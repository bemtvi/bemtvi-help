-- Help-buffer highlighting: opening a topic places extmarks for tags, links,
-- headings and delimiters. Run with `nxvim --test-plugin`.

local help = require("nxvim-help")
local window = require("nxvim-help.window")
local highlight = require("nxvim-help.highlight")
local index = require("nxvim-help.index")

-- The set of hl_groups currently marked on `buf` under our namespace.
local function marked_groups(buf)
  local groups = {}
  for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
    local d = mk[4]
    if d and d.hl_group then
      groups[d.hl_group] = true
    end
  end
  return groups
end

nx.test.describe("nxvim-help highlight", function()
  nx.test.before_each(function()
    window._reset()
    index._index = nil
    help.setup()
  end)

  nx.test.after_each(function()
    window._reset()
  end)

  nx.test.it("marks tags, links, headings and delimiters when a topic opens", function(t)
    help.help("nxvim-help") -- the front page has all four
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    local groups = t:wait_for(function()
      local g = marked_groups(buf)
      -- wait until highlighting has been applied (it lands a tick after the buffer)
      return next(g) and g
    end)
    nx.test.expect(groups["nxHelpTag"]).to_be_truthy()
    nx.test.expect(groups["nxHelpLink"]).to_be_truthy()
    nx.test.expect(groups["nxHelpHeadline"]).to_be_truthy()
    nx.test.expect(groups["nxHelpDelim"]).to_be_truthy()
  end)

  nx.test.it("renders a >lua … < code block: conceals markers, marks the code", function(t)
    -- A fixture doc with a fenced example; drive window.show directly against it.
    local dir = nx.test.tempdir()
    local file = dir .. "/topic.txt"
    nx.await(nx.fs.write(
      file,
      table.concat({
        "*topic*  A topic.",
        "",
        "Use it like this: >lua",
        "  local x = nx.foo()",
        "<Back to prose.",
      }, "\n")
    ))
    window.show({ file = file, name = "topic" })

    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    -- markers are gone from the displayed text
    local lines = t:wait_for(function()
      local ls = nx.buf.lines(buf, 0, -1, false)
      return ls[3] == "Use it like this:" and ls
    end)
    nx.test.expect(lines[3]).to_be("Use it like this:") -- `>lua` concealed
    nx.test.expect(lines[5]).to_be("Back to prose.") -- leading `<` concealed

    -- the code line carries the code-block highlight
    local groups = t:wait_for(function()
      local g = {}
      for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        if mk[2] == 3 then -- the `local x = ...` code row (0-based)
          local d = mk[4]
          if d and d.hl_group then
            g[d.hl_group] = true
          end
          if d and d.line_hl_group then
            g[d.line_hl_group] = true
          end
        end
      end
      return next(g) and g
    end)
    nx.test.expect(groups["nxHelpCode"]).to_be_truthy()
    nx.test.expect(groups["nxHelpCodeBlock"]).to_be_truthy()
  end)

  nx.test.it("token-highlights a >lua block body by its fence language", function(t)
    -- Needs the `lua` tree-sitter grammar installed; the off-buffer highlighter
    -- returns nothing without it, so skip rather than fail (the external-dependency
    -- convention). The probe doubles as proof the API is wired.
    local probe = nx.await(nx.treesitter.highlight("lua", "local x = 1\n"))
    if #probe == 0 then
      return
    end
    local dir = nx.test.tempdir()
    local file = dir .. "/topic.txt"
    nx.await(nx.fs.write(
      file,
      table.concat({
        "*topic*  A topic.",
        "",
        "Use it like this: >lua",
        "  local y = require('mod')",
        "<Back to prose.",
      }, "\n")
    ))
    window.show({ file = file, name = "topic" })
    local buf = t:wait_for(function()
      return window.bufnr()
    end)

    -- The `local` keyword on the code row (0-based 3) carries a `@keyword` extmark —
    -- a group that can ONLY come from the injected lua highlighter, never the plugin's
    -- flat `nxHelpCode`. Async (the overlay awaits the highlight promise), so poll.
    local kw = t:wait_for(function()
      for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        if mk[2] == 3 and mk[4] and mk[4].hl_group == "@keyword" then
          -- `local` starts at byte column 2 (two-space indent).
          return mk[3] == 2 and mk
        end
      end
      return nil
    end)
    nx.test.expect(kw).to_be_truthy()

    -- The flat code base and block background survive under the tokens (the code row
    -- keeps `nxHelpCode` / `nxHelpCodeBlock` — the token overlay only adds marks).
    local groups = {}
    for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
      if mk[2] == 3 then
        local d = mk[4] or {}
        if d.hl_group then
          groups[d.hl_group] = true
        end
        if d.line_hl_group then
          groups[d.line_hl_group] = true
        end
      end
    end
    nx.test.expect(groups["nxHelpCode"]).to_be_truthy()
    nx.test.expect(groups["nxHelpCodeBlock"]).to_be_truthy()
  end)

  nx.test.it("marks a *target* span at its exact byte columns", function(t)
    help.help("nxvim-help")
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    -- wait for marks, then slice each nxHelpTag span out of its line and confirm it
    -- is exactly a *…* run (columns line up).
    local sliced = t:wait_for(function()
      local found = {}
      for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        local row, col, d = mk[2], mk[3], mk[4]
        if d and d.hl_group == "nxHelpTag" then
          local line = nx.buf.lines(buf, row, row + 1, false)[1] or ""
          found[#found + 1] = line:sub(col + 1, d.end_col)
        end
      end
      return #found > 0 and found
    end)
    for _, s in ipairs(sliced) do
      nx.test.expect(s:sub(1, 1)).to_be("*")
      nx.test.expect(s:sub(-1)).to_be("*")
    end
  end)
end)
