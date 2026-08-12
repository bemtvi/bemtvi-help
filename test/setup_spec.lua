-- setup() option handling: the maps it owns are re-applied (and withdrawn) on every
-- call, and the index is built once no matter how many callers race for it. Run with
-- `bemtvi --test-plugin`.

local help = require("bemtvi-help")
local index = require("bemtvi-help.index")

-- Is `lhs` currently a global normal-mode map? `lhs` is the LEADER-EXPANDED form,
-- which is what the keymap registry stores.
local function mapped(lhs)
  for _, m in ipairs(btv.keymap.get("n")) do
    if m.lhs == lhs then
      return true
    end
  end
  return false
end

btv.test.describe("bemtvi-help setup", function()
  btv.test.before_each(function()
    vim.g.mapleader = ","
  end)

  btv.test.after_each(function()
    -- leave the default maps in place for the other suites
    help.setup()
  end)

  btv.test.it("search_keymap = false withdraws the map a previous setup bound", function()
    -- The auto-loader (plugin/bemtvi-help.lua) calls setup() with defaults BEFORE a
    -- user's own setup runs, so `search_keymap = false` has to be able to undo it —
    -- otherwise the documented "false disables it" never takes effect.
    help.setup()
    btv.test.expect(mapped(",fh")).to_be(true)
    help.setup({ search_keymap = false })
    btv.test.expect(mapped(",fh")).to_be(false)
  end)

  btv.test.it("search_keymap = <lhs> moves the map instead of leaving both", function()
    help.setup()
    help.setup({ search_keymap = ",hh" })
    btv.test.expect(mapped(",hh")).to_be(true)
    btv.test.expect(mapped(",fh")).to_be(false)
  end)

  btv.test.it("keywordprg toggles K off again", function()
    help.setup({ keywordprg = true })
    btv.test.expect(mapped("K")).to_be(true)
    help.setup({ keywordprg = false })
    btv.test.expect(mapped("K")).to_be(false)
  end)

  btv.test.it("concurrent ensure() calls share one build", function()
    -- Two callers racing for the index (a `:help` and the picker source, say) used to
    -- each kick off a full runtimepath scan — every doc file read twice.
    local real = index.build
    local builds = 0
    index.build = function()
      builds = builds + 1
      return real()
    end
    index.invalidate()
    local a, b = index.ensure(), index.ensure()
    btv.await(a)
    btv.await(b)
    index.build = real
    btv.test.expect(builds).to_be(1)
  end)

  btv.test.it("invalidate() forces the next ensure() to rebuild", function()
    local first = btv.await(index.ensure())
    btv.test.expect(btv.await(index.ensure()) == first).to_be(true) -- cached
    index.invalidate()
    btv.test.expect(btv.await(index.ensure()) == first).to_be(false) -- rebuilt
  end)
end)
