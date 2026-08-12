-- Code-fence rendering: vim marks examples with `>` / `>lua` … `<` markers that
-- neovim conceals. render.prepare rewrites them out of the displayed text and flags
-- the example rows for the code highlight. Run with `bemtvi --test-plugin`.

local render = require("bemtvi-help.render")

-- Split a `\n`-joined string into lines the way the window does.
local function split(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

btv.test.describe("bemtvi-help.render", function()
  btv.test.it("strips a trailing `>` / `>lang` fence marker from the opening line", function()
    btv.test.expect(render.strip_start("A {spec} is: >")).to_be("A {spec} is:")
    btv.test.expect(render.strip_start("run this: >lua")).to_be("run this:")
    btv.test.expect(render.strip_start(">")).to_be("")
    btv.test.expect(render.strip_start(">vim")).to_be("")
  end)

  btv.test.it("leaves a bare `>` in prose alone (not a fence)", function()
    btv.test.expect(render.strip_start("use a => b here")).to_be_nil()
    btv.test.expect(render.strip_start("nothing to see")).to_be_nil()
  end)

  btv.test.it("conceals the fence and flags the example rows", function()
    local raw = split(table.concat({
      "Intro line.", -- row 0  prose
      "An example: >lua", -- row 1  opening fence  -> "An example:"
      "  local x = 1", -- row 2  code
      "  return x", -- row 3  code
      "<Back to prose.", -- row 4  closing fence   -> "Back to prose."
      "Trailing.", -- row 5  prose
    }, "\n"))
    local r = render.prepare(raw)

    -- markers concealed, line count preserved
    btv.test.expect(#r.lines).to_be(#raw)
    btv.test.expect(r.lines[2]).to_be("An example:")
    btv.test.expect(r.lines[5]).to_be("Back to prose.")

    -- only the two indented rows are code
    btv.test.expect(r.code[2]).to_be_truthy()
    btv.test.expect(r.code[3]).to_be_truthy()
    btv.test.expect(r.code[0]).to_be_nil()
    btv.test.expect(r.code[1]).to_be_nil() -- the opening line is prose
    btv.test.expect(r.code[4]).to_be_nil() -- the closing line is prose
    btv.test.expect(r.code[5]).to_be_nil()
  end)

  btv.test.it("strips a block's common indentation, keeping relative indent", function()
    -- panvimdoc indents every `>` body line by 4 spaces; we dedent by the block's
    -- own minimum so the code sits flush against the block's left edge while its
    -- internal (relative) indentation survives. Blank body rows stay blank.
    local raw = split(table.concat({
      "Example: >lua", -- row 0  opening fence -> "Example:"
      "    require('x').setup({", -- row 1  common 4-space indent
      "      opt = true,", -- row 2  6 spaces (2 nested)
      "", -- row 3  blank inside the block
      "    })", -- row 4  4 spaces
      "<done", -- row 5  closing fence -> "done"
    }, "\n"))
    local r = render.prepare(raw)
    btv.test.expect(r.lines[1]).to_be("Example:") -- opening prose
    btv.test.expect(r.lines[2]).to_be("require('x').setup({") -- common 4 stripped
    btv.test.expect(r.lines[3]).to_be("  opt = true,") -- relative 2 kept
    btv.test.expect(r.lines[4]).to_be("") -- blank stays blank
    btv.test.expect(r.lines[5]).to_be("})") -- common 4 stripped
    btv.test.expect(r.lines[6]).to_be("done") -- closing prose
    -- still flagged as code rows
    btv.test.expect(r.code[1]).to_be_truthy()
    btv.test.expect(r.code[4]).to_be_truthy()
  end)

  btv.test.it("reopens a fence on the prose that follows a `<` closing marker", function()
    -- `<Then try: >lua` closes one example and opens the next on the same line — the
    -- closing branch used to emit the remainder as plain prose, so the second block's
    -- body was never flagged as code and its `>lua` marker stayed visible.
    local raw = split(table.concat({
      "First: >", -- row 0  opening fence
      "  one", -- row 1  code
      "<Then try: >lua", -- row 2  close + reopen -> "Then try:"
      "  two", -- row 3  code (second block)
      "Prose.", -- row 4  column-1 line ends it
    }, "\n"))
    local r = render.prepare(raw)
    btv.test.expect(r.lines[3]).to_be("Then try:")
    btv.test.expect(r.code[1]).to_be_truthy() -- first block body
    btv.test.expect(r.code[3]).to_be_truthy() -- second block body
    btv.test.expect(r.code[2]).to_be_nil() -- the fence line itself is prose
    btv.test.expect(r.lines[4]).to_be("two") -- dedented as a code body
    btv.test.expect(#r.blocks).to_be(2)
    btv.test.expect(r.blocks[2].lang).to_be("lua")
  end)

  btv.test.it("leaves a mixed tab/space block undedented rather than mis-shifting it", function()
    -- Dedent strips the block's longest COMMON leading-whitespace prefix. With one row
    -- indented by a tab and another by spaces there is no common prefix, so nothing is
    -- stripped — the old character-count minimum would have eaten one tab's worth of a
    -- space-indented row (and vice versa), skewing the code.
    local raw = split(table.concat({
      "Mixed: >", -- row 0
      "\ttabbed", -- row 1  tab indent
      "    spaced", -- row 2  space indent
      "Prose.", -- row 3
    }, "\n"))
    local r = render.prepare(raw)
    btv.test.expect(r.lines[2]).to_be("\ttabbed")
    btv.test.expect(r.lines[3]).to_be("    spaced")
  end)

  btv.test.it("ends an unclosed block at the next column-1 line", function()
    local raw = split(table.concat({
      "Header: >", -- row 0  opening fence
      "    code line", -- row 1  code
      "", -- row 2  blank stays in the block
      "    more code", -- row 3  code
      "Next section", -- row 4  column-1 prose ends the block before it
    }, "\n"))
    local r = render.prepare(raw)
    btv.test.expect(r.lines[1]).to_be("Header:")
    btv.test.expect(r.code[1]).to_be_truthy()
    btv.test.expect(r.code[2]).to_be_truthy() -- blank line inside the block
    btv.test.expect(r.code[3]).to_be_truthy()
    btv.test.expect(r.code[4]).to_be_nil() -- "Next section" is prose
    btv.test.expect(r.lines[5]).to_be("Next section")
  end)
end)
