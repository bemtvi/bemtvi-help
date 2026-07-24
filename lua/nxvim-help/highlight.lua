-- nxvim-help.highlight — syntax highlighting for the help buffer via extmarks.
--
-- Help files are small, static and read-only, so we mark every line once per show
-- (clearing our namespace first) rather than running a live decoration provider.
-- Groups link to standard groups so any colorscheme styles them.

local M = {}

M.ns = nx.ns.create("nxvim-help")

-- Linked groups: a colorscheme that defines Title/Comment/Label/Identifier/String
-- (essentially all of them) styles help for free.
nx.hl.define(0, "nxHelpHeadline", { link = "Title" }) -- UPPERCASE section headings
nx.hl.define(0, "nxHelpDelim", { link = "Comment" }) -- ==== / ---- rules
nx.hl.define(0, "nxHelpTag", { link = "Label" }) -- *target*
nx.hl.define(0, "nxHelpLink", { link = "Identifier" }) -- |hot-link|
nx.hl.define(0, "nxHelpCode", { link = "String" }) -- `code`
nx.hl.define(0, "nxHelpCodeBlock", { link = "@markup.raw.block" }) -- >lua … < example bg

local function mark(buf, row, s, e, group)
  -- s/e are 1-based inclusive (string.find); extmark cols are 0-based, end exclusive.
  nx.buf.set_extmark(buf, M.ns, row, s - 1, { end_row = row, end_col = e, hl_group = group })
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
function M.apply(buf, lines, code)
  code = code or {}
  nx.buf.clear_namespace(buf, M.ns, 0, -1)
  for i, line in ipairs(lines) do
    local row = i - 1
    if code[row] then
      -- Full-width block background plus a code foreground over the visible text.
      nx.buf.set_extmark(buf, M.ns, row, 0, { line_hl_group = "nxHelpCodeBlock" })
      if #line > 0 then
        mark(buf, row, 1, #line, "nxHelpCode")
      end
    else
      if line:find("^==+") or line:find("^%-%-%-+") then
        mark(buf, row, 1, #line, "nxHelpDelim")
      else
        -- A leading run of UPPERCASE words is a section headline ("NXVIM HELP").
        local hs, he = line:find("^[A-Z][A-Z0-9 ]*[A-Z0-9]")
        if hs then
          mark(buf, row, hs, he, "nxHelpHeadline")
        end
      end
      scan(buf, row, line, '%*[^ \t*"]+%*', "nxHelpTag")
      scan(buf, row, line, "|[^| \t]+|", "nxHelpLink")
      scan(buf, row, line, "`[^`]+`", "nxHelpCode")
    end
  end
end

-- Priority for the per-language token marks, above the flat `nxHelpCode` base so a
-- `>lua` block's real lua tokens (keyword, string, …) paint over the flat colour on
-- the cells they cover; the un-captured cells keep the flat code colour. Extmarks
-- default to priority 4096 (as `nxHelpCode` does), so the tokens sit just above it.
local TOKEN_PRIORITY = 4200

-- Overlay per-language syntax highlighting on each fenced code block's body, the way
-- neovim's tree-sitter injection colours a `>lua` example. For every block that names
-- a language, the body text is highlighted via `nx.treesitter.highlight` (the native
-- off-buffer highlighter) and each returned span placed as an extmark over the block's
-- rows — displayed text equals the raw text on code rows (only fence *markers* are
-- concealed), so a span's byte columns are the extmark columns directly. Async (the
-- highlight is a promise); a language with no installed grammar returns no spans, so
-- the block simply keeps its flat `nxHelpCode` colour. Returns a promise.
function M.apply_tokens(buf, lines, blocks)
  return nx.async(function()
    for _, b in ipairs(blocks or {}) do
      if b.lang and b.lang ~= "" and b.first then
        local body = {}
        for r = b.first, b.last do
          body[#body + 1] = lines[r + 1]
        end
        local spans = nx.await(nx.treesitter.highlight(b.lang, table.concat(body, "\n")))
        for _, sp in ipairs(spans) do
          if sp.col_end > sp.col_start then
            -- The engine reports tree-sitter capture names (`keyword`, `function.call`);
            -- the `@`-prefixed group is what a colorscheme styles.
            nx.buf.set_extmark(buf, M.ns, b.first + sp.line, sp.col_start, {
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
-- a tick after the view is created, so the first show must wait for it (nx.wait_for
-- returns at once when it's already known). Places the base marks synchronously, then
-- overlays the per-language code-block tokens (async, off the base paint). Returns a
-- promise (settled once the base marks are placed and the token overlay is kicked off).
function M.apply_to_view(view, lines, code, blocks)
  return nx.async(function()
    local buf = view:bufnr()
      or nx.await(nx.wait_for(function()
        return view:bufnr()
      end, { tries = 100, interval = 5, message = "help buffer never appeared" }))
    M.apply(buf, lines, code)
    -- Don't block the show on the token overlay; surface a failure rather than swallow.
    M.apply_tokens(buf, lines, blocks):catch(function(e)
      nx.notify("nxvim-help: code highlight failed: " .. tostring(e), 3)
    end)
  end)()
end

return M
