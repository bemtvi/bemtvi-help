-- setup() option handling: the maps it owns are re-applied (and withdrawn) on every
-- call, and the index is built once no matter how many callers race for it. Run with
-- `nxvim --test-plugin`.

local help = require("nxvim-help")
local index = require("nxvim-help.index")

-- Is `lhs` currently a global normal-mode map? `lhs` is the LEADER-EXPANDED form,
-- which is what the keymap registry stores.
local function mapped(lhs)
  for _, m in ipairs(nx.keymap.get("n")) do
    if m.lhs == lhs then
      return true
    end
  end
  return false
end

nx.test.describe("nxvim-help setup", function()
  nx.test.before_each(function()
    vim.g.mapleader = ","
  end)

  nx.test.after_each(function()
    -- leave the default maps in place for the other suites
    help.setup()
  end)

  nx.test.it("search_keymap = false withdraws the map a previous setup bound", function()
    -- The auto-loader (plugin/nxvim-help.lua) calls setup() with defaults BEFORE a
    -- user's own setup runs, so `search_keymap = false` has to be able to undo it —
    -- otherwise the documented "false disables it" never takes effect.
    help.setup()
    nx.test.expect(mapped(",fh")).to_be(true)
    help.setup({ search_keymap = false })
    nx.test.expect(mapped(",fh")).to_be(false)
  end)

  nx.test.it("search_keymap = <lhs> moves the map instead of leaving both", function()
    help.setup()
    help.setup({ search_keymap = ",hh" })
    nx.test.expect(mapped(",hh")).to_be(true)
    nx.test.expect(mapped(",fh")).to_be(false)
  end)

  nx.test.it("keywordprg toggles K off again", function()
    help.setup({ keywordprg = true })
    nx.test.expect(mapped("K")).to_be(true)
    help.setup({ keywordprg = false })
    nx.test.expect(mapped("K")).to_be(false)
  end)

  nx.test.it("concurrent ensure() calls share one build", function()
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
    nx.await(a)
    nx.await(b)
    index.build = real
    nx.test.expect(builds).to_be(1)
  end)

  nx.test.it("invalidate() forces the next ensure() to rebuild", function()
    local first = nx.await(index.ensure())
    nx.test.expect(nx.await(index.ensure()) == first).to_be(true) -- cached
    index.invalidate()
    nx.test.expect(nx.await(index.ensure()) == first).to_be(false) -- rebuilt
  end)
end)
