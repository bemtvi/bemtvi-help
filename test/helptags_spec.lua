-- Tag generation and the tags-optional scan path, over a real (temp) filesystem.
-- Run with `bemtvi --test-plugin`.

local helptags = require("bemtvi-help.helptags")
local index = require("bemtvi-help.index")
local fs = btv.fs

local function write(path, text)
  btv.await(fs.write(path, text))
end

local function read(path)
  return btv.await(fs.read_text(path))
end

btv.test.describe("bemtvi-help.helptags", function()
  btv.test.it("extracts *targets*, ignoring bullets, spaced stars and prose", function()
    local text = table.concat({
      "*intro* *intro-sub*",
      "a bullet * here and 5 * 3 is not a tag",
      "see *foo.bar* for *baz*",
      " vim:tw=78:ft=help:",
    }, "\n")
    local tags = helptags.targets(text)
    btv.test.expect(table.concat(tags, ",")).to_be("intro,intro-sub,foo.bar,baz")
  end)

  btv.test.it("requires a target to be whitespace-delimited, like vim", function()
    -- vim's helptags accepts `*tag*` only when the opening `*` sits at column 1 or
    -- after a space/tab AND the closing `*` is followed by whitespace or end-of-line
    -- (src/nvim/help.c, helptags_one). Without those two rules every inline mention —
    -- markdown bold, a backticked `*targets*`, a C pointer deref — became a tag, and
    -- this plugin's OWN doc ended up shadowing generic topics like `target` and `tag`.
    local text = table.concat({
      "*good* opens the line",
      "a **bold** run is not a tag",
      "a backticked `*targets*` is not a tag",
      "neither is a*b*c mid-token",
      "but *trailing* ", -- followed by a space: still a tag
      "*a|b* has a bar in it",
      "** is empty",
      "ends the file with *last*",
    }, "\n")
    btv.test.expect(table.concat(helptags.targets(text), ",")).to_be("good,trailing,last")
  end)

  btv.test.it("skips targets inside a `>` code example, like vim", function()
    -- vim's scanner suspends tag collection inside an example: a line ending in
    -- `>`/`>lang` opens one, and any line starting in column 1 ends it. A `*ptr*` in
    -- sample code is code, not a tag.
    local text = table.concat({
      "*real-tag*  a topic",
      "",
      "An example: >c",
      "  int *ptr* = 0;",
      "  *also-code*",
      "<*glued* is NOT a tag: the `<` is not whitespace before the star",
      "",
      "Another: >",
      "  *still-code*",
      "< *after-close* ends the block, and IS a tag",
      "",
      "Unclosed: >",
      "  *also-still-code*",
      "*column-one* ends the block and is a tag",
    }, "\n")
    btv.test
      .expect(table.concat(helptags.targets(text), ","))
      .to_be("real-tag,after-close,column-one")
  end)

  btv.test.it("writes a sorted, tab-separated tags file from doc/*.txt", function()
    local dir = btv.test.tempdir()
    write(dir .. "/a.txt", "*zeta*\n*alpha*\n")
    write(dir .. "/b.txt", "*mid*\n")
    local res = btv.await(helptags.generate(dir))
    btv.test.expect(res.count).to_be(3)
    btv.test.expect(res.files).to_be(2)
    -- sorted by tag; format is tag<TAB>file<TAB>/*tag*
    btv.test
      .expect(read(dir .. "/tags"))
      .to_be("alpha\ta.txt\t/*alpha*\nmid\tb.txt\t/*mid*\nzeta\ta.txt\t/*zeta*\n")
  end)

  btv.test.it("reports duplicate tags and keeps the first", function()
    local dir = btv.test.tempdir()
    write(dir .. "/a.txt", "*dup*\n")
    write(dir .. "/b.txt", "*dup*\n")
    local res = btv.await(helptags.generate(dir))
    btv.test.expect(res.count).to_be(1)
    btv.test.expect(res.dupes[1]).to_be("dup")
    -- a.txt sorts before b.txt, so the first (a.txt) wins
    btv.test.expect(read(dir .. "/tags")).to_be("dup\ta.txt\t/*dup*\n")
  end)

  btv.test.it("round-trips: a generated tags file parses back", function()
    local dir = btv.test.tempdir()
    write(dir .. "/x.txt", "*one*\n*two*\n")
    btv.await(helptags.generate(dir))
    local idx = btv.await(index.build_from({ dir .. "/tags" }))
    btv.test.expect(idx["one"].file).to_be(dir .. "/x.txt")
    btv.test.expect(idx["two"].name).to_be("two")
  end)

  btv.test.it("scan_dir derives an index from .txt with no tags file", function()
    local dir = btv.test.tempdir()
    write(dir .. "/only.txt", "*lonely*\n*also*\n")
    local idx = btv.await(index.scan_dir(dir))
    btv.test.expect(idx["lonely"].file).to_be(dir .. "/only.txt")
    btv.test.expect(idx["also"].name).to_be("also")
  end)
end)
