<!-- DO NOT EDIT doc/nxvim-help.txt BY HAND. It is generated from this file by
panvimdoc — run `scripts/gen-vimdoc.sh` after editing. -->

Vim-style `:help` for nxvim — an optional first-party plugin built entirely on the native
`nx.*` plugin API ([ADR 0002](https://github.com/davidrios/nxvim)): no core changes and no
buffer-mutation hacks. Help renders in a read-only `nx.view` split, topics resolve through a
tag index merged across the runtimepath, and doc files are read with the promise `nx.fs` API.

It works out of the box. The plugin auto-registers `:help` when it loads (`plugin/nxvim-help.lua`
calls `setup()`), so once it is installed `:help {topic}` resolves against every installed
plugin's docs — this plugin's own included. Because nxvim-help is optional, a plugin's `doc/`
is only viewable when the user has installed it; the docs ship harmlessly regardless.

<!-- Passed through to the vimdoc verbatim so `:help nxvim-help` lands on this page
     (panvimdoc derives per-section tags but no bare project tag). -->
```vimdoc
                                              *nxvim-help* *nxvim-help-intro*
```

# Commands

```
:help {topic}     Open help for {topic} in a read-only split.
:help             With no topic, open the fuzzy topic picker.
:h {topic}        `:h` is the vim abbreviation of `:help`.
:NxHelptags [dir] (Re)generate a vim-style `doc/tags` file — see Registering help.
```

An unknown topic is a loud, vim-style `E149` (`Sorry, no help for "{topic}"`) — never a silent
no-op.

# Usage

Inside a help window:

```
CTRL-]  /  <CR>   Follow the tag under the cursor (pushes the tag stack).
CTRL-T            Jump back along the tag stack.
q                 Close the help window.
```

Both `CTRL-]` and `<CR>` follow, matching vim. The tag stack lets you drill through `|links|`
and return the way you came.

# The picker

Bare `:help` opens a fuzzy-finder over every known topic (`nx.picker`) with a live preview — the
target doc scrolled to the topic's tag. Each row shows the tag and, in an aligned second column,
the help file it lives in. Type to filter, `CTRL-N` / `CTRL-P` to move, `<CR>` to open, `<Esc>`
to cancel.

# Registering help

There is no registration API. Any plugin that ships a `doc/` directory is discovered
automatically — exactly like dropping `doc/` into a neovim plugin. `:Plugins` already puts every
installed plugin on the runtimepath (via `nx._add_rtp`), so `nx.runtime_file` finds every `doc/`.

A `tags` file is optional. If a `doc/` has one it is used (fast, and readable by vim);
otherwise nxvim-help derives the `*targets*` straight from `doc/*.txt`, so help works with zero
setup. A `tags` file is one line per `*target*`:

```
my-topic	my-plugin.txt	/*my-topic*
```

i.e. `tag<Tab>file<Tab>address`, with `file` relative to its `doc/` directory.

`:NxHelptags [dir]` writes such a file from `doc/*.txt`. With no argument (or `ALL`) it
regenerates every `doc/` directory on the runtimepath; with a directory argument it does just
that one. It is named `:NxHelptags` because nxvim core owns `:helptags`. Because the index reads
`.txt` directly, this is for interop and startup speed, not correctness. Duplicate tags in a
directory are reported.

# Topic resolution

Lookup is exact-first, then the shortest prefix match: `:help nxvim-help-u` resolves to
`nxvim-help-usage`. An unmatched topic is a loud `E149`.

# Keyword lookup

`K` — help for the word under the cursor — is opt-in, so it leaves an LSP-hover `K` alone by
default. Enable it with `setup({ keywordprg = true })`. It uses `<cWORD>` (the whole non-blank
token, since help tags contain `.` and `-` that `<cword>` stops at) and trims surrounding
punctuation, so `(nx.view)` and `|tag|` both resolve. No word under the cursor is a loud no-op.

# Setup

`setup()` is optional — the plugin auto-registers its commands on load. Registration happens once;
a later `setup{...}` still applies its options.

```lua
require("nxvim-help").setup({
  -- Map `K` (normal mode) to help for the word under the cursor.
  -- Off by default so it doesn't clobber an LSP-hover `K`.
  keywordprg = true,
})
```

# Highlighting

The help buffer is syntax-highlighted with extmark groups linked to standard highlights: section
headings, `*targets*`, `|links|`, and inline code spans.

# Notes

nxvim-help is built on the native `nx.*` surfaces only — `nx.view` (the read-only split), `nx.fs`
(promise reads), `nx.picker` (the topic finder), and `nx.runtime_file` (runtimepath discovery). It
adds no core changes; it is a worked example of a substantial editor feature living entirely as an
`nx.*` plugin.
