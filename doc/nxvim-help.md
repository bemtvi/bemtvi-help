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

`<leader>fh` ("find help") opens this same picker from normal mode — the keymap equivalent of a
bare `:help`. It is on by default; see Setup to rebind or disable it.

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
directory are reported (each clashing tag named once).

What counts as a target follows vim's own rule, which matters when your doc writes *about* help
tags rather than defining one:

- The opening star must sit at column 1 or right after a space or tab, and the closing star must
  be followed by whitespace or the end of the line. So a bold run, a backticked mention, or a C
  dereference (`int *p*`) is prose, not a tag.
- The text between the stars may not contain a space, a tab, or `|`.
- Stars inside a `>` code example are skipped entirely — sample code is code.

Without those rules a doc that merely *mentions* `*targets*` would claim the generic topic
`targets` for the whole runtimepath.

# Topic resolution

Lookup is exact-first, then the shortest prefix match: `:help nxvim-help-u` resolves to
`nxvim-help-usage`. An unmatched topic is a loud `E149`.

# Keyword lookup

`K` — help for the word under the cursor — is opt-in, so it leaves an LSP-hover `K` alone by
default. Enable it with `setup({ keywordprg = true })`. It reads `<cWORD>` (the whole non-blank
token, since help tags contain `.` and `-` that `<cword>` stops at) and tries two topics in
order:

1. The token exactly as written. Help tags carry punctuation of their own — an option is
   tagged `*'number'*`, a key `*CTRL-]*` — so the verbatim form has to win.
2. The token with surrounding punctuation trimmed, which catches a tag caught in prose
   punctuation: `(nx.view)`, `|tag|`, a trailing full stop.

No word under the cursor is a loud no-op.

# Setup

`setup()` is optional — the plugin auto-registers its commands on load. Command registration
happens once, but the options are re-applied on every call, so a later `setup{...}` in your
config can move or withdraw a keymap an earlier call bound (the auto-loader has already run
`setup()` with the defaults by the time your config is reached — without this, `search_keymap =
false` could never take effect). Only maps nxvim-help itself bound are ever removed.

```lua
require("nxvim-help").setup({
  -- Map `K` (normal mode) to help for the word under the cursor.
  -- Off by default so it doesn't clobber an LSP-hover `K`.
  keywordprg = true,

  -- The normal-mode map that opens the help-topic picker (the bare `:help`
  -- search). Defaults to "<leader>fh"; a string rebinds it, `false` disables it.
  search_keymap = "<leader>fh",
})
```

# Highlighting

The help buffer is syntax-highlighted with extmark groups linked to standard highlights, so a
colorscheme styles it for free:

```
nxHelpHeadline   Title              a section heading
nxHelpDelim      Comment            the ==== / ---- rules
nxHelpTag        Label              a *target*
nxHelpLink       Identifier         a |hot-link|
nxHelpCode       String             an inline `code` span, and code-block text
nxHelpCodeBlock  @markup.raw.block  a code block's full-width background
```

A heading is recognized by vimdoc structure — text at column 1 followed by a right-aligned
`*tag*`, or an H3-style `TITLE ~` — not by an ALL-CAPS run, so a numbered or mixed-case
panvimdoc title is highlighted and a sentence that merely opens with capitals is not.

# Code blocks

Vim marks an example with a fence: a line ending in `>` (optionally with a language, `>lua` /
`>vim`) opens it, and a line starting with `<` — or any line that starts in column 1 — closes
it. nxvim has no `'conceal'`, so nxvim-help rewrites those markers out of the displayed text
instead, exactly one output line per input line so tag anchors and the tag stack stay aligned.

Each block is then dedented to its own left edge (panvimdoc indents every body line by four
spaces) with relative indentation preserved, painted on a full-width background, and — when the
fence names a language whose tree-sitter grammar is installed — token-highlighted the way an
injected code block is anywhere else in nxvim. A language with no grammar simply keeps the flat
code colour.

# Notes

nxvim-help is built on the native `nx.*` surfaces only — `nx.view` (the read-only split), `nx.fs`
(promise reads), `nx.picker` (the topic finder), `nx.runtime_file` (runtimepath discovery),
`nx.buf.set_extmark` (the highlighting), `nx.treesitter.highlight` (code-block tokens), and
`nx.keymap` / `nx.user_command` / `nx.autocmd` (the bindings). It adds no core changes; it is a
worked example of a substantial editor feature living entirely as an `nx.*` plugin.

Every disk read goes through the promise filesystem, never a blocking call, and the tag index is
built once and shared: callers that race for it (a `:help` and the picker opening together) join
the same scan rather than each walking the runtimepath. `:NxHelptags` invalidates it.
