# Neovim Config

A personal, batteries-included Neovim setup in pure Lua. Built around two
daily drivers — **Java / Spring Boot** and the web stack (**TypeScript,
Angular, HTML/CSS**) — plus an **Obsidian-style Markdown** workflow.

Managed by [lazy.nvim](https://github.com/folke/lazy.nvim), themed with
**Catppuccin Mocha**, tested with headless specs.

---

## Table of Contents

- [Highlights](#highlights)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Architecture](#architecture)
- [Testing](#testing)
- [Customization](#customization)
- [Notes & Caveats](#notes--caveats)

---

## Highlights

- **Java (Spring Boot)** — `nvim-jdtls` with Lombok agent, `java-debug-adapter`
  and `java-test` bundles wired straight into jdtls, JUnit run/test keymaps.
- **New-file templates** — `BufNewFile` skeletons for Java (`package` from
  `src/main|test/java` + `public class <Name>`, plus `main` for standalone
  files), C, C++, headers, C#, Go, Kotlin, Rust and PHP; existing files are
  never touched.
- **Markdown / Obsidian** — a hand-written editing core: emphasis toggles,
  links, wikilinks, headings, checkboxes, quotes, and list continuation with
  automatic ordered-list renumbering. Rendered in-buffer by `render-markdown.nvim`.
- **Web frontend indentation** — a custom `indentexpr` (VSCode `onEnterRules`
  logic) replaces Treesitter indent for HTML/Angular/JS/TS/JSX so `<div>`,
  `{`, `(` and `[` break exactly the way you expect.
- **LSP everywhere** — installs and configures 20+ servers via Mason:
  jdtls, vtsls, pyright, gopls, rust-analyzer, clangd, angular, kotlin,
  html/css/json/eslint/tailwind/yaml/bash/dockerfile, marksman and more.
- **Inline AI** — `opencode.nvim` in a right-side pane, context-aware
  (current file, selection, diagnostics).
- **UI polish** — Catppuccin Mocha, Lualine, Bufferline (pinned buffers),
  Neo-tree, Telescope, Noice, indent-blankline.
- **Headless test suite** — plain `nvim --headless` specs, no framework needed.

---

## Requirements

| Requirement | Notes |
| :-- | :-- |
| **Neovim ≥ 0.11** | Uses `vim.lsp.config`, `vim.treesitter.start`, and the `main` branch of nvim-treesitter. |
| **git**, **ripgrep** | Plugin bootstrap and Telescope live-grep. |
| **JDK 17/21** | jdtls runtime is hardcoded to `/usr/lib/jvm/java-21-openjdk` (see [Notes](#notes--caveats)). |
| **Maven or Gradle** | For Java project roots (`pom.xml`, `mvnw`, `gradlew`, `.git`). |
| **Nerd Font** | `JetBrainsMono Nerd Font` is the GUI font. |
| **C compiler + `tree-sitter` CLI** | Building Treesitter parsers. |
| **Alacritty** *(optional)* | Used by the Neovide `<C-S-n>` keymap. |
| **`latex2text`** *(optional)* | LaTeX conversion in `render-markdown.nvim`. |

---

## Installation

> Back up anything already in `~/.config/nvim` first.

```bash
git clone git@github.com:AliFuatAkyemis/Neovim-Config.git ~/.config/nvim
nvim
```

On first launch `lazy.nvim` bootstraps itself, then installs every plugin:

1. Wait for Lazy to finish — `:Lazy` to inspect.
2. `:Mason` — verify `jdtls`, `java-debug-adapter`, `java-test` and the other
   servers are installed.
3. `:TSUpdate` — builds the Treesitter parsers listed in
   `lua/plugins/treesitter.lua`.

`lazy-lock.json` is **gitignored** on purpose, so plugins track their latest
compatible revisions after a fresh clone.

---

## Usage

Leader is <kbd>Space</kbd>; local leader is <kbd>\\</kbd>.

### Global

| Key | Action |
| :-- | :-- |
| `<C-p>` | Find files (Telescope) |
| `<leader>fg` | Live grep |
| `<C-n>` | Toggle Neo-tree |
| `<leader>w` | Save file |
| `<leader>f` | Format buffer (conform) |
| `<leader>?` | Buffer-local keymaps (which-key) |
| `<C-k>` | Floating diagnostic |
| `<leader>r` | Clear search highlight + redraw |
| `<leader>up` | Toggle LSP progress |

### Buffers & Windows

| Key | Action |
| :-- | :-- |
| `L` / `H` | Next / previous buffer |
| `<leader>x` | Close buffer, keep the split layout |
| `<leader>bp` | Pin / unpin buffer (Bufferline) |

### Motion & Editing

| Key | Action |
| :-- | :-- |
| `<C-l>`, `<C-Right>` | Next word — normal/insert stop at the word end before wrapping; visual uses native `<C-Right>` |
| `<C-h>`, `<C-Left>` | Previous word — normal, insert and all visual modes (visual, visual-line, visual-block) |
| `<C-BS>` | Delete previous word (insert) |
| `<C-H>`, `<C-BS>` | Delete previous word (cmdline) |
| `<C-Del>` | Delete next word |
| `Tab` / `S-Tab` (insert) | Completion / snippet navigation |

`<C-h>` / `<C-l>` mirror <kbd>Ctrl</kbd>+<kbd>←</kbd> / <kbd>Ctrl</kbd>+<kbd>→</kbd>. Insert-mode
`<C-h>` no longer deletes; word deletion there is `<C-BS>` (requires a terminal
with Kitty Keyboard Protocol support — Alacritty 0.13+).

### Clipboard

| Key | Action |
| :-- | :-- |
| `y` / `p` | Neovim registers only — does **not** touch the system clipboard |
| `<leader>y` | Yank line/selection to the system clipboard |
| `<leader>p` / `<leader>P` | Paste from clipboard (after / before) |
| `<C-S-c>` | Copy selection to clipboard (visual) |
| `<C-S-v>` | Paste from clipboard (normal / visual / insert / cmd) |

### Comments

One key everywhere: `gc`.

| Mode | Action |
| :-- | :-- |
| Normal | Toggle `//` on the current line |
| Visual line, 1 line | Toggle `//` |
| Visual line, 2+ lines | Formatter-style `/*` + ` * ` block |
| Visual block | Wrap only the selected part of each line in `/* ... */` |

Blocks are uncommented even after the formatter rewrites them (`*` prefixes,
spacing or tab variations). `gcc`, `gb`, `gco` and the other Comment.nvim
mappings are removed; `gc` is the only comment key.

### Markdown & Obsidian

Active in `markdown` buffers only.

| Key | Action |
| :-- | :-- |
| `<C-b>` | **Bold** (normal / visual / insert) |
| `<C-i>`, `Tab` | *Italic* |
| `<C-e>` | `Inline code` |
| `<C-s>` | ~~Strikethrough~~ |
| `<leader>lh` | ==Highlight== |
| `<C-k>` | Insert link `[text](url)` |
| `<leader>l` | Insert wikilink `[[Note]]` |
| `<C-1>` … `<C-6>` | Heading level 1–6 (press again to clear) |
| `<C-Enter>` | Toggle checkbox `- [ ] ↔ - [x]` |
| `<Enter>` | Continue list / next ordered number |
| `<Shift-Enter>` | Soft break, aligned to the item's content column |
| `o` | New item below |
| `<leader>q` | Toggle block quote |
| `Tab` / `S-Tab` (visual) | Indent / outdent |

Behavioral details:

- Emphasis toggles the **whole span** the cursor sits in, and handles
  `***bold italic***` style combinations without corrupting them.
- Ordering is renumbered on edits and on insert-leave, skipping fenced code
  blocks.
- Normal-mode `<Enter>` only toggles *existing* checkboxes; it never converts a
  plain list item into one.

### Java (jdtls)

Buffer-local, loaded from `ftplugin/java.lua`.

| Key | Action |
| :-- | :-- |
| `<leader>jo` | Organize imports |
| `<leader>jc` | Extract constant |
| `<leader>jv` | Extract variable |
| `<leader>jt` | Run test class |
| `<leader>jT` | Run nearest test method |
| `K` | Hover documentation |
| `gd` | Go to definition |

### AI (opencode.nvim)

| Key | Action |
| :-- | :-- |
| `<leader>o…` | opencode actions (prefix `<leader>o`) |
| `<leader>out` | Toggle tool output |
| `<leader>our` | Toggle reasoning output |
| `<leader>oum` | Toggle max messages |

### Neovide

| Key | Action |
| :-- | :-- |
| `<F11>` | Toggle fullscreen |
| `<C-S-n>` | Open Alacritty in the current directory |

---

## Architecture

```text
~/.config/nvim/
├── init.lua                  # Entry: leader → options → lazy → keymaps
├── ftplugin/
│   ├── java.lua              # jdtls + Lombok + debug/test bundles
│   └── markdown.lua          # Markdown keymaps (buffer-local, thin wiring)
├── lib/
│   └── lombok.jar            # Fallback Lombok agent
├── queries/
│   └── typescript/injections.scm   # Treesitter injection override
├── lua/
│   ├── config/               # Non-plugin core
│   │   ├── options.lua       # vim.opt, autocmds, htmlangular detection
│   │   ├── lazy.lua          # lazy.nvim bootstrap + { import = "plugins" }
│   │   ├── keymaps.lua       # Global keymaps + layout manager
│   │   ├── indent.lua        # Custom indentexpr (VSCode onEnterRules)
│   │   ├── comments.lua      # Single gc comment toggle (formatter-aware)
│   │   ├── templates.lua     # BufNewFile skeletons (9 languages)
│   │   └── markdown.lua      # Obsidian-style markdown engine (pure logic)
│   └── plugins/              # One file per plugin group (lazy specs)
└── tests/                    # Headless specs
```

**Load order** — `init.lua` sets `mapleader` first, then `config.options`, then
`config.lazy` (which bootstraps lazy.nvim and imports every module in
`lua/plugins/`), then `config.keymaps` last so plugin commands like Telescope
exist when the mappings are created, then `config.templates` for the
`BufNewFile` autocmd and `config.comments` for `gc`.

**File templates** — `config/templates.lua` seeds a buffer only when it is a
brand-new, empty file (`BufNewFile` + pristine-buffer check). Java derives the
`package` line when the path contains `src/main/java` or `src/test/java`, and
the class name is PascalCased from the filename. Files outside those project
layouts are treated as standalone and get a `main` method. Python is
intentionally left empty. Headers get `#ifndef` guards named after the file. C# uses the filename
as the class name with a `Main(string[] args)` entry point and a file-scoped
`namespace` derived from the nearest `.csproj` (project name + subfolders);
without a `.csproj` it emits no namespace. Go, Kotlin and Rust get a bare
`main`; PHP gets the `<?php` opener. Ruby is intentionally empty. Neo-tree
creates files without opening a buffer, so its `file_added` event feeds
zero-byte files through the same builder (`seed_file`).

**Filetype layer** — `ftplugin/` and the `FileType` autocmds in
`config/options.lua` and `lua/plugins/treesitter.lua` attach LSP, indent and
keymaps only where they belong, keeping global state untouched.

**Markdown split** — `lua/config/markdown.lua` holds the logic (cursor
geometry, span detection, list parsing and renumbering) and defines no
keymaps; `ftplugin/markdown.lua` only binds keys to it. This is what makes the
engine testable headlessly.

**Web indentation** — for `html`, `htmlangular`, `javascript`, `typescript`
and JSX/TSX, Treesitter indent is deliberately disabled and `indent.lua`'s rule
table (`mode` / `before` / `before_not` / `current` / `action`) drives
`indentexpr` instead.

**Layout manager** — an autocmd group in `config/keymaps.lua` pins Neo-tree to
the far left (~25%) and the opencode pane to the far right, re-applying widths
whenever windows open, close or the editor resizes.

---

## Testing

The specs run against a **clean** Neovim (`-u NONE`) and load only the code
under test:

```bash
nvim --headless -u NONE -l tests/keymap_word_nav_spec.lua
nvim --headless -u NONE -l tests/markdown_list_spec.lua
nvim --headless -u NONE -l tests/markdown_mapping_spec.lua
nvim --headless -u NONE -l tests/obsidian_checkbox_spec.lua
nvim --headless -u NONE -l tests/templates_spec.lua
nvim --headless -u NONE -l tests/comments_spec.lua
```

Each prints `ok` / `FAIL` lines and exits non-zero on failure, so they drop
into CI as-is.

| Spec | Covers |
| :-- | :-- |
| `keymap_word_nav_spec` | `<C-h>` / `<C-l>` aliases — normal, insert and all visual modes match `<C-Left>` / `<C-Right>` |
| `markdown_list_spec` | List parsing, continuation, renumbering |
| `markdown_mapping_spec` | `ftplugin/markdown.lua` bindings |
| `obsidian_checkbox_spec` | Normal-mode `<Enter>` never creates checkboxes |
| `templates_spec` | `BufNewFile` + `seed_file` templates (Java/C/C++/headers/C#/Go/Kotlin/Rust/PHP), package/namespace detection, existing files untouched |
| `comments_spec` | `gc` normal/line/block toggles, formatter-style blocks, `//` round-trip |

---

## Customization

**Leader**

```lua
-- init.lua
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
```

**Add a plugin** — drop a new spec file into `lua/plugins/`; it is picked up
automatically by the `{ import = "plugins" }` glob.

```lua
-- lua/plugins/my-plugin.lua
return {
  "author/my-plugin.nvim",
  event = "VeryLazy",
  opts = {},
}
```

**Formatters** — extend `formatters_by_ft` in `lua/plugins/conform.lua`.
Markdown is intentionally excluded so Prettier cannot re-wrap prose.

**Lombok** — resolved in this order: `./lib/lombok.jar` in the current project
→ `~/.config/nvim/lib/lombok.jar` → the jar bundled with jdtls.

**Obsidian vaults** — the `workspaces` table in `lua/plugins/obsidian.lua`
points at personal paths; replace them with your own.

---

## Notes & Caveats

- **JDK path is hardcoded** in `ftplugin/java.lua`
  (`/usr/lib/jvm/java-21-openjdk`). Change it for your machine.
- **`render-markdown.nvim` loads from a local fork** at
  `~/dev/render-markdown.nvim` because it carries a downstream patch. Without
  that checkout the plugin will not load — point the `dir` at your own copy or
  swap it for the upstream repo.
- **`lazy-lock.json` is gitignored**, so plugin versions are not pinned across
  machines.
- **`lib/lombok.jar` is committed** to give jdtls a Lombok agent even when a
  project ships none.
- Some comments in the Lua sources are in Turkish.
