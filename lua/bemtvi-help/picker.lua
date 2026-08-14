-- bemtvi-help.picker — fuzzy-find a help topic with btv.picker.
--
-- This is the primary discovery UX: bare `:help` (no topic) opens a picker over every
-- known tag, fuzzy-matched as you type; <CR> opens the highlighted topic. It replaces
-- vim's command-line tag completion (bemtvi user commands have no completer hook) with
-- something better.

local helptags = require("bemtvi-help.helptags")
local index = require("bemtvi-help.index")
local util = require("bemtvi-help.util")
local window = require("bemtvi-help.window")

local M = {}

-- Anchor rows (`helptags.target_rows`) memoized per help file, valid for one index
-- build: the tags don't move while the index they came from is current, so reopening
-- the picker doesn't re-read and re-scan every doc file. Keyed on the index table's
-- identity — a rebuild mints a new one, which drops the whole cache. Scanning a file
-- once for ALL of its tags also replaces the old per-tag search, which cost a `find`
-- plus a newline count over the whole prefix for every single tag.
local cache = { idx = nil, rows = {} }

local function rows_for(idx, file)
  if cache.idx ~= idx then
    cache = { idx = idx, rows = {} }
  end
  if not cache.rows[file] then
    local ok, text = pcall(btv.await, btv.fs.read_text(file))
    cache.rows[file] = helptags.target_rows((ok and text) or "")
  end
  return cache.rows[file]
end

-- Stream every known tag as a picker item — a TWO-COLUMN row: `head` is the tag and
-- the body is its help file, so the widget aligns the file column itself (to the
-- widest tag actually listed, capped at a share of the row) and keeps both columns
-- when a row overflows. The matcher still sees the whole row, so you can narrow by
-- help file as well as by tag. `entry` carries its index entry for confirm;
-- `path`/`row`/`col` drive the "location" preview (the file scrolled to the tag's
-- anchor). Sorted for a stable list. Async: builds the index, then reads each doc file
-- once to locate anchors.
function M.items(ctx)
  return btv.async(function()
    local idx = btv.await(index.ensure())
    local tags = {}
    for tag in pairs(idx) do
      tags[#tags + 1] = tag
    end
    table.sort(tags)
    for _, tag in ipairs(tags) do
      local entry = idx[tag]
      ctx.push({
        head = tag .. "  ",
        text = btv.utils.basename(entry.file) or entry.file,
        entry = entry,
        path = entry.file,
        row = rows_for(idx, entry.file)[tag] or 1,
        col = 1,
      })
    end
  end)()
end

-- Open the chosen topic in the help window.
function M.confirm(item)
  util.run(function()
    btv.await(window.show(item.entry))
  end)
end

-- Register the source (idempotent — keyed by name; a re-require overwrites). Named
-- bemtvi_help so it can't clash with a built-in source. Single-choice: `<Tab>` marking
-- a batch of topics would have nothing to act on, since confirm opens exactly one.
btv.picker.source({
  name = "bemtvi_help",
  items = M.items,
  confirm = M.confirm,
  title = "Help Topics",
  multiselect = false,
  preview = "location", -- preview the doc scrolled to the highlighted topic
})

-- Open the help-topic picker.
function M.open()
  btv.picker.open("bemtvi_help")
end

return M
