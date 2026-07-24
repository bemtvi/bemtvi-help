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

-- Apply to a view's buffer once it exists. The backing buffer arrives via the mirror
-- a tick after the view is created, so the first show must wait for it (nx.wait_for
-- returns at once when it's already known). Returns a promise.
function M.apply_to_view(view, lines, code)
  return nx.async(function()
    local buf = view:bufnr()
      or nx.await(nx.wait_for(function()
        return view:bufnr()
      end, { tries = 100, interval = 5, message = "help buffer never appeared" }))
    M.apply(buf, lines, code)
  end)()
end

return M
