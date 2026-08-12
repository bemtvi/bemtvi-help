-- bemtvi-help.helptags — extract *targets* from help text and (optionally) write a
-- vim-style `doc/tags` file, like vim's :helptags.
--
-- A generated `tags` file is *optional*: the index (index.lua) derives the same
-- targets directly from `doc/*.txt` for any dir that lacks one, so help works with
-- zero setup. Writing the file is an interop/speed convenience — vim and other tools
-- can read it, and parsing one tab-separated file is cheaper than scanning every .txt.
--
-- bemtvi core owns `:helptags` (a stub), so this exposes generation as a Lua function
-- and the non-colliding `:BtvHelptags` command instead.

local render = require("bemtvi-help.render")
local util = require("bemtvi-help.util")

local M = {}

-- This module is the ONE definition of what a help target is: the index derives tags
-- with it, the picker locates anchors with it, and the highlighter paints tag spans
-- with it. It mirrors vim's own scanner (`helptags_one` in src/nvim/help.c), whose
-- rules are stricter than "a `*…*` pair" in two ways that matter:
--
--   1. A target must be WHITESPACE-DELIMITED — the opening `*` at column 1 or after a
--      space/tab, the closing `*` followed by whitespace or end-of-line — and its body
--      may not contain a space, tab or `|`. Without this, every inline mention becomes
--      a tag: markdown bold (`**bold**`), a backticked `` `*targets*` ``, a C
--      dereference (`int *p*`). A doc that merely writes ABOUT help tags would then
--      squat on generic topics like `tag` and `target` for the whole runtimepath.
--   2. Targets inside a `>` CODE EXAMPLE are skipped. `*ptr*` in sample code is code.
--
-- `line_targets` is the per-line span form (what the highlighter needs, since it marks
-- byte columns); `each_target` walks a whole file with the example rule applied.

-- Iterate the targets on ONE line as `tag, s, e` — the inner text, then the 1-based
-- inclusive byte offsets of the whole `*…*` run (what the highlighter marks). Usage:
-- `for tag, s, e in helptags.line_targets(line) do`.
function M.line_targets(line)
  local i = 1
  return function()
    while true do
      local s = line:find("*", i, true)
      if not s then
        return nil
      end
      local e = line:find("*", s + 1, true)
      if not e then
        return nil
      end
      -- vim retries the pair search from the SECOND `*` of a rejected candidate, and
      -- from the one after it on a match.
      i = e
      if e > s + 1 then -- skip `*` and `**` (an empty body)
        local body = line:sub(s + 1, e - 1)
        local before = s == 1 or line:find("^[ \t]", s - 1) ~= nil
        local after = e == #line or line:find("^[ \t\r]", e + 1) ~= nil
        if before and after and not body:find("[ \t|]") then
          i = e + 1
          return body, s, e
        end
      end
    end
  end
end

-- Call `fn(tag, row)` for every target in `text`, in file order, with `row` its 1-based
-- line. Lines inside a `>` … code example are skipped: a line ending in a fence marker
-- opens one (the same test `render.strip_start` applies for display), and any line
-- starting in column 1 closes it — vim's `in_example` walk exactly.
function M.each_target(text, fn)
  local in_example = false
  local row = 0
  for _, line in ipairs(util.split_lines(text)) do
    row = row + 1
    -- An example body is any blank or indented line while a fence is open; it carries
    -- no tags and cannot itself open the next fence.
    local example_body = in_example and (line == "" or line:find("^[ \t]") ~= nil)
    if not example_body then
      for tag in M.line_targets(line) do
        fn(tag, row)
      end
      in_example = render.strip_start(line) ~= nil
    end
  end
end

-- Every `*target*` on `text`, in file order (duplicates within the file preserved for
-- the caller to report).
function M.targets(text)
  local out = {}
  M.each_target(text, function(tag)
    out[#out + 1] = tag
  end)
  return out
end

-- Every target's anchor line in `text`, as tag -> 1-based row (first occurrence wins).
-- One pass for the whole file, which is what the picker needs to position its preview
-- for every topic that lives in a given doc.
function M.target_rows(text)
  local rows = {}
  M.each_target(text, function(tag, row)
    if not rows[tag] then
      rows[tag] = row
    end
  end)
  return rows
end

-- Escape a tag for the `/…/` search address column: only the chars that would break
-- the search — backslash and the slash delimiter. Mirrors vim's loose form
-- (`/*quickref.txt*` leaves the `.` unescaped).
local function esc(tag)
  return (tag:gsub("[\\/]", "\\%0"))
end

-- The unique doc/ directories on the runtimepath that ship help text — i.e. the dirs
-- :BtvHelptags (no arg / ALL) regenerates. Derived from the `doc/*.txt` glob, so a dir
-- with only a stale tags file (no .txt) is skipped (nothing to regenerate from).
function M.doc_dirs()
  local seen, out = {}, {}
  for _, p in ipairs(btv.runtime_file("doc/*.txt", true) or {}) do
    local dir = btv.utils.dirname(p)
    if not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  return out
end

-- Generate `dir/tags` from every `dir/*.txt`. Async. Returns
-- { count = <#tags>, dupes = { <tag>, … }, files = <#txt> }. A duplicate tag (same
-- tag in two files, or twice in one) keeps the first and is reported — surfaced loud
-- by the caller, never silently dropped (matching vim's "duplicate tag" warning).
-- `dupes` names each offending tag ONCE (a tag repeated five times is one problem, not
-- five), so the caller's message stays readable.
function M.generate(dir)
  return btv.async(function()
    dir = dir:gsub("/+$", "") -- a trailing slash would write `dir//tags`
    local entries = btv.await(btv.fs.readdir(dir))
    local names = {}
    for _, e in ipairs(entries) do
      if e.type ~= "directory" and e.name:sub(-4) == ".txt" then
        names[#names + 1] = e.name
      end
    end
    table.sort(names)

    local seen = {} -- tag -> first file
    local reported = {} -- tag -> true (already in `dupes`)
    local dupes = {}
    local tags = {} -- { { tag, file }, … }
    for _, name in ipairs(names) do
      local text = btv.await(btv.fs.read_text(dir .. "/" .. name))
      for _, tag in ipairs(M.targets(text)) do
        if seen[tag] then
          if not reported[tag] then
            reported[tag] = true
            dupes[#dupes + 1] = tag
          end
        else
          seen[tag] = name
          tags[#tags + 1] = { tag, name }
        end
      end
    end
    -- vim writes the tags file sorted (it binary-searches it).
    table.sort(tags, function(a, b)
      return a[1] < b[1]
    end)

    local lines = {}
    for _, t in ipairs(tags) do
      lines[#lines + 1] = t[1] .. "\t" .. t[2] .. "\t/*" .. esc(t[1]) .. "*"
    end
    local body = #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
    btv.await(btv.fs.write(dir .. "/tags", body))
    return { count = #tags, dupes = dupes, files = #names }
  end)()
end

return M
