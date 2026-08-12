-- Tag following: tag_at extraction (pure) and the follow/back e2e. Run with
-- `bemtvi --test-plugin`.

local help = require("bemtvi-help")
local tagstack = require("bemtvi-help.tagstack")
local window = require("bemtvi-help.window")
local index = require("bemtvi-help.index")

btv.test.describe("bemtvi-help.tagstack.tag_at", function()
  -- col is 0-based, like btv.cursor.get().
  btv.test.it("returns the inner text of a |hot-link| under the cursor", function()
    local line = "see |bemtvi-help-usage| now"
    btv.test.expect(tagstack.tag_at(line, 8)).to_be("bemtvi-help-usage") -- inside the link
  end)

  btv.test.it("returns the inner text of a *target* under the cursor", function()
    local line = "HEAD\t\t*bemtvi-help* *bemtvi-help-intro*"
    btv.test.expect(tagstack.tag_at(line, 8)).to_be("bemtvi-help")
  end)

  btv.test.it("falls back to the word under the cursor, trimming punctuation", function()
    btv.test.expect(tagstack.tag_at("a foo-bar.", 4)).to_be("foo-bar")
  end)

  btv.test.it("returns nil on a separator", function()
    btv.test.expect(tagstack.tag_at("a | b", 1)).to_be_falsy() -- on the space
  end)
end)

btv.test.describe("bemtvi-help.tagstack follow/back", function()
  btv.test.before_each(function()
    window._reset()
    tagstack._reset()
    index.invalidate()
    help.setup()
  end)

  btv.test.after_each(function()
    window._reset()
    tagstack._reset()
  end)

  btv.test.it("follows the tag under the cursor and <C-t> returns", function(t)
    help.help("bemtvi-help") -- front page
    t:wait_for(function()
      local c = window.current()
      return c and c.name == "bemtvi-help"
    end)
    -- put the cursor on the first "bemtvi-help-usage" (the |hot-link| in the intro)
    t:feed("/bemtvi-help-usage<CR>")
    t:feed("<C-]>")
    local jumped = t:wait_for(function()
      local c = window.current()
      return c and c.name == "bemtvi-help-usage" and c
    end)
    btv.test.expect(jumped.name).to_be("bemtvi-help-usage")

    t:feed("<C-t>")
    local back = t:wait_for(function()
      local c = window.current()
      return c and c.name == "bemtvi-help" and c
    end)
    btv.test.expect(back.name).to_be("bemtvi-help")
  end)

  btv.test.it("<C-t> restores the exact column, not just the line", function(t)
    help.help("bemtvi-help") -- front page
    t:wait_for(function()
      local c = window.current()
      return c and c.name == "bemtvi-help"
    end)
    -- land on a hot-link mid-line, so the from-position has a non-zero column.
    t:feed("/bemtvi-help-usage<CR>")
    local from = t:wait_for(function()
      local p = btv.cursor.get()
      return p[2] > 0 and p -- non-zero column, else this test proves nothing
    end)

    t:feed("<C-]>")
    t:wait_for(function()
      local c = window.current()
      return c and c.name == "bemtvi-help-usage"
    end)

    t:feed("<C-t>")
    -- back on the front page AND on the exact (line, col) the follow jumped from.
    local pos = t:wait_for(function()
      local c = window.current()
      if not (c and c.name == "bemtvi-help") then
        return nil
      end
      local p = btv.cursor.get()
      return p[1] == from[1] and p[2] == from[2] and p
    end)
    btv.test.expect(pos[1]).to_be(from[1])
    btv.test.expect(pos[2]).to_be(from[2])
  end)
end)
