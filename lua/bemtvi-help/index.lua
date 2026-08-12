-- bemtvi-help.index — discover and parse help tag files across the runtimepath.
--
-- Help "registration" is by convention, exactly like neovim: any plugin that ships
-- a `doc/` directory with a `tags` file (its *targets* indexed as
-- `tag<TAB>file<TAB>address` lines) is on the runtimepath via :Plugins, so
-- `btv.runtime_file("doc/tags", true)` finds every one of them — this plugin's own
-- docs included. No plugin calls an API to register; it just drops `doc/` in its
-- repo. The parsed, merged index maps a tag -> { file = <absolute .txt path>, name =
-- <tag> }; the first occurrence in runtimepath order wins, matching vim's "first
-- tags file" precedence.

local helptags = require("bemtvi-help.helptags")
local util = require("bemtvi-help.util")

local M = {}

-- The merged tag -> entry map, built lazily on first :help and cached. nil until built.
M._index = nil

-- The in-flight build promise, so two callers racing for the index (a `:help` and the
-- picker source opening together) share ONE runtimepath scan instead of each reading
-- every doc file. Cleared when the build settles.
local building = nil

-- Parse one tags file's text into `out` (tag -> entry), resolving each `file` column
-- against `dir`. Skips blank lines and ctags `!_TAG_` header pragmas. The first
-- writer of a tag wins (runtimepath precedence), so a later file never clobbers an
-- earlier tag.
function M.parse_into(out, text, dir)
  for _, line in ipairs(util.split_lines(text)) do
    if line ~= "" and line:sub(1, 1) ~= "!" then
      local tag, file = line:match("^([^\t]+)\t([^\t]+)\t")
      if tag and file and not out[tag] then
        out[tag] = { file = dir .. "/" .. file, name = tag }
      end
    end
  end
  return out
end

-- Build an index from an explicit list of tags-file paths. Async because reading each
-- file goes through the promise filesystem; an unreadable tags file is skipped (not
-- fatal — another plugin's docs should still resolve). Returns a promise of the map.
-- Factored out of build() so a test can drive it against a temp dir without the rtp.
function M.build_from(tag_files)
  return btv.async(function()
    local out = {}
    for _, tf in ipairs(tag_files or {}) do
      local ok, text = pcall(btv.await, btv.fs.read_text(tf))
      if ok and text then
        M.parse_into(out, text, btv.utils.dirname(tf))
      end
    end
    return out
  end)()
end

-- Build an in-memory index for a single doc/ dir by scanning its `*.txt` for targets
-- — no tags file needed. Async; returns a promise of a tag -> entry map (first
-- occurrence of a tag within the dir wins). build() uses this for dirs that ship docs
-- without a generated tags file; it is also the directly testable seam.
function M.scan_dir(dir)
  return btv.async(function()
    local out = {}
    local entries = btv.await(btv.fs.readdir(dir))
    table.sort(entries, function(a, b)
      return a.name < b.name
    end)
    for _, e in ipairs(entries) do
      if e.type ~= "directory" and e.name:sub(-4) == ".txt" then
        local text = btv.await(btv.fs.read_text(dir .. "/" .. e.name))
        for _, tag in ipairs(helptags.targets(text)) do
          if not out[tag] then
            out[tag] = { file = dir .. "/" .. e.name, name = tag }
          end
        end
      end
    end
    return out
  end)()
end

-- Build (or rebuild) the index from the runtimepath, then cache it. On-disk
-- `doc/tags` files are the fast, authoritative source; any doc/ dir that ships `.txt`
-- but no tags file is scanned directly (helptags.targets), so help works even when a
-- plugin never generated a tags file. A tag already provided by a tags file wins over
-- a derived one. Returns a promise of the index table.
function M.build()
  return btv.async(function()
    local out = {}
    local has_tags = {} -- dir -> true (a tags file already covered this dir)
    for _, tf in ipairs(btv.runtime_file("doc/tags", true) or {}) do
      local ok, text = pcall(btv.await, btv.fs.read_text(tf))
      if ok and text then
        local dir = btv.utils.dirname(tf)
        has_tags[dir] = true
        M.parse_into(out, text, dir)
      end
    end
    -- doc/ dirs with .txt but no tags file: derive targets directly.
    local seen_dir = {}
    for _, txt in ipairs(btv.runtime_file("doc/*.txt", true) or {}) do
      local dir = btv.utils.dirname(txt)
      if not has_tags[dir] and not seen_dir[dir] then
        seen_dir[dir] = true
        local derived = btv.await(M.scan_dir(dir))
        for tag, entry in pairs(derived) do
          if not out[tag] then
            out[tag] = entry
          end
        end
      end
    end
    M._index = out
    return out
  end)()
end

-- Drop the cached index so the next `ensure()` rescans the runtimepath — after
-- `:BtvHelptags` writes new tags files, or when a test wants a fresh scan.
function M.invalidate()
  M._index = nil
  building = nil
end

-- The index, building it on first use. Promise of the tag -> entry map. Concurrent
-- callers share the in-flight build rather than each starting their own.
function M.ensure()
  return btv.async(function()
    if M._index then
      return M._index
    end
    if not building then
      building = M.build()
    end
    -- Every waiter awaits the SAME promise and clears the slot on the way out, so a
    -- failed scan doesn't wedge a rejected promise in place and the next `:help`
    -- retries. `pcall` around the await keeps the rejection propagating unchanged.
    local ok, res = pcall(btv.await, building)
    building = nil
    if not ok then
      error(res, 0)
    end
    return res
  end)()
end

-- Resolve a topic to an entry: an exact tag first, then the best prefix match
-- (shortest tag, then lexicographic) so `:help btv.vi` finds `btv.view`. Returns the
-- entry or nil.
function M.lookup(index, topic)
  if index[topic] then
    return index[topic]
  end
  local best
  for tag, entry in pairs(index) do
    if tag:sub(1, #topic) == topic then
      if not best or #tag < #best.name or (#tag == #best.name and tag < best.name) then
        best = entry
      end
    end
  end
  return best
end

return M
