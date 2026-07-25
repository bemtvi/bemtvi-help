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
    index.invalidate()
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

  nx.test.it("marks structural headings (tagged / ~) but not ALL-CAPS prose", function(t)
    -- panvimdoc headings are numbered / mixed-case with a right-aligned *tag*
    -- ("1. Commands  *topic-commands*", "Table of Contents  *topic-toc*"), or an
    -- H3-style "TITLE ~". A caps run in PROSE ("LSP-hover …") is NOT a heading —
    -- the old ALL-CAPS heuristic wrongly flagged it and missed the real headings.
    local dir = nx.test.tempdir()
    local file = dir .. "/topic.txt"
    nx.await(nx.fs.write(
      file,
      table.concat({
        "*topic.txt*  A topic.", -- row 0: title line (not a section heading)
        "", -- 1
        "==============================================================================", -- 2: delim
        "Table of Contents                                          *topic-toc*", -- 3: heading
        "", -- 4
        "1. Commands                                           *topic-commands*", -- 5: heading
        "", -- 6
        "SUBSECTION ~", -- 7: H3-style heading
        "", -- 8
        "LSP-hover K stays out of the way by default.", -- 9: caps PROSE, not a heading
      }, "\n")
    ))
    window.show({ file = file, name = "topic" })
    local buf = t:wait_for(function()
      return window.bufnr()
    end)

    -- Rows carrying each group (wait until highlighting has landed).
    local by_row = t:wait_for(function()
      local rows, any = {}, false
      for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        local g = mk[4] and mk[4].hl_group
        if g then
          rows[mk[2]] = rows[mk[2]] or {}
          rows[mk[2]][g] = true
          any = true
        end
      end
      return any and rows
    end)
    local function has(row, group)
      return (by_row[row] and by_row[row][group]) or false
    end

    -- The three real headings are headlines…
    nx.test.expect(has(3, "nxHelpHeadline")).to_be(true) -- Table of Contents
    nx.test.expect(has(5, "nxHelpHeadline")).to_be(true) -- 1. Commands
    nx.test.expect(has(7, "nxHelpHeadline")).to_be(true) -- SUBSECTION ~
    -- …the delimiter is marked…
    nx.test.expect(has(2, "nxHelpDelim")).to_be(true)
    -- …and the ALL-CAPS-prefixed PROSE line is NOT a headline.
    nx.test.expect(has(9, "nxHelpHeadline")).to_be(false)
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
          -- `local` starts at byte column 0: render.prepare dedents the block's
          -- common (two-space) indent, so the code sits flush at the left.
          return mk[3] == 0 and mk
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

  nx.test.it("drops a superseded token overlay instead of painting it on the new doc", function(t)
    -- Regression: `apply_tokens` awaits the (async) tree-sitter highlight per block.
    -- If a second `:help` repaints the buffer while that await is in flight, the
    -- resolved spans used to land on the NEW document — stale `@`-group marks at rows
    -- and columns belonging to the previous one. A generation guard must drop them.
    local probe = nx.await(nx.treesitter.highlight("lua", "local x = 1\n"))
    if #probe == 0 then
      return -- no lua grammar installed; nothing to overlay (external-dep convention)
    end
    -- A fence-free doc, just to obtain a live help buffer with enough rows/columns.
    local dir = nx.test.tempdir()
    local file = dir .. "/plain.txt"
    local plain = {
      "*plain*  A doc.",
      "",
      "just prose here",
      "more prose here",
      "tail prose here",
    }
    nx.await(nx.fs.write(file, table.concat(plain, "\n") .. "\n"))
    window.show({ file = file, name = "plain" })
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    t:wait_for(function()
      return next(marked_groups(buf)) and true
    end)

    -- Doc A's overlay goes in flight (row 3 is a `>lua` body holding `local x = 1`)…
    local pending = highlight.apply_tokens(buf, {
      plain[1],
      plain[2],
      plain[3],
      "local x = 1",
      plain[5],
    }, { { lang = "lua", first = 3, last = 3 } })
    -- …and doc B repaints the same buffer before it settles.
    highlight.apply(buf, plain, {})
    nx.await(pending)

    for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
      local g = mk[4] and mk[4].hl_group
      nx.test.expect(g and g:sub(1, 1) == "@").to_be_falsy()
    end
  end)

  nx.test.it("renders a CRLF help file (fences concealed, no stray carriage returns)", function(t)
    -- A doc/ checked out with CRLF endings must render exactly like an LF one: a
    -- trailing `\r` used to defeat the fence match (`>lua\r`), leaving the markers
    -- visible and a `\r` on every displayed line.
    local dir = nx.test.tempdir()
    local file = dir .. "/crlf.txt"
    nx.await(nx.fs.write(file, "*crlf*  A doc.\r\n\r\nUse it: >lua\r\n  local x = 1\r\n<done\r\n"))
    window.show({ file = file, name = "crlf" })
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    local lines = t:wait_for(function()
      local ls = nx.buf.lines(buf, 0, -1, false)
      return ls[1] == "*crlf*  A doc." and ls
    end)
    nx.test.expect(lines[3]).to_be("Use it:") -- `>lua` concealed, no `\r`
    nx.test.expect(lines[4]).to_be("local x = 1") -- dedented, no `\r`
    nx.test.expect(lines[5]).to_be("done") -- leading `<` concealed, no `\r`
  end)

  nx.test.it("marks only whitespace-delimited targets, not inline star pairs", function(t)
    -- The tag highlight has to agree with what the INDEX considers a tag; otherwise a
    -- markdown bold run or a backticked mention is painted as a clickable tag that
    -- `<C-]>` then can't resolve.
    local dir = nx.test.tempdir()
    local file = dir .. "/topic.txt"
    nx.await(nx.fs.write(
      file,
      table.concat({
        "*topic*  A topic.", -- row 0: a real target
        "", -- 1
        "A **bold** run and a `*quoted*` mention.", -- 2: neither is a target
        "", -- 3
        "A real *second-tag* sits here.", -- 4: a real target
      }, "\n")
    ))
    window.show({ file = file, name = "topic" })
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    local rows = t:wait_for(function()
      local found, any = {}, false
      for _, mk in ipairs(nx.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        if mk[4] and mk[4].hl_group == "nxHelpTag" then
          found[mk[2]] = true
          any = true
        end
      end
      return any and found
    end)
    nx.test.expect(rows[0]).to_be_truthy() -- *topic*
    nx.test.expect(rows[4]).to_be_truthy() -- *second-tag*
    nx.test.expect(rows[2]).to_be_falsy() -- **bold** / `*quoted*`
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
