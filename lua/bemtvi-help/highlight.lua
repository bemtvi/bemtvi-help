-- bemtvi-help.highlight — syntax highlighting for the help buffer via extmarks.
--
-- Help files are small, static and read-only, so we mark every line once per show
-- (clearing our namespace first) rather than running a live decoration provider.
-- Groups link to standard groups so any colorscheme styles them.

local helptags = require("bemtvi-help.helptags")
local util = require("bemtvi-help.util")

local M = {}

M.ns = btv.ns.create("bemtvi-help")

-- The paint generation. Every repaint of the help buffer bumps it, and the async
-- per-language token overlay carries the generation it was started for: when a second
-- `:help` lands while the tree-sitter highlight of the first is still in flight, the
-- resolved spans belong to a document that is no longer on screen, so they are dropped
-- instead of painted at rows and columns that now hold different text.
M._gen = 0

local function bump()
  M._gen = M._gen + 1
  return M._gen
end

-- Linked groups: a colorscheme that defines Title/Comment/Label/Identifier/String
-- (essentially all of them) styles help for free.
btv.hl.define(0, "btvHelpHeadline", { link = "Title" }) -- UPPERCASE section headings
btv.hl.define(0, "btvHelpDelim", { link = "Comment" }) -- ==== / ---- rules
btv.hl.define(0, "btvHelpTag", { link = "Label" }) -- *target*
btv.hl.define(0, "btvHelpLink", { link = "Identifier" }) -- |hot-link|
btv.hl.define(0, "btvHelpCode", { link = "String" }) -- `code`
btv.hl.define(0, "btvHelpCodeBlock", { link = "@markup.raw.block" }) -- >lua … < example bg

local function mark(buf, row, s, e, group)
  -- s/e are 1-based inclusive (string.find); extmark cols are 0-based, end exclusive.
  btv.buf.set_extmark(buf, M.ns, row, s - 1, { end_row = row, end_col = e, hl_group = group })
end

-- Mark every occurrence of `pat` on `line` (row `row`) with `group`.
local function scan(buf, row, line, pat, group)
  local i = 1
  while true do
    local s, e = line:find(pat, i)
    if not s then
      return
    end
    mark(buf, row, s, e, group)
    i = e + 1
  end
end

-- Place all highlights for `lines` on `buf` (clearing the namespace first). `code`
-- (optional) is a set of 0-based rows that are fenced example content — those rows get
-- the code-block highlight and skip the prose scans (a `*foo*` inside code is not a tag).
-- Returns the paint generation, which `apply_tokens` takes to detect being superseded.
function M.apply(buf, lines, code)
  code = code or {}
  local gen = bump()
  btv.buf.clear_namespace(buf, M.ns, 0, -1)
  for i, line in ipairs(lines) do
    local row = i - 1
    if code[row] then
      -- Full-width block background plus a code foreground over the visible text.
      btv.buf.set_extmark(buf, M.ns, row, 0, { line_hl_group = "btvHelpCodeBlock" })
      if #line > 0 then
        mark(buf, row, 1, #line, "btvHelpCode")
      end
    else
      if line:find("^==+") or line:find("^%-%-%-+") then
        mark(buf, row, 1, #line, "btvHelpDelim")
      else
        -- A section heading, keyed on the vimdoc STRUCTURE rather than an ALL-CAPS
        -- run: text at column 1 followed by a right-aligned *tag* at end of line
        -- ("Table of Contents  *…*", "1. Commands  *…*", "SUBSECTION  *…*"), or an
        -- H3-style "TITLE ~". Structure, not caps, because panvimdoc titles are
        -- numbered / mixed-case, and a caps run in prose (e.g. a line opening with
        -- "LSP") is not a heading. Table-of-contents ENTRIES end in `|link|`, not a
        -- tag, so they are correctly excluded.
        local htext = line:match("^(%S.-)%s%s+%*[^\t]+%*%s*$") or line:match("^(%S.-) ~$")
        if htext then
          mark(buf, row, 1, #htext, "btvHelpHeadline")
        end
      end
      -- Tags come from the shared vimdoc scanner rather than a loose `*…*` pattern, so
      -- the highlight marks exactly what the INDEX considers a tag — otherwise a bold
      -- run or a backticked mention paints as a tag that `<C-]>` then can't resolve.
      for _, s, e in helptags.line_targets(line) do
        mark(buf, row, s, e, "btvHelpTag")
      end
      scan(buf, row, line, "|[^| \t]+|", "btvHelpLink")
      scan(buf, row, line, "`[^`]+`", "btvHelpCode")
    end
  end
  return gen
end

-- Priority for the per-language token marks, above the flat `btvHelpCode` base so a
-- `>lua` block's real lua tokens (keyword, string, …) paint over the flat colour on
-- the cells they cover; the un-captured cells keep the flat code colour. Extmarks
-- default to priority 4096 (as `btvHelpCode` does), so the tokens sit just above it.
local TOKEN_PRIORITY = 4200

-- Overlay per-language syntax highlighting on each fenced code block's body, the way
-- neovim's tree-sitter injection colours a `>lua` example. For every block that names
-- a language, the body text is highlighted via `btv.treesitter.highlight` (the native
-- off-buffer highlighter) and each returned span placed as an extmark over the block's
-- rows — displayed text equals the raw text on code rows (only fence *markers* are
-- concealed), so a span's byte columns are the extmark columns directly. Async (the
-- highlight is a promise); a language with no installed grammar returns no spans, so
-- the block simply keeps its flat `btvHelpCode` colour. `gen` is the paint generation
-- these blocks belong to (defaulting to the current one): if a later repaint bumps it
-- while a block's highlight is in flight, the overlay stops rather than marking up the
-- document that replaced it. Returns a promise.
function M.apply_tokens(buf, lines, blocks, gen)
  return btv.async(function()
    gen = gen or M._gen
    for _, b in ipairs(blocks or {}) do
      if b.lang and b.lang ~= "" and b.first then
        local body = {}
        for r = b.first, b.last do
          body[#body + 1] = lines[r + 1]
        end
        local spans = btv.await(btv.treesitter.highlight(b.lang, table.concat(body, "\n")))
        if gen ~= M._gen then
          return -- superseded while the highlight ran; these spans are stale
        end
        for _, sp in ipairs(spans) do
          if sp.col_end > sp.col_start then
            -- The engine reports tree-sitter capture names (`keyword`, `function.call`);
            -- the `@`-prefixed group is what a colorscheme styles.
            btv.buf.set_extmark(buf, M.ns, b.first + sp.line, sp.col_start, {
              end_row = b.first + sp.line,
              end_col = sp.col_end,
              hl_group = "@" .. sp.group,
              priority = TOKEN_PRIORITY,
            })
          end
        end
      end
    end
  end)()
end

-- Apply to a view's buffer once it exists. The backing buffer arrives via the mirror
-- a tick after the view is created, so the first show must wait for it (btv.wait_for
-- returns at once when it's already known). Places the base marks synchronously, then
-- overlays the per-language code-block tokens (async, off the base paint). Returns a
-- promise (settled once the base marks are placed and the token overlay is kicked off).
function M.apply_to_view(view, lines, code, blocks)
  return btv.async(function()
    -- Claim the paint up front: a `:help` issued while we wait on the buffer bumps the
    -- generation, and painting THIS document's marks afterwards would show the wrong
    -- text's colouring.
    local claim = bump()
    local buf = view:bufnr()
      or btv.await(btv.wait_for(function()
        return view:bufnr()
      end, { tries = 100, interval = 5, message = "help buffer never appeared" }))
    if claim ~= M._gen then
      return
    end
    local gen = M.apply(buf, lines, code)
    -- Don't block the show on the token overlay; surface a failure rather than swallow.
    M.apply_tokens(buf, lines, blocks, gen):catch(function(e)
      btv.notify("bemtvi-help: code highlight failed: " .. util.errmsg(e), 3)
    end)
  end)()
end

return M
