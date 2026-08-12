-- Help-buffer highlighting: opening a topic places extmarks for tags, links,
-- headings and delimiters. Run with `bemtvi --test-plugin`.

local help = require("bemtvi-help")
local window = require("bemtvi-help.window")
local highlight = require("bemtvi-help.highlight")
local index = require("bemtvi-help.index")

-- The set of hl_groups currently marked on `buf` under our namespace.
local function marked_groups(buf)
  local groups = {}
  for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
    local d = mk[4]
    if d and d.hl_group then
      groups[d.hl_group] = true
    end
  end
  return groups
end

btv.test.describe("bemtvi-help highlight", function()
  btv.test.before_each(function()
    window._reset()
    index.invalidate()
    help.setup()
  end)

  btv.test.after_each(function()
    window._reset()
  end)

  btv.test.it("marks tags, links, headings and delimiters when a topic opens", function(t)
    help.help("bemtvi-help") -- the front page has all four
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    local groups = t:wait_for(function()
      local g = marked_groups(buf)
      -- wait until highlighting has been applied (it lands a tick after the buffer)
      return next(g) and g
    end)
    btv.test.expect(groups["btvHelpTag"]).to_be_truthy()
    btv.test.expect(groups["btvHelpLink"]).to_be_truthy()
    btv.test.expect(groups["btvHelpHeadline"]).to_be_truthy()
    btv.test.expect(groups["btvHelpDelim"]).to_be_truthy()
  end)

  btv.test.it("marks structural headings (tagged / ~) but not ALL-CAPS prose", function(t)
    -- panvimdoc headings are numbered / mixed-case with a right-aligned *tag*
    -- ("1. Commands  *topic-commands*", "Table of Contents  *topic-toc*"), or an
    -- H3-style "TITLE ~". A caps run in PROSE ("LSP-hover …") is NOT a heading —
    -- the old ALL-CAPS heuristic wrongly flagged it and missed the real headings.
    local dir = btv.test.tempdir()
    local file = dir .. "/topic.txt"
    btv.await(btv.fs.write(
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
      for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
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
    btv.test.expect(has(3, "btvHelpHeadline")).to_be(true) -- Table of Contents
    btv.test.expect(has(5, "btvHelpHeadline")).to_be(true) -- 1. Commands
    btv.test.expect(has(7, "btvHelpHeadline")).to_be(true) -- SUBSECTION ~
    -- …the delimiter is marked…
    btv.test.expect(has(2, "btvHelpDelim")).to_be(true)
    -- …and the ALL-CAPS-prefixed PROSE line is NOT a headline.
    btv.test.expect(has(9, "btvHelpHeadline")).to_be(false)
  end)

  btv.test.it("renders a >lua … < code block: conceals markers, marks the code", function(t)
    -- A fixture doc with a fenced example; drive window.show directly against it.
    local dir = btv.test.tempdir()
    local file = dir .. "/topic.txt"
    btv.await(btv.fs.write(
      file,
      table.concat({
        "*topic*  A topic.",
        "",
        "Use it like this: >lua",
        "  local x = btv.foo()",
        "<Back to prose.",
      }, "\n")
    ))
    window.show({ file = file, name = "topic" })

    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    -- markers are gone from the displayed text
    local lines = t:wait_for(function()
      local ls = btv.buf.lines(buf, 0, -1, false)
      return ls[3] == "Use it like this:" and ls
    end)
    btv.test.expect(lines[3]).to_be("Use it like this:") -- `>lua` concealed
    btv.test.expect(lines[5]).to_be("Back to prose.") -- leading `<` concealed

    -- the code line carries the code-block highlight
    local groups = t:wait_for(function()
      local g = {}
      for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
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
    btv.test.expect(groups["btvHelpCode"]).to_be_truthy()
    btv.test.expect(groups["btvHelpCodeBlock"]).to_be_truthy()
  end)

  btv.test.it("token-highlights a >lua block body by its fence language", function(t)
    -- Needs the `lua` tree-sitter grammar installed; the off-buffer highlighter
    -- returns nothing without it, so skip rather than fail (the external-dependency
    -- convention). The probe doubles as proof the API is wired.
    local probe = btv.await(btv.treesitter.highlight("lua", "local x = 1\n"))
    if #probe == 0 then
      return
    end
    local dir = btv.test.tempdir()
    local file = dir .. "/topic.txt"
    btv.await(btv.fs.write(
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
    -- flat `btvHelpCode`. Async (the overlay awaits the highlight promise), so poll.
    local kw = t:wait_for(function()
      for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        if mk[2] == 3 and mk[4] and mk[4].hl_group == "@keyword" then
          -- `local` starts at byte column 0: render.prepare dedents the block's
          -- common (two-space) indent, so the code sits flush at the left.
          return mk[3] == 0 and mk
        end
      end
      return nil
    end)
    btv.test.expect(kw).to_be_truthy()

    -- The flat code base and block background survive under the tokens (the code row
    -- keeps `btvHelpCode` / `btvHelpCodeBlock` — the token overlay only adds marks).
    local groups = {}
    for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
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
    btv.test.expect(groups["btvHelpCode"]).to_be_truthy()
    btv.test.expect(groups["btvHelpCodeBlock"]).to_be_truthy()
  end)

  btv.test.it("drops a superseded token overlay instead of painting it on the new doc", function(t)
    -- Regression: `apply_tokens` awaits the (async) tree-sitter highlight per block.
    -- If a second `:help` repaints the buffer while that await is in flight, the
    -- resolved spans used to land on the NEW document — stale `@`-group marks at rows
    -- and columns belonging to the previous one. A generation guard must drop them.
    local probe = btv.await(btv.treesitter.highlight("lua", "local x = 1\n"))
    if #probe == 0 then
      return -- no lua grammar installed; nothing to overlay (external-dep convention)
    end
    -- A fence-free doc, just to obtain a live help buffer with enough rows/columns.
    local dir = btv.test.tempdir()
    local file = dir .. "/plain.txt"
    local plain = {
      "*plain*  A doc.",
      "",
      "just prose here",
      "more prose here",
      "tail prose here",
    }
    btv.await(btv.fs.write(file, table.concat(plain, "\n") .. "\n"))
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
    btv.await(pending)

    for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
      local g = mk[4] and mk[4].hl_group
      btv.test.expect(g and g:sub(1, 1) == "@").to_be_falsy()
    end
  end)

  btv.test.it("renders a CRLF help file (fences concealed, no stray carriage returns)", function(t)
    -- A doc/ checked out with CRLF endings must render exactly like an LF one: a
    -- trailing `\r` used to defeat the fence match (`>lua\r`), leaving the markers
    -- visible and a `\r` on every displayed line.
    local dir = btv.test.tempdir()
    local file = dir .. "/crlf.txt"
    btv.await(btv.fs.write(file, "*crlf*  A doc.\r\n\r\nUse it: >lua\r\n  local x = 1\r\n<done\r\n"))
    window.show({ file = file, name = "crlf" })
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    local lines = t:wait_for(function()
      local ls = btv.buf.lines(buf, 0, -1, false)
      return ls[1] == "*crlf*  A doc." and ls
    end)
    btv.test.expect(lines[3]).to_be("Use it:") -- `>lua` concealed, no `\r`
    btv.test.expect(lines[4]).to_be("local x = 1") -- dedented, no `\r`
    btv.test.expect(lines[5]).to_be("done") -- leading `<` concealed, no `\r`
  end)

  btv.test.it("marks only whitespace-delimited targets, not inline star pairs", function(t)
    -- The tag highlight has to agree with what the INDEX considers a tag; otherwise a
    -- markdown bold run or a backticked mention is painted as a clickable tag that
    -- `<C-]>` then can't resolve.
    local dir = btv.test.tempdir()
    local file = dir .. "/topic.txt"
    btv.await(btv.fs.write(
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
      for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        if mk[4] and mk[4].hl_group == "btvHelpTag" then
          found[mk[2]] = true
          any = true
        end
      end
      return any and found
    end)
    btv.test.expect(rows[0]).to_be_truthy() -- *topic*
    btv.test.expect(rows[4]).to_be_truthy() -- *second-tag*
    btv.test.expect(rows[2]).to_be_falsy() -- **bold** / `*quoted*`
  end)

  btv.test.it("marks a *target* span at its exact byte columns", function(t)
    help.help("bemtvi-help")
    local buf = t:wait_for(function()
      return window.bufnr()
    end)
    -- wait for marks, then slice each btvHelpTag span out of its line and confirm it
    -- is exactly a *…* run (columns line up).
    local sliced = t:wait_for(function()
      local found = {}
      for _, mk in ipairs(btv.buf.extmarks(buf, highlight.ns, 0, -1, { details = true })) do
        local row, col, d = mk[2], mk[3], mk[4]
        if d and d.hl_group == "btvHelpTag" then
          local line = btv.buf.lines(buf, row, row + 1, false)[1] or ""
          found[#found + 1] = line:sub(col + 1, d.end_col)
        end
      end
      return #found > 0 and found
    end)
    for _, s in ipairs(sliced) do
      btv.test.expect(s:sub(1, 1)).to_be("*")
      btv.test.expect(s:sub(-1)).to_be("*")
    end
  end)
end)
