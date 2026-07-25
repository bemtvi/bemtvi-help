-- nxvim-help.render — turn raw help text into the lines we actually display,
-- concealing vim's code-fence markers the way neovim's help syntax does.
--
-- Vim marks a code example with a fence: a line ending in `>` (optionally `>lua`,
-- `>vim`, … — a language tag) opens it, and a line whose first column is `<` (or the
-- next line that starts in column 1) closes it. neovim conceals the `>` / `>lua` / `<`
-- markers so you never see them; nxvim has no conceal yet, so we do the equivalent by
-- rewriting those marker characters out of the displayed text. Line COUNT is preserved
-- (we only edit within a line, never drop one) so tag anchors and the <C-t> tag stack —
-- which address the buffer by line/column — stay exactly aligned.
--
-- The mirror of vim's `help.vim` region:
--   start  \%(^\| \)>[a-z0-9]*$      (`>` at BOL or after a space, then a language tag)
--   end    ^[^ \t]  (before it)  OR  ^<   (that `<` consumed)
-- Blank lines do NOT end a block (they stay inside it), matching vim.

local M = {}

-- The longest common leading substring of `a` and `b` (both leading-whitespace runs).
local function common_prefix(a, b)
  local n, max = 0, math.min(#a, #b)
  while n < max and a:byte(n + 1) == b:byte(n + 1) do
    n = n + 1
  end
  return a:sub(1, n)
end

-- If `line` is a code-fence START, return `(stripped, lang)` — the line with the
-- trailing `>`/`>lang` marker removed, plus the fence language (`"lua"` for `>lua`,
-- `""` for a bare `>`); otherwise nil. The marker is the last `>` followed only by
-- `[a-z0-9]` to the end of the line, provided that `>` sits at column 1 or just after
-- a space (vim's `\%(^\| \)` prefix). The preceding space is stripped with it (vim
-- conceals ` >`). `lang` drives the per-language token highlighting of the block body.
function M.strip_start(line)
  local s = line:find(">[%l%d]*$")
  if not s then
    return nil
  end
  local lang = line:sub(s + 1) -- "" for a bare `>`
  if s == 1 then
    return "", lang -- a bare `>` / `>lua` line collapses to blank
  end
  if line:sub(s - 1, s - 1) == " " then
    return line:sub(1, s - 2), lang
  end
  return nil -- `>` mid-token (e.g. `a=>b`) is prose, not a fence
end

-- Prepare `raw` (the file split into lines) for display. Returns
--   { lines = <rendered lines>, code = { [row0] = true, … },
--     blocks = { { lang = <string>, first = <row0>, last = <row0> }, … } }
-- where `code` flags the 0-based rows that are fenced example content (for the flat
-- code highlight) and `blocks` describes each fenced example (its language and its
-- 0-based inclusive body-row range) for the per-language token overlay. Fence markers
-- are concealed in `lines`; every input line maps to exactly one output line, so
-- `#lines == #raw`.
function M.prepare(raw)
  local lines = {}
  local code = {}
  local blocks = {}
  local in_block = false
  local cur = nil -- the open block's { lang, first, last } (nil between blocks)
  -- Close the open block, recording it only if it had at least one body row (a `>`
  -- immediately followed by `<` has no body and needs no token overlay).
  local function close()
    if cur and cur.first then
      blocks[#blocks + 1] = cur
    end
    cur = nil
  end
  -- Note a fenced-example body row on the open block (extends its row range).
  local function mark_body(row)
    code[row] = true
    if cur then
      cur.first = cur.first or row
      cur.last = row
    end
  end
  -- Emit `line` as prose, opening a fence if it ends in one. Used for every row that
  -- is NOT example content: outside a block, the column-1 line that ends one, and the
  -- remainder of a `<` closing line (`<Then try: >lua` both closes and reopens).
  local function prose(i, line)
    local opened, lang = M.strip_start(line)
    lines[i] = opened or line
    in_block = opened ~= nil
    cur = in_block and { lang = lang } or nil
  end
  for i = 1, #raw do
    local line = raw[i]
    local row = i - 1
    if in_block then
      if line:sub(1, 1) == "<" then
        -- Closing marker: drop the leading `<`; the rest of the line is normal prose.
        close()
        prose(i, line:sub(2))
      elseif line ~= "" and not line:find("^[ \t]") then
        -- A non-blank line starting in column 1 ends the block *before* itself; this
        -- line is prose (and may itself open the next fence).
        close()
        prose(i, line)
      else
        -- Indented or blank: example content.
        lines[i] = line
        mark_body(row)
      end
    else
      prose(i, line)
    end
  end
  close() -- an unclosed block running to end-of-file

  -- Dedent each fenced block by its own common leading indentation, so the code sits
  -- flush against the block's left edge (it renders on its own background) rather than
  -- at vim's fixed example indent — panvimdoc prefixes every `>` body line with 4
  -- spaces. Relative indentation within the block is preserved: we strip the longest
  -- common whitespace PREFIX (as a string, over the rows that have real content), not
  -- a character count, so a block mixing tabs and spaces has no common prefix and is
  -- left alone rather than shifted by a tab's worth of the wrong whitespace. Blank rows
  -- stay blank. Only code-body columns shift; tags/links are never scanned on code
  -- rows, so anchor addressing is unaffected (and line count is untouched).
  for _, b in ipairs(blocks) do
    local prefix
    for row = b.first, b.last do
      local ws, rest = lines[row + 1]:match("^([ \t]*)(.*)$")
      if rest ~= "" then
        prefix = prefix and common_prefix(prefix, ws) or ws
        if prefix == "" then
          break
        end
      end
    end
    if prefix and prefix ~= "" then
      for row = b.first, b.last do
        lines[row + 1] = lines[row + 1]:sub(#prefix + 1)
      end
    end
  end

  return { lines = lines, code = code, blocks = blocks }
end

return M
