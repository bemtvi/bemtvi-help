-- End-to-end :help: discover this plugin's own doc/ on the runtimepath, then open a
-- topic in the help split and land on its tag anchor. Run with `nxvim --test-plugin`.
--
-- This exercises the real mechanism the unit specs stub out: rtp discovery via
-- nx.runtime_file (the neovim-identical "drop doc/ in a plugin" path) and the
-- nx.view-backed window.

local help = require("nxvim-help")
local index = require("nxvim-help.index")
local window = require("nxvim-help.window")

-- The joined text of the help view buffer right now (or "" before it exists).
local function buf_text()
  local b = window.bufnr()
  if not b then
    return ""
  end
  return table.concat(nx.buf.lines(b, 0, -1, false), "\n")
end

-- Wait until the help buffer contains `needle`, returning the text.
local function wait_contains(t, needle)
  return t:wait_for(function()
    local txt = buf_text()
    return txt:find(needle, 1, true) and txt
  end)
end

nx.test.describe("nxvim-help window", function()
  nx.test.before_each(function()
    window._reset()
    index._index = nil -- force a fresh runtimepath scan
    help.setup()
  end)

  nx.test.after_each(function()
    window._reset()
  end)

  nx.test.it("discovers its own docs on the runtimepath (no tags file needed)", function()
    -- nxvim-help ships no doc/tags; the index derives targets from doc/*.txt.
    local txts = nx.runtime_file("doc/*.txt", true)
    nx.test.expect(#txts >= 1).to_be_truthy()
    local idx = nx.await(index.build())
    nx.test.expect(idx["nxvim-help"]).to_be_truthy()
    nx.test.expect(idx["nxvim-help-usage"]).to_be_truthy()
  end)

  nx.test.it("opens :help {topic} and lands on the tag anchor", function(t)
    -- Drive the real :help command: core defers it, the server sees the plugin's
    -- user command is registered, and runs it (the installed-plugin path).
    t:feed(":help nxvim-help-usage<CR>")
    -- Wait on the resolved tag, not the rendered header casing.
    wait_contains(t, "nxvim-help-usage")
    -- the cursor settles on the anchor line a tick later
    local line = t:wait_for(function()
      return window.line()
    end)
    local lines = nx.buf.lines(window.bufnr(), 0, -1, false)
    nx.test.expect(lines[line]).to_contain("nxvim-help-usage")
  end)

  nx.test.it("prefix-resolves a partial topic", function(t)
    help.help("nxvim-help-reg")
    nx.test.expect(wait_contains(t, "nxvim-help-registering")).to_contain("nxvim-help-registering")
  end)
end)
