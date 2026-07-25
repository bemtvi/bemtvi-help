-- Tag following: tag_at extraction (pure) and the follow/back e2e. Run with
-- `nxvim --test-plugin`.

local help = require("nxvim-help")
local tagstack = require("nxvim-help.tagstack")
local window = require("nxvim-help.window")
local index = require("nxvim-help.index")

nx.test.describe("nxvim-help.tagstack.tag_at", function()
  -- col is 0-based, like nx.cursor.get().
  nx.test.it("returns the inner text of a |hot-link| under the cursor", function()
    local line = "see |nxvim-help-usage| now"
    nx.test.expect(tagstack.tag_at(line, 8)).to_be("nxvim-help-usage") -- inside the link
  end)

  nx.test.it("returns the inner text of a *target* under the cursor", function()
    local line = "HEAD\t\t*nxvim-help* *nxvim-help-intro*"
    nx.test.expect(tagstack.tag_at(line, 8)).to_be("nxvim-help")
  end)

  nx.test.it("falls back to the word under the cursor, trimming punctuation", function()
    nx.test.expect(tagstack.tag_at("a foo-bar.", 4)).to_be("foo-bar")
  end)

  nx.test.it("returns nil on a separator", function()
    nx.test.expect(tagstack.tag_at("a | b", 1)).to_be_falsy() -- on the space
  end)
end)

nx.test.describe("nxvim-help.tagstack follow/back", function()
  nx.test.before_each(function()
    window._reset()
    tagstack._reset()
    index.invalidate()
    help.setup()
  end)

  nx.test.after_each(function()
    window._reset()
    tagstack._reset()
  end)

  nx.test.it("follows the tag under the cursor and <C-t> returns", function(t)
    help.help("nxvim-help") -- front page
    t:wait_for(function()
      local c = window.current()
      return c and c.name == "nxvim-help"
    end)
    -- put the cursor on the first "nxvim-help-usage" (the |hot-link| in the intro)
    t:feed("/nxvim-help-usage<CR>")
    t:feed("<C-]>")
    local jumped = t:wait_for(function()
      local c = window.current()
      return c and c.name == "nxvim-help-usage" and c
    end)
    nx.test.expect(jumped.name).to_be("nxvim-help-usage")

    t:feed("<C-t>")
    local back = t:wait_for(function()
      local c = window.current()
      return c and c.name == "nxvim-help" and c
    end)
    nx.test.expect(back.name).to_be("nxvim-help")
  end)

  nx.test.it("<C-t> restores the exact column, not just the line", function(t)
    help.help("nxvim-help") -- front page
    t:wait_for(function()
      local c = window.current()
      return c and c.name == "nxvim-help"
    end)
    -- land on a hot-link mid-line, so the from-position has a non-zero column.
    t:feed("/nxvim-help-usage<CR>")
    local from = t:wait_for(function()
      local p = nx.cursor.get()
      return p[2] > 0 and p -- non-zero column, else this test proves nothing
    end)

    t:feed("<C-]>")
    t:wait_for(function()
      local c = window.current()
      return c and c.name == "nxvim-help-usage"
    end)

    t:feed("<C-t>")
    -- back on the front page AND on the exact (line, col) the follow jumped from.
    local pos = t:wait_for(function()
      local c = window.current()
      if not (c and c.name == "nxvim-help") then
        return nil
      end
      local p = nx.cursor.get()
      return p[1] == from[1] and p[2] == from[2] and p
    end)
    nx.test.expect(pos[1]).to_be(from[1])
    nx.test.expect(pos[2]).to_be(from[2])
  end)
end)
