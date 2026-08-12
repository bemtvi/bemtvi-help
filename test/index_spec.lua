-- The tag index: discovery/parse over a real (temp) filesystem, plus pure lookup.
-- Run with `bemtvi --test-plugin`.
--
-- build_from() awaits btv.fs, and an `it` body already runs inside an btv.async
-- coroutine, so we drive it directly. parse_into/lookup are pure and need no fs.

local index = require("bemtvi-help.index")
local fs = btv.fs

local function write(path, text)
  btv.await(fs.write(path, text))
end

-- A tags file body (real tabs) for a fake plugin whose doc/ lives at `dir`.
local function tags_body()
  return table.concat({
    "!_TAG_FILE_SORTED\t1\t", -- a ctags pragma line; must be skipped
    "alpha\talpha.txt\t/*alpha*",
    "alpha-sub\talpha.txt\t/*alpha-sub*",
    "beta\tbeta.txt\t/*beta*",
    "",
  }, "\n")
end

btv.test.describe("bemtvi-help.index", function()
  local DIR

  btv.test.before_each(function()
    DIR = btv.test.tempdir()
    write(DIR .. "/tags", tags_body())
  end)

  btv.test.it("parses a tags file, skipping pragmas, resolving paths against its dir", function()
    local idx = btv.await(index.build_from({ DIR .. "/tags" }))
    btv.test.expect(idx["alpha"].file).to_be(DIR .. "/alpha.txt")
    btv.test.expect(idx["beta"].file).to_be(DIR .. "/beta.txt")
    btv.test.expect(idx["alpha"].name).to_be("alpha")
    -- the !_TAG_ pragma is not a tag
    btv.test.expect(idx["!_TAG_FILE_SORTED"]).to_be_falsy()
  end)

  btv.test.it("merges multiple tags files; first on the path wins", function()
    local other = btv.test.tempdir()
    write(other .. "/tags", "alpha\tother.txt\t/*alpha*\ngamma\tgamma.txt\t/*gamma*\n")
    -- DIR first, so its alpha wins over `other`'s; gamma still merges in.
    local idx = btv.await(index.build_from({ DIR .. "/tags", other .. "/tags" }))
    btv.test.expect(idx["alpha"].file).to_be(DIR .. "/alpha.txt")
    btv.test.expect(idx["gamma"].file).to_be(other .. "/gamma.txt")
  end)

  btv.test.it("looks up an exact tag", function()
    local idx = btv.await(index.build_from({ DIR .. "/tags" }))
    btv.test.expect(index.lookup(idx, "beta").name).to_be("beta")
  end)

  btv.test.it("falls back to the shortest prefix match", function()
    local idx = btv.await(index.build_from({ DIR .. "/tags" }))
    -- "alph" matches both alpha and alpha-sub; the shorter tag wins.
    btv.test.expect(index.lookup(idx, "alph").name).to_be("alpha")
  end)

  btv.test.it("returns nil for an unknown topic", function()
    local idx = btv.await(index.build_from({ DIR .. "/tags" }))
    btv.test.expect(index.lookup(idx, "nope")).to_be_falsy()
  end)
end)
