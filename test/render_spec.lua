-- Code-fence rendering: vim marks examples with `>` / `>lua` … `<` markers that
-- neovim conceals. render.prepare rewrites them out of the displayed text and flags
-- the example rows for the code highlight. Run with `nxvim --test-plugin`.

local render = require("nxvim-help.render")

-- Split a `\n`-joined string into lines the way the window does.
local function split(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

nx.test.describe("nxvim-help.render", function()
  nx.test.it("strips a trailing `>` / `>lang` fence marker from the opening line", function()
    nx.test.expect(render.strip_start("A {spec} is: >")).to_be("A {spec} is:")
    nx.test.expect(render.strip_start("run this: >lua")).to_be("run this:")
    nx.test.expect(render.strip_start(">")).to_be("")
    nx.test.expect(render.strip_start(">vim")).to_be("")
  end)

  nx.test.it("leaves a bare `>` in prose alone (not a fence)", function()
    nx.test.expect(render.strip_start("use a => b here")).to_be_nil()
    nx.test.expect(render.strip_start("nothing to see")).to_be_nil()
  end)

  nx.test.it("conceals the fence and flags the example rows", function()
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
    nx.test.expect(#r.lines).to_be(#raw)
    nx.test.expect(r.lines[2]).to_be("An example:")
    nx.test.expect(r.lines[5]).to_be("Back to prose.")

    -- only the two indented rows are code
    nx.test.expect(r.code[2]).to_be_truthy()
    nx.test.expect(r.code[3]).to_be_truthy()
    nx.test.expect(r.code[0]).to_be_nil()
    nx.test.expect(r.code[1]).to_be_nil() -- the opening line is prose
    nx.test.expect(r.code[4]).to_be_nil() -- the closing line is prose
    nx.test.expect(r.code[5]).to_be_nil()
  end)

  nx.test.it("strips a block's common indentation, keeping relative indent", function()
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
    nx.test.expect(r.lines[1]).to_be("Example:") -- opening prose
    nx.test.expect(r.lines[2]).to_be("require('x').setup({") -- common 4 stripped
    nx.test.expect(r.lines[3]).to_be("  opt = true,") -- relative 2 kept
    nx.test.expect(r.lines[4]).to_be("") -- blank stays blank
    nx.test.expect(r.lines[5]).to_be("})") -- common 4 stripped
    nx.test.expect(r.lines[6]).to_be("done") -- closing prose
    -- still flagged as code rows
    nx.test.expect(r.code[1]).to_be_truthy()
    nx.test.expect(r.code[4]).to_be_truthy()
  end)

  nx.test.it("ends an unclosed block at the next column-1 line", function()
    local raw = split(table.concat({
      "Header: >", -- row 0  opening fence
      "    code line", -- row 1  code
      "", -- row 2  blank stays in the block
      "    more code", -- row 3  code
      "Next section", -- row 4  column-1 prose ends the block before it
    }, "\n"))
    local r = render.prepare(raw)
    nx.test.expect(r.lines[1]).to_be("Header:")
    nx.test.expect(r.code[1]).to_be_truthy()
    nx.test.expect(r.code[2]).to_be_truthy() -- blank line inside the block
    nx.test.expect(r.code[3]).to_be_truthy()
    nx.test.expect(r.code[4]).to_be_nil() -- "Next section" is prose
    nx.test.expect(r.lines[5]).to_be("Next section")
  end)
end)
