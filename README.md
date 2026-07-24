# nxvim-help

Vim-style **`:help`** for [nxvim](https://github.com/davidrios/nxvim) — an optional
first-party plugin built entirely on the native `nx.*` plugin API (ADR 0002): no core
changes, no buffer-mutation hacks. Help lives in a read-only `nx.view` split, topics
resolve through a tag index merged across the runtimepath, and doc files are read with
the promise `nx.fs` API.

```
:help                  fuzzy-find a topic (the picker)
:help nxvim-help       open help for a topic  (`:h` is the abbreviation)
<leader>fh             open the topic picker ("find help") — bare :help
CTRL-] / <CR>          (in help) follow the tag under the cursor
CTRL-T                 (in help) jump back along the tag stack
q                      (in the help window) close it
K                      help for the word under the cursor (opt-in)
```

It works out of the box: the plugin auto-registers `:help` on load, and any installed
plugin that ships a `doc/` directory is discovered automatically — exactly like dropping
`doc/` into a neovim plugin. A `tags` file is optional (targets are derived from
`doc/*.txt` when absent).

## Install

Declare it with the built-in `:Plugins` manager, then `:PluginSync`:

```lua
nx.plugins({ { "davidrios/nxvim-help" } })

-- setup() is optional; pass keywordprg to map K to "help for the word under
-- the cursor" (off by default so it leaves an LSP-hover K alone):
require("nxvim-help").setup({ keywordprg = true })
```

## Documentation

Full docs — commands, the topic picker, how plugins register help, `:NxHelptags`,
topic resolution, `K`/`keywordprg`, and `setup()` — live in the help file. The same
source renders both on GitHub and in the editor:

- In editor: `:help nxvim-help`
- On GitHub: [doc/nxvim-help.md](./doc/nxvim-help.md) (the help source)

## Development

Pure-Lua [`nx.test`](https://github.com/davidrios/nxvim) specs drive a real editor over a
temp filesystem — tag parsing/merge/lookup, helptags generation, the tags-optional scan,
real runtimepath discovery, and opening a topic at its anchor:

```sh
nxvim --test-plugin .
```

Try the runnable demo (config isolated from your real one):

```sh
NXVIM_CONFIG=examples cargo run -p nxvim -- README.md
# then :help nxvim-help
```

The vimdoc `doc/nxvim-help.txt` is **generated** from `doc/nxvim-help.md` via
[panvimdoc](https://github.com/kdheepak/panvimdoc): edit the `.md`, then run
`bash scripts/gen-vimdoc.sh` (needs `pandoc` + `git`). Never edit the `.txt` by hand.
