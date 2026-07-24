-- Help-window lifecycle: surviving the user closing it with :q, or deleting the
-- hidden help buffer with :bd. Run with `nxvim --test-plugin`.
--
-- Regression for: open help → :q (window hidden) → :help wouldn't reshow; then :bd
-- the hidden buffer → the next :help panicked the editor.

local help = require("nxvim-help")
local window = require("nxvim-help.window")
local index = require("nxvim-help.index")

local function shows(t, needle)
  return t:wait_for(function()
    local b = window.bufnr()
    if not b then
      return nil
    end
    local s = table.concat(nx.buf.lines(b, 0, -1, false), "\n")
    return s:find(needle, 1, true) and s
  end)
end

nx.test.describe("nxvim-help window lifecycle", function()
  nx.test.before_each(function()
    window._reset()
    index._index = nil
    help.setup()
  end)

  nx.test.after_each(function()
    window._reset()
  end)

  nx.test.it("reopens after the help window is closed with :q", function(t)
    help.help("nxvim-help")
    -- Wait on the resolved tag (intro page), not the rendered header text.
    shows(t, "nxvim-help-intro")
    -- the help window is focused after show; close it like the user
    t:feed(":q<CR>")
    -- opening another topic must reshow (remount), not focus a closed window
    help.help("nxvim-help-usage")
    nx.test.expect(shows(t, "nxvim-help-usage")).to_contain("nxvim-help-usage")
  end)

  nx.test.it("recovers (no panic) after the help buffer is :bd-deleted", function(t)
    help.help("nxvim-help")
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    t:feed(":q<CR>") -- hide it
    t:feed(":bd! " .. buf .. "<CR>") -- delete the hidden help buffer
    -- the next open must not panic and must show (the handle is recreated)
    help.help("nxvim-help-usage")
    nx.test.expect(shows(t, "nxvim-help-usage")).to_contain("nxvim-help-usage")
  end)
end)
