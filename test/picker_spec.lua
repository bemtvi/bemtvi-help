-- The topic picker: the source streams tags, confirm opens the topic, and bare
-- :help opens the picker. Run with `nxvim --test-plugin`.

local help = require("nxvim-help")
local picker = require("nxvim-help.picker")
local index = require("nxvim-help.index")
local window = require("nxvim-help.window")

-- Collect what the source pushes, with a fake ctx.
local function collect_items()
  local pushed = {}
  nx.await(picker.items({
    push = function(it)
      pushed[#pushed + 1] = it
    end,
  }))
  return pushed
end

nx.test.describe("nxvim-help picker", function()
  nx.test.before_each(function()
    window._reset()
    index._index = nil -- fresh runtimepath scan
    help.setup()
  end)

  nx.test.after_each(function()
    window._reset()
  end)

  nx.test.it("streams all tags as sorted items carrying their entry", function()
    local items = collect_items()
    nx.test.expect(#items >= 1).to_be_truthy()
    local texts, found = {}, nil
    for _, it in ipairs(items) do
      texts[#texts + 1] = it.text
      if it.entry.name == "nxvim-help-usage" then
        found = it
      end
    end
    -- the known topic is present and carries a resolvable entry
    nx.test.expect(found).to_be_truthy()
    nx.test.expect(found.entry.name).to_be("nxvim-help-usage")
    -- the display text is `tag  file`: starts with the tag, ends with the help file
    nx.test.expect(found.text:sub(1, #"nxvim-help-usage")).to_be("nxvim-help-usage")
    nx.test.expect(found.text).to_contain(found.entry.file:match("([^/]+)$"))
    -- sorted ascending (the fixed-width tag padding preserves tag order)
    for i = 2, #texts do
      nx.test.expect(texts[i - 1] <= texts[i]).to_be_truthy()
    end
    -- carries the location-preview data: path = its file, row = its anchor line
    nx.test.expect(found.path).to_be(found.entry.file)
    local text = nx.await(nx.fs.read_text(found.path))
    local lines = {}
    for ln in (text .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = ln
    end
    nx.test.expect(lines[found.row]).to_contain("*nxvim-help-usage*")
  end)

  nx.test.it("confirm opens the chosen topic in the help window", function(t)
    local idx = nx.await(index.ensure())
    picker.confirm({ text = "nxvim-help-usage", entry = idx["nxvim-help-usage"] })
    local txt = t:wait_for(function()
      local b = window.bufnr()
      if not b then
        return nil
      end
      local s = table.concat(nx.buf.lines(b, 0, -1, false), "\n")
      -- Assert on the resolved tag, not the rendered header casing.
      return s:find("nxvim-help-usage", 1, true) and s
    end)
    nx.test.expect(txt).to_contain("nxvim-help-usage")
  end)

  nx.test.it("bare :help opens the topic picker", function(t)
    t:feed(":help<CR>")
    -- the picker is server-owned; nx._picker is set while one is open and its
    -- source streams our tags into it.
    t:wait_for(function()
      return nx._picker ~= nil
    end)
    local items = t:wait_for(function()
      local it = nx._picker and nx._picker.items
      return it and #it >= 1 and it
    end)
    nx.test.expect(#items >= 1).to_be_truthy()
    -- the picker is opened with a location preview pane
    nx.test.expect(nx._picker.preview).to_be("location")
  end)
end)
