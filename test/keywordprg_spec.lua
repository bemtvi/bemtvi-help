-- K / keywordprg: open help for the word under the cursor. Run with
-- `nxvim --test-plugin`.

local help = require("nxvim-help")
local window = require("nxvim-help.window")
local index = require("nxvim-help.index")

local function buf_text(b)
  return table.concat(nx.buf.lines(b, 0, -1, false), "\n")
end

nx.test.describe("nxvim-help keywordprg (K)", function()
  nx.test.before_each(function()
    window._reset()
    index._index = nil
    help.setup({ keywordprg = true })
  end)

  nx.test.after_each(function()
    window._reset()
  end)

  nx.test.it("K opens help for the (dotted/hyphenated) word under the cursor", function(t)
    -- type a known tag, put the cursor on it (col 0). <cWORD> grabs the whole token,
    -- which <cword> could not (it stops at '-').
    t:feed("inxvim-help-usage<Esc>0")
    t:feed("K")
    local txt = t:wait_for(function()
      local b = window.bufnr()
      if not b then
        return nil
      end
      local s = buf_text(b)
      -- Assert on the structural tag the topic resolves to, not the rendered
      -- header casing (which is a doc-presentation detail, not this behavior).
      return s:find("nxvim-help-usage", 1, true) and s
    end)
    nx.test.expect(txt).to_contain("nxvim-help-usage")
  end)

  nx.test.it("help_cword with no word under the cursor opens nothing", function(t)
    -- empty buffer line → no <cWORD>
    help.help_cword()
    t:feed("") -- settle a tick
    nx.test.expect(window.bufnr()).to_be_falsy()
  end)
end)
