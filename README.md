# bemtvi-help

Vim-style **`:help`** for [bemtvi](https://github.com/davidrios/bemtvi) — an optional
first-party plugin built entirely on the native `btv.*` plugin API (ADR 0002): no core
changes, no buffer-mutation hacks. Help lives in a read-only `btv.view` split, topics
resolve through a tag index merged across the runtimepath, and doc files are read with
the promise `btv.fs` API.

```
:help                  fuzzy-find a topic (the picker)
:help bemtvi-help       open help for a topic  (`:h` is the abbreviation)
<leader>fh             open the topic picker ("find help") — bare :help
CTRL-] / <CR>          (in help) follow the tag under the cursor
CTRL-T                 (in help) jump back along the tag stack
q                      (in the help window) close it
K                      help for the word under the cursor (opt-in)
```

It works out of the box: the plugin auto-registers `:help` on load, and any installed
plugin that ships a `doc/` directory is discovered automatically — exactly like dropping
`doc/` into a neovim plugin. A `tags` file is optional (targets are derived from
`doc/*.txt` when absent), and what counts as a target follows vim's own scanner — a
whitespace-delimited `*tag*`, never an inline mention or a star inside a `>` example — so
a doc that writes *about* help tags doesn't squat on generic topics.

The help buffer is highlighted with groups linked to standard highlights (headings,
targets, links, inline code), and vim's `>lua` … `<` code fences render as real code
blocks: markers concealed, body dedented to its own left edge, on a full-width background,
token-highlighted by the fence's language wherever a tree-sitter grammar is installed.

## Install

Declare it with the built-in `:Plugins` manager, then `:PluginSync`:

```lua
btv.plugins({ { "davidrios/bemtvi-help" } })

-- setup() is optional; pass keywordprg to map K to "help for the word under
-- the cursor" (off by default so it leaves an LSP-hover K alone):
require("bemtvi-help").setup({ keywordprg = true })
```

## Documentation

Full docs — commands, the topic picker, how plugins register help (and exactly what
counts as a tag), `:BtvHelptags`, topic resolution, `K`/`keywordprg`, `setup()`,
highlighting, and code blocks — live in the help file. The same source renders both on
GitHub and in the editor:

- In editor: `:help bemtvi-help`
- On GitHub: [doc/bemtvi-help.md](./doc/bemtvi-help.md) (the help source)

## Development

Pure-Lua [`btv.test`](https://github.com/davidrios/bemtvi) specs drive a real editor over a
temp filesystem — target extraction, tag parsing/merge/lookup, helptags generation, the
tags-optional scan, real runtimepath discovery, fence rendering, buffer highlighting, the
picker source, the tag stack, `setup()` option handling, and opening a topic at its
anchor:

```sh
bemtvi --test-plugin .
```

Try the runnable demo (config isolated from your real one):

```sh
BEMTVI_CONFIG=examples cargo run -p bemtvi -- README.md
# then :help bemtvi-help
```

The vimdoc `doc/bemtvi-help.txt` is **generated** from `doc/bemtvi-help.md` via
[panvimdoc](https://github.com/kdheepak/panvimdoc): edit the `.md`, then run
`bash scripts/gen-vimdoc.sh` (needs `pandoc` + `git`). Never edit the `.txt` by hand.
