-- bemtvi-help.util — the plugin-private glue every module shares.
--
-- Nothing here is help-specific enough for `btv.utils.*` (the path helpers this plugin
-- needs already live there — `btv.utils.dirname` / `btv.utils.basename`), and nothing
-- here belongs to one module, so it lives in one place instead of three copies.

local M = {}

-- Run an async body, surfacing any rejection as an error notification rather than an
-- unhandled promise error. Every entry point the user can trigger (`:help`, `K`, a
-- picker confirm, a tag jump) funnels through this, so a failure is always loud.
function M.run(body)
  btv.async(body)():catch(function(e)
    btv.notify("bemtvi-help: " .. M.errmsg(e), 4)
  end)
end

-- The human-readable text of a rejection value (a promise rejects with either an
-- error table carrying `.message` or a plain string).
function M.errmsg(e)
  return tostring(type(e) == "table" and e.message or e)
end

-- Split file text into display lines: no synthetic trailing blank from a final
-- newline, and no `\r` left behind by a CRLF checkout (a stray carriage return would
-- otherwise defeat every end-of-line match — the `>lua` fence, the right-aligned
-- heading tag — and show up as a control glyph on every row).
function M.split_lines(text)
  local out = {}
  local start = 1
  while true do
    local nl = text:find("\n", start, true)
    local stop = nl and nl - 1 or #text
    if not nl and stop < start then
      break -- a trailing newline: nothing after it
    end
    local line = text:sub(start, stop)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    out[#out + 1] = line
    if not nl then
      break
    end
    start = nl + 1
  end
  return out
end

-- Strip leading and trailing whitespace.
function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

return M
