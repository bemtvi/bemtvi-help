-- nxvim-help — vim-style `:help` for nxvim, built entirely on the native `nx.*`
-- plugin API (ADR 0002). It is an *optional* first-party plugin: install it and
-- `:help {topic}` works against every installed plugin's docs.
--
-- How help "registration" works (phase 1): there is no registration API. Any plugin
-- that ships a `doc/` directory with a `tags` file is already on the runtimepath
-- (`:Plugins` calls `nx._add_rtp`), so `nx.runtime_file("doc/tags", true)` discovers
-- all of them — exactly like dropping `doc/` into a neovim plugin. This plugin's own
-- docs are found the same way.
--
-- Module map:
--   index.lua     runtimepath tags scan + parse + merge + topic lookup
--   helptags.lua  `*target*` extraction and `doc/tags` generation (:NxHelptags)
--   window.lua    show a resolved entry in the read-only help split (an nx.view)
--   render.lua    conceal vim's `>lua` … `<` code fences before display
--   highlight.lua the help buffer's extmark highlighting, incl. code-block tokens
--   picker.lua    the nx.picker source behind a bare `:help`
--   tagstack.lua  <C-]> / <CR> follow and <C-t> back
--   util.lua      the small glue the modules share (async runner, line splitting)
--
-- Quick start (init.lua): require("nxvim-help").setup() — then `:help nxvim-help`.

local index = require("nxvim-help.index")
local window = require("nxvim-help.window")
local helptags = require("nxvim-help.helptags")
local picker = require("nxvim-help.picker")
local tagstack = require("nxvim-help.tagstack")
local util = require("nxvim-help.util")

local M = {}

local run, trim = util.run, util.trim

-- How many clashing tags `:NxHelptags` names before it switches to "(+N more)".
local DUPES_SHOWN = 10

-- Open the first of `candidates` that resolves against the tag index. More than one
-- candidate is how `K` offers a fallback (see help_cword); a failure names the FIRST
-- candidate, which is what the user actually pointed at.
local function open_first(candidates)
  run(function()
    local idx = nx.await(index.ensure())
    for _, topic in ipairs(candidates) do
      local entry = index.lookup(idx, topic)
      if entry then
        nx.await(window.show(entry))
        return
      end
    end
    nx.notify('E149: Sorry, no help for "' .. candidates[1] .. '"', 4)
  end)
end

-- :help [topic] — with a topic, resolve it against the merged runtimepath tag index
-- and open it in the help split; with no topic, open the fuzzy topic picker. An
-- unknown topic is a loud, vim-style E149 (a user error, surfaced — never silent).
function M.help(topic)
  topic = topic and trim(topic) or ""
  if topic == "" then
    picker.open()
    return
  end
  open_first({ topic })
end

-- :NxHelptags [dir] — write a vim-style doc/tags from doc/*.txt. No argument (or
-- "ALL") regenerates every doc/ dir on the runtimepath. Optional: the index already
-- reads .txt directly, so this is for interop/startup speed, not correctness. Named
-- :NxHelptags because nxvim core owns (a stub of) :helptags.
function M.helptags(dir)
  run(function()
    dir = dir and trim(dir) or ""
    local dirs
    if dir == "" or dir:upper() == "ALL" then
      dirs = helptags.doc_dirs()
    else
      dirs = { dir }
    end
    local total = 0
    for _, d in ipairs(dirs) do
      local res = nx.await(helptags.generate(d))
      total = total + res.count
      if #res.dupes > 0 then
        -- Name the first few and count the rest: a doc set with a systematic clash can
        -- report hundreds, and an unbounded list would bury the message it belongs to.
        local shown = { table.unpack(res.dupes, 1, math.min(#res.dupes, DUPES_SHOWN)) }
        local more = #res.dupes - #shown
        nx.notify(
          "nxvim-help: duplicate tags in "
            .. d
            .. ": "
            .. table.concat(shown, ", ")
            .. (more > 0 and (" (+" .. more .. " more)") or ""),
          3
        )
      end
    end
    index.invalidate() -- the next :help must see the new tags
    nx.notify("nxvim-help: wrote tags for " .. #dirs .. " dir(s), " .. total .. " tags")
  end)
end

-- The topics to try for `word`, in order: the token EXACTLY as it appears, then the
-- same token with surrounding punctuation trimmed. Verbatim comes first because help
-- tags carry punctuation of their own — an option is tagged `*'number'*` and a key
-- `*CTRL-]*` — so trimming unconditionally would look up `number` / `CTRL-` and land
-- somewhere else (or nowhere). The trimmed form then covers the ordinary case of a tag
-- caught in prose punctuation: `(nx.view)`, `|tag|`, a trailing full stop.
function M.cword_candidates(word)
  local out = {}
  local trimmed = word:gsub("^[^%w_]+", ""):gsub("[^%w_]+$", "")
  for _, w in ipairs({ word, trimmed }) do
    if w ~= "" and w ~= out[1] then
      out[#out + 1] = w
    end
  end
  return out
end

-- :help for the word under the cursor — the `K` / `keywordprg` action. Uses <cWORD>
-- (the whole non-blank token), since help tags contain '.'/'-' that <cword> stops at.
-- No word under the cursor is a loud no-op (not the bare-:help picker, which would
-- surprise on K).
function M.help_cword()
  local candidates = M.cword_candidates(nx.expand("<cWORD>") or "")
  if #candidates == 0 then
    nx.notify("nxvim-help: no word under the cursor", 3)
    return
  end
  open_first(candidates)
end

local registered = false

-- The lhs each setup-owned map currently occupies (nil when unbound), so a later
-- setup() can MOVE or WITHDRAW what an earlier one bound. This is what makes the
-- documented options honest: the auto-loader (plugin/nxvim-help.lua) already ran
-- setup() with the defaults by the time a user's own setup{...} is reached, so
-- `search_keymap = false` has to be able to undo a map, not merely decline to add one.
-- Only maps we bound ourselves are ever deleted.
local bound = { search = nil, keywordprg = nil }

local function rebind(slot, lhs, rhs, desc)
  -- Withdraw the previous binding first — even at the SAME lhs, since `nx.keymap.set`
  -- appends rather than replaces, so re-running setup() would otherwise stack a
  -- duplicate mapping on every call.
  if bound[slot] then
    nx.keymap.del("n", bound[slot])
    bound[slot] = nil
  end
  if lhs then
    nx.keymap.set("n", lhs, rhs, { desc = desc })
    bound[slot] = lhs
  end
end

-- setup([opts]) — register the commands (once) and apply the per-call options. The
-- auto-loader (plugin/nxvim-help.lua) calls setup() with no opts, and a user's later
-- setup{...} still takes effect: command registration is one-time, options are not —
-- each call re-applies the maps it owns, including removing one it previously bound.
--   opts.keywordprg = true  → map `K` (normal mode) to help for the word under the
--   cursor. Off by default so it doesn't clobber an LSP-hover `K`.
--   opts.search_keymap      → the normal-mode map that opens the help-topic picker
--   (the bare `:help` search). Defaults to `<leader>fh`; a string sets a different
--   lhs, `false` disables it.
function M.setup(opts)
  opts = opts or {}

  rebind("keywordprg", opts.keywordprg and "K" or nil, function()
    M.help_cword()
  end, "Help for the word under the cursor")

  -- <leader>fh opens the topic picker — "find help", the bare `:help` search. On by
  -- default (a leader map rarely collides); pass `search_keymap = false` to skip it,
  -- or a string to bind a different key.
  local search_lhs = opts.search_keymap
  if search_lhs == nil then
    search_lhs = "<leader>fh"
  end
  rebind("search", search_lhs or nil, function()
    M.help("")
  end, "Search help topics")

  if registered then
    return
  end
  registered = true

  -- nxvim core has no built-in :help, so this defines it; :h is the vim abbreviation.
  -- A core built-in (if one is ever added) takes precedence, so registering :h is safe.
  for _, name in ipairs({ "help", "h" }) do
    nx.user_command.create(name, function(a)
      M.help(a.args)
    end, { desc = "Open nxvim help for {topic}" })
  end

  -- :NxHelptags [dir|ALL] — (re)generate doc/tags. (:helptags is core-owned.)
  nx.user_command.create("NxHelptags", function(a)
    M.helptags(a.args)
  end, { desc = "Generate help tags from doc/*.txt ([dir] or ALL)" })

  -- Buffer-local maps for the help window, installed when a help buffer loads.
  nx.autocmd.create("FileType", {
    pattern = "help",
    callback = function()
      nx.keymap.set("n", "q", function()
        window.close()
      end, { buffer = 0, desc = "Close help" })
      -- Follow the tag under the cursor (vim binds both <C-]> and <CR> in help)…
      for _, lhs in ipairs({ "<C-]>", "<CR>" }) do
        nx.keymap.set("n", lhs, function()
          tagstack.follow()
        end, { buffer = 0, desc = "Follow help tag" })
      end
      -- …and pop back along the tag stack.
      nx.keymap.set("n", "<C-t>", function()
        tagstack.back()
      end, { buffer = 0, desc = "Back (help tag stack)" })
    end,
  })
end

return M
