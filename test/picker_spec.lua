-- The topic picker: the source streams tags, confirm opens the topic, and bare
-- :help opens the picker. Run with `bemtvi --test-plugin`.

local help = require("bemtvi-help")
local picker = require("bemtvi-help.picker")
local index = require("bemtvi-help.index")
local window = require("bemtvi-help.window")

-- Collect what the source pushes, with a fake ctx.
local function collect_items()
  local pushed = {}
  btv.await(picker.items({
    push = function(it)
      pushed[#pushed + 1] = it
    end,
  }))
  return pushed
end

btv.test.describe("bemtvi-help picker", function()
  btv.test.before_each(function()
    window._reset()
    index.invalidate()
    help.setup()
  end)

  btv.test.after_each(function()
    window._reset()
  end)

  btv.test.it("streams all tags as sorted items carrying their entry", function()
    local items = collect_items()
    btv.test.expect(#items >= 1).to_be_truthy()
    local heads, found = {}, nil
    for _, it in ipairs(items) do
      heads[#heads + 1] = it.head
      if it.entry.name == "bemtvi-help-usage" then
        found = it
      end
    end
    -- the known topic is present and carries a resolvable entry
    btv.test.expect(found).to_be_truthy()
    btv.test.expect(found.entry.name).to_be("bemtvi-help-usage")
    -- a two-column row: the tag is the head the widget aligns, its help file the body.
    -- Declared columns, not a padded string, so an over-long tag can't push the file
    -- column off the row.
    btv.test.expect(found.head).to_be("bemtvi-help-usage  ")
    btv.test.expect(found.text).to_be(found.entry.file:match("([^/]+)$"))
    -- sorted ascending
    for i = 2, #heads do
      btv.test.expect(heads[i - 1] <= heads[i]).to_be_truthy()
    end
    -- carries the location-preview data: path = its file, row = its anchor line
    btv.test.expect(found.path).to_be(found.entry.file)
    local text = btv.await(btv.fs.read_text(found.path))
    local lines = {}
    for ln in (text .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = ln
    end
    btv.test.expect(lines[found.row]).to_contain("*bemtvi-help-usage*")
  end)

  btv.test.it("confirm opens the chosen topic in the help window", function(t)
    local idx = btv.await(index.ensure())
    picker.confirm({ head = "bemtvi-help-usage  ", entry = idx["bemtvi-help-usage"] })
    local txt = t:wait_for(function()
      local b = window.bufnr()
      if not b then
        return nil
      end
      local s = table.concat(btv.buf.lines(b, 0, -1, false), "\n")
      -- Assert on the resolved tag, not the rendered header casing.
      return s:find("bemtvi-help-usage", 1, true) and s
    end)
    btv.test.expect(txt).to_contain("bemtvi-help-usage")
  end)

  btv.test.it("bare :help opens the topic picker", function(t)
    t:feed(":help<CR>")
    -- the picker is server-owned; btv._picker is set while one is open and its
    -- source streams our tags into it.
    t:wait_for(function()
      return btv._picker ~= nil
    end)
    local items = t:wait_for(function()
      local it = btv._picker and btv._picker.items
      return it and #it >= 1 and it
    end)
    btv.test.expect(#items >= 1).to_be_truthy()
    -- the picker is opened with a location preview pane
    btv.test.expect(btv._picker.preview).to_be("location")
  end)

  btv.test.it("<leader>fh opens the topic picker (help search)", function(t)
    -- setup() binds <leader>fh to the picker (bare :help). Rebind under a known
    -- leader so we can drive it, then feed the sequence.
    vim.g.mapleader = ","
    help.setup()
    t:feed(",fh")
    t:wait_for(function()
      return btv._picker ~= nil
    end)
    btv.test.expect(btv._picker ~= nil).to_be_truthy()
    t:feed("<Esc>") -- dismiss the picker
  end)
end)
