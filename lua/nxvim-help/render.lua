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

-- If `line` is a code-fence START, return it with the trailing `>`/`>lang` marker
-- removed; otherwise nil. The marker is the last `>` followed only by `[a-z0-9]` to the
-- end of the line, provided that `>` sits at column 1 or just after a space (vim's
-- `\%(^\| \)` prefix). The preceding space is stripped with it (vim conceals ` >`).
function M.strip_start(line)
  local s = line:find(">[%l%d]*$")
  if not s then
    return nil
  end
  if s == 1 then
    return "" -- a bare `>` / `>lua` line collapses to blank
  end
  if line:sub(s - 1, s - 1) == " " then
    return line:sub(1, s - 2)
  end
  return nil -- `>` mid-token (e.g. `a=>b`) is prose, not a fence
end

-- Prepare `raw` (the file split into lines) for display. Returns
--   { lines = <rendered lines>, code = { [row0] = true, … } }
-- where `code` flags the 0-based rows that are fenced example content (for the code
-- highlight). Fence markers are concealed in `lines`; every input line maps to exactly
-- one output line, so `#lines == #raw`.
function M.prepare(raw)
  local lines = {}
  local code = {}
  local in_block = false
  for i = 1, #raw do
    local line = raw[i]
    local row = i - 1
    if in_block then
      if line:sub(1, 1) == "<" then
        -- Closing marker: drop the leading `<`; the rest of the line is normal prose.
        lines[i] = line:sub(2)
        in_block = false
      elseif line ~= "" and not line:find("^[ \t]") then
        -- A non-blank line starting in column 1 ends the block *before* itself; this
        -- line is prose (and may itself open the next fence).
        local opened = M.strip_start(line)
        lines[i] = opened or line
        in_block = opened ~= nil
      else
        -- Indented or blank: example content.
        lines[i] = line
        code[row] = true
      end
    else
      local opened = M.strip_start(line)
      lines[i] = opened or line
      in_block = opened ~= nil
    end
  end
  return { lines = lines, code = code }
end

return M
