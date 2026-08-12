-- K / keywordprg: open help for the word under the cursor. Run with
-- `bemtvi --test-plugin`.

local help = require("bemtvi-help")
local window = require("bemtvi-help.window")
local index = require("bemtvi-help.index")

local function buf_text(b)
  return table.concat(btv.buf.lines(b, 0, -1, false), "\n")
end

btv.test.describe("bemtvi-help keywordprg (K)", function()
  btv.test.before_each(function()
    window._reset()
    index.invalidate()
    help.setup({ keywordprg = true })
  end)

  btv.test.after_each(function()
    window._reset()
  end)

  btv.test.it("K opens help for the (dotted/hyphenated) word under the cursor", function(t)
    -- type a known tag, put the cursor on it (col 0). <cWORD> grabs the whole token,
    -- which <cword> could not (it stops at '-').
    t:feed("ibemtvi-help-usage<Esc>0")
    t:feed("K")
    local txt = t:wait_for(function()
      local b = window.bufnr()
      if not b then
        return nil
      end
      local s = buf_text(b)
      -- Assert on the structural tag the topic resolves to, not the rendered
      -- header casing (which is a doc-presentation detail, not this behavior).
      return s:find("bemtvi-help-usage", 1, true) and s
    end)
    btv.test.expect(txt).to_contain("bemtvi-help-usage")
  end)

  btv.test.it("help_cword with no word under the cursor opens nothing", function(t)
    -- empty buffer line → no <cWORD>
    help.help_cword()
    t:feed("") -- settle a tick
    btv.test.expect(window.bufnr()).to_be_falsy()
  end)

  btv.test.it("K resolves a punctuated tag verbatim before trying the trimmed word", function(t)
    -- Option tags carry their quotes (`*'number'*`) and key tags their brackets
    -- (`*CTRL-]*`). Unconditionally trimming punctuation off <cWORD> destroyed those:
    -- `'number'` became `number`, which resolves elsewhere or to E149. The raw token
    -- must be tried first, with the trimmed form only as a fallback.
    local dir = btv.test.tempdir()
    local quoted = dir .. "/quoted.txt"
    btv.await(btv.fs.write(quoted, "*'number'*\tthe quoted option topic\n"))
    index._index = { ["'number'"] = { file = quoted, name = "'number'" } }

    t:feed("i'number'<Esc>0")
    help.help_cword()
    local txt = t:wait_for(function()
      local b = window.bufnr()
      if not b then
        return nil
      end
      local s = buf_text(b)
      return s:find("the quoted option topic", 1, true) and s
    end)
    btv.test.expect(txt).to_contain("the quoted option topic")
  end)

  btv.test.it("K still falls back to the trimmed word for surrounding punctuation", function(t)
    -- `(btv.view)` / `|tag|` must still resolve: nothing indexes the punctuated form,
    -- so the trimmed candidate carries the lookup.
    local dir = btv.test.tempdir()
    local plain = dir .. "/plain.txt"
    btv.await(btv.fs.write(plain, "*btv.view*\tthe bare topic body\n"))
    index._index = { ["btv.view"] = { file = plain, name = "btv.view" } }

    t:feed("i(btv.view)<Esc>0")
    help.help_cword()
    local txt = t:wait_for(function()
      local b = window.bufnr()
      if not b then
        return nil
      end
      local s = buf_text(b)
      return s:find("the bare topic body", 1, true) and s
    end)
    btv.test.expect(txt).to_contain("the bare topic body")
  end)
end)
