-- nxvim-help.window — render a resolved help entry in a read-only split.
--
-- The help buffer is an `nx.view` (the sanctioned read-only, mountable line surface):
-- we read the target `.txt`, set its lines, mount it in a split, and jump the cursor
-- to the tag's `*anchor*` via `View:set_cursor` (the one sanctioned cursor write).
-- A singleton handle is reused across `:help` calls so a second lookup reuses the
-- same window instead of stacking splits.

local highlight = require("nxvim-help.highlight")
local render = require("nxvim-help.render")

local M = {}

local view = nil -- the singleton help view handle
local current = nil -- the entry currently displayed (for the tag stack)

-- The 1-based line of the `*tag*` anchor in `lines`, or 1 if absent. Vim's tag
-- address is a `/*tag*` search; for phase 1 we locate the literal anchor directly.
local function anchor_line(lines, tag)
  local needle = "*" .. tag .. "*"
  for i, l in ipairs(lines) do
    if l:find(needle, 1, true) then
      return i
    end
  end
  return 1
end

-- Split text into lines without a synthetic trailing blank from a final newline.
local function split_lines(text)
  local out = {}
  local start = 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then
      if #text >= start then
        out[#out + 1] = text:sub(start)
      end
      break
    end
    out[#out + 1] = text:sub(start, nl - 1)
    start = nl + 1
  end
  return out
end

-- Open `entry` in the help split. Jumps to `line` if given (used to restore position
-- when popping the tag stack), else to the tag's `*anchor*`. `col` (0-based) refines
-- the cursor to an exact column — the tag stack passes it so `<C-t>` lands back on the
-- precise spot a follow jumped from, not just its line. Async (reads the file).
function M.show(entry, line, col)
  return nx.async(function()
    local text = nx.await(nx.fs.read_text(entry.file))
    -- Render code fences (conceal the `>`/`>lua`/`<` markers) before display; line
    -- count is preserved so the anchor/tag-stack line addressing stays aligned.
    local rendered = render.prepare(split_lines(text))
    local lines = rendered.lines
    -- A cached handle can go stale behind our back: `:bd` of the help buffer destroys
    -- the view (its bufnr mirror clears), and `:q` closes its window (winid clears)
    -- without telling us. Drop a dead handle so we recreate it, and decide mount vs
    -- focus from the *live* winid rather than a flag we'd fail to update on `:q`.
    if view and not view:bufnr() then
      view = nil
      current = nil
    end
    if not view then
      view = nx.view.create({ name = "[Help]", filetype = "help" })
    end
    view:set_lines(lines)
    if view:winid() then
      view:focus()
    else
      view:mount({ split = "split" })
    end
    local target = line or anchor_line(lines, entry.name)
    view:set_cursor(target) -- focuses the view and lands on the line (column 0)
    -- nx.view's cursor is line-granular; refine to the exact byte column when asked,
    -- via the public cursor setter (1-based row, 0-based col).
    if col and col > 0 and view:winid() then
      nx.cursor.set({ target, col }, view:winid())
    end
    current = entry
    -- Syntax highlighting (cosmetic): apply once the backing buffer exists. Don't
    -- block the show on it; surface a failure rather than swallowing it.
    highlight.apply_to_view(view, lines, rendered.code):catch(function(e)
      nx.notify(
        "nxvim-help: highlight failed: " .. tostring(type(e) == "table" and e.message or e),
        4
      )
    end)
    return view
  end)()
end

-- The entry currently displayed (nil before first show), so the tag stack can record
-- where a jump came from.
function M.current()
  return current
end

-- Close the help split (keeps the handle for reuse). unmount is a no-op when the
-- view isn't currently shown, so no mounted flag to track.
function M.close()
  if view then
    view:unmount()
  end
end

-- ----- test seams -------------------------------------------------------------

-- The help view's backing buffer number (nil before first show), for tests.
function M.bufnr()
  return view and view:bufnr()
end

-- The help view's 1-based cursor line (nil while unfocused), for tests.
function M.line()
  return view and view:line()
end

-- Tear down the singleton entirely so a test starts from a clean slate.
function M._reset()
  if view then
    view:close()
  end
  view = nil
  current = nil
end

return M
