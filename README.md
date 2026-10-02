# Telescope Hierarchy

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) extension for navigating the call hierarchy. It works
through the attached LSP, so if the LSP doesn't offer call hierarchy,
[Lua-ls](https://github.com/LuaLS/lua-language-server) I'm 👀 at you, this extension won't do anything.

![image](https://github.com/user-attachments/assets/4120f28c-52f2-4c92-8c1e-147dd37efa25)

# Usage

`:Telescope hierarchy incoming_calls` opens a Telescope window. It finds all incoming calls (i.e. other functions) of
the function under the current cursor. Recursive searches are only done on request when the function node is first
attempted to be expanded.

`:Telescope hierarchy outgoing_calls` will do the same but in the other direction, so find the definition location of
all functions the current function calls.

Don't worry about committing to the right 'direction', the plugin can also toggle the direction it is looking in whilst
the Telescope session is running. This means switching from functions that call the current function to functions the
current function calls (incoming -> outgoing) and vice versa. See below in the keymaps for how to do this.

The following keymaps are set:

| Mode | Key | Action |
| --- | --- | --- |
| `i`  | `<c-e>` or `<c-l>` | Expand the current node: this will recursively find all incoming calls of the current node. It will only go the next level deep though |
| `i`  | `<c-m>` | Multi-expand several layers at once. Depends on the `multi-depth` setting how deep it will go, which defaults to 5 layers |
| `i`  | `<c-h>` | Collapse the current node: the child calls are still found, just hidden in the finder window |
| `i`  | `<c-t>` | Toggle the expanded state of the current node |
| `i`  | `<c-s>` | Switch the direction of the Call hierarchy and toggle between incoming and outgoing calls |
| `n`  | `e`, `l` or `→` | Expand the current node: this will recursively find all incoming calls of the current node. It will only go the next level deep though |
| `n`  | `c`, `h` or `←` | Collapse the current node: the child calls are still found, just hidden in the finder window |
| `n`  | `E` | Multi-expand several layers at once. Depends on the `multi-depth` setting how deep it will go, which defaults to 5 layers |
| `n`  | `t` | Toggle the expanded state of the current node |
| `n`  | `s` | Switch the direction of the Call hierarchy and toggle between incoming and outgoing calls |
| `n`  | `d` | Goto the definition of the current node, not the place it is being called, which is what Telescope shows |
| `n`  | `CR` | Navigate to the function call shown |
| `n`  | `q` or `ESC` | Quit the Telescope finder |

# Filtering

Filtering is currently 'opt-in' and will need to be explicitly switched on your settings using `filter_mode = true`. See
[Config](#config) Filtering is based on the visible (expanded/non-collapsed) function names displayed. When a filter
matches on a node in the tree, then that node, and all of its parents are kept while anything not matching is filtered.
The parents are retained so the hierarchy back to the root search remains always visible.

Filtering can also retain any child calls of a matching node, even if they themselves do not match the search text. This
is controlled by the `filter_include_children` setting. By default this is set to `true`.

There is an additional relevant setting `filter_start_insert`. If you start in insert mode, then anything typed will be
treated as an attempt to filter the treeview. By default this is set to be `true`. For this reason the expand, collapse,
toggle etc shortcuts have Ctrl equivalents to ensure that they are still functional in insert mode. If you want to use
the standard shortcuts then you will need to revert to "normal" mode, typically by pressing `<ESC>`. Alternatively, if
you would like the option to be able to filter but would rather start in "normal" mode, you may set `filter_start_insert
= false` in your configs.

# Type Hierarchy

The LSP specification also includes the possibility to explore the type hierarchy (i.e. supertypes and subtypes) and the
request pattern is almost identical to call hierarchy. So much so that you may be wondering why this plugin doesn't
support it. Well the truth is that I have blindly written out the code to support type hierarchy ... but I don't run an
LSP that offers this capability so I cannot test my code. The two LSPs I have found that do offer type hierarchy support
are clangd and Eclipse JDT, there may well be more out there and over time the pool of working LSPs will grow. However,
since I can't test the code I'm not super happy about pushing it into main. I have pushed up a branch: 'feature/types'
with my untested code, which I will endeavour to keep rebased on top of main.

If you are a kindly soul, in possession of a valid LSP and are interested in testing for me, please let me know by
raising an issue. It would be nice to get it merged in.

# Install

**This plugin requires Neovim v0.10 or greater**. The native `vim.pack` installation below requires **Neovim v0.12
or greater**.

## Native package manager (`vim.pack`)

Neovim's built-in [package manager](https://neovim.io/doc/user/pack.html#vim.pack) can install the extension without a
third-party plugin manager. Add the following to your `init.lua`:

```lua
vim.pack.add({
  { src = "https://github.com/nvim-lua/plenary.nvim" },
  { src = "https://github.com/nvim-telescope/telescope.nvim" },
  { src = "https://github.com/jmacadie/telescope-hierarchy.nvim" },
})

require("telescope").setup({
  extensions = {
    hierarchy = {
      -- telescope-hierarchy.nvim config, see below
    },
  },
})
require("telescope").load_extension("hierarchy")

-- Choose your own keys, this works for me
vim.keymap.set("n", "<leader>si", "<cmd>Telescope hierarchy incoming_calls<cr>", {
  desc = "LSP: [S]earch [I]ncoming Calls",
})
vim.keymap.set("n", "<leader>so", "<cmd>Telescope hierarchy outgoing_calls<cr>", {
  desc = "LSP: [S]earch [O]utgoing Calls",
})
```

`vim.pack.add()` installs missing plugins and makes them available before the setup calls. Dependencies must be listed
explicitly, so the example includes both Telescope and Plenary. If you already install these with `vim.pack`, keep
those entries in your existing list and add only `telescope-hierarchy.nvim`. Likewise, if you already configure
Telescope, add `extensions.hierarchy` to your existing setup and load the extension after it.

## Lazy

Using Lazy, with a separate module for this extension's config:

```lua ...\lua\plugins\telescope-hierarchy.lua
return {
  "jmacadie/telescope-hierarchy.nvim",
  dependencies = {
    {
      "nvim-telescope/telescope.nvim",
      dependencies = { "nvim-lua/plenary.nvim" },
    },
  },
  keys = {
    { -- lazy style key map
      -- Choose your own keys, this works for me
      "<leader>si",
      "<cmd>Telescope hierarchy incoming_calls<cr>",
      desc = "LSP: [S]earch [I]ncoming Calls",
    },
    {
      "<leader>so",
      "<cmd>Telescope hierarchy outgoing_calls<cr>",
      desc = "LSP: [S]earch [O]utgoing Calls",
    },
  },
  opts = {
    -- don't use `defaults = { }` here, do this in the main telescope spec
    extensions = {
      hierarchy = {
        -- telescope-hierarchy.nvim config, see below
      },
      -- no other extensions here, they can have their own spec too
    },
  },
  config = function(_, opts)
    -- Calling telescope's setup from multiple specs does not hurt, it will happily merge the
    -- configs for us. We won't use data, as everything is in it's own namespace (telescope
    -- defaults, as well as each extension).
    require("telescope").setup(opts)
    require("telescope").load_extension("hierarchy")
  end,
}
```

The extension can also be configured directly as part of the Telescope plugin. Rather than write out my own, I refer you
to [debugloop's excellent documentation](https://github.com/debugloop/telescope-undo.nvim/tree/main?tab=readme-ov-file#installation)

# Config

The usual [Telescope config options](https://github.com/nvim-telescope/telescope.nvim?tab=readme-ov-file#customization)
can be used with this extension

Telescope hierarchy specific settings default to the following, so you only need specify these if you want to change any
of the settings. For Lazy, use the `opts` table below in your plugin spec. With `vim.pack`, pass the contents of `opts`
(the `extensions` table) to `require("telescope").setup()` instead.

```lua
  opts = {
    extensions = {
      hierarchy = {
        -- telescope-hierarchy.nvim config
        initial_multi_expand = false, -- Run a multi-expand on open? If false, will only expand one layer deep by default
        multi_depth = 5, -- How many layers deep should a multi-expand go?
        filter_mode = false, -- Is filter mode enabled?
        filter_start_insert = true, -- If filter mode is enabled, should the picker start in insert mode
        filter_include_children = true, -- If filter mode is enabled, should children of matched calls be retained?
        layout_strategy = "horizontal",
      },
    },
  },
```

Settings can be included by exception, so if you only want 'Multi-expand' to go to 10 layers deep, but the rest of the
defaults are fine, then you settings will look like this:

```lua
  opts = {
    extensions = {
      hierarchy = {
        -- telescope-hierarchy.nvim config
        multi_depth = 10, -- How many layers deep should a multi-expand go?
      },
    },
  },
```

# Development and testing

Run the complete quality gate from the repository root:

```sh make check ```

This runs **Luacheck**, **StyLua's formatting check**, then the **test suite in headless Neovim**. Warnings, formatting
differences, and failed tests all return a non-zero exit code and stop the command. It does not automatically change
your code or repeatedly try to fix failures: fix the reported problems and rerun it. For another build/release command,
use `make check && your-command`.

## Prerequisites

- Neovim 0.10 or newer, Git, and Make.
- [Luacheck](https://github.com/lunarmodules/luacheck) (CI uses Ubuntu's `lua-check` package).
- [StyLua](https://github.com/JohnnyMorganz/StyLua), version **2.5.2**, on `PATH`.

For Ubuntu/WSL, install Luacheck with `sudo apt install lua-check`. StyLua can be installed using its prebuilt release
binary or, if Rust is installed, `cargo install stylua --locked --version 2.5.2`.

On its first test run, Make downloads pinned `mini.test`, Plenary, and Telescope checkouts into `.deps/` (ignored by
Git). `mini.test` is the test framework; Plenary remains necessary for the plugin's current implementation and
Telescope, not for running the framework. Subsequent runs reuse these checkouts, so only the first run needs network
access. Delete `.deps/` to rebuild the test dependencies. No personal Neovim config, language server, or Tree-sitter
parser is required.

Individual commands are also available:

```sh
make lint          # static analysis; warnings fail too
make format-check  # verify formatting without changing files
make format        # apply formatting
make test          # headless tests only
```

Tools can be overridden, for example:
`make check NVIM=/path/to/nvim STYLUA=/path/to/stylua`.

## Writing tests

Tests live in `tests/spec/*_spec.lua` and use [`mini.test`](https://github.com/nvim-mini/mini.test)'s native test sets
(no Busted compatibility layer). Each file returns a set created with `test.new_set()`:

```lua
local test = require("mini.test")
local T = test.new_set()

T["example"] = function()
  test.expect.equality(1 + 1, 2)
end

return T
```

`tests/run.lua` collects and executes these sets, reports results to stdout, and exits with a non-zero status on test
failures, collection errors, or an empty suite. Tests run sequentially in one headless Neovim process. The LSP transport
is mocked so responses can be delivered deterministically, including pending and out-of-order cases. Use
`hooks.pre_case` and `hooks.post_case` for setup and cleanup; restore mocks and shared state to avoid test pollution.
Use `rawequal` when asserting object identity, since `test.expect.equality` compares structure.

The initial suite covers cache identity/reuse, pending searches, call-site sorting/deduplication, recursion, tree
rendering, depth-limited expansion, LSP completion/error handling, and loading the extension through Telescope. It does
not yet exercise an interactive picker or a real language server.

Only specs in `tests/spec/` are collected as tests; those specs and the test bootstrap/runner are linted and
formatting-checked. Standalone exploratory scripts such as `tests/containing_function.lua` are not part of this gate;
that script targets containing-function/reference-fallback APIs not present in this checkout and requires a Lua parser.
New supported regression tests should go in `tests/spec/`.

`.github/workflows/check.yml` runs the same `make check` on pull requests and pushes, against both Neovim 0.10.4 (the
minimum supported series) and the current stable release. To **prevent merging** until checks pass, enable branch
protection or a repository ruleset and require both `Check` matrix jobs. A workflow alone reports failures but does not
prevent merging without that repository setting.

# See Also

This extension is very new, there may well be better options for you

- [telescope-undo.nvim](https://github.com/debugloop/telescope-undo.nvim/tree/main) showed me that a treeview was
  possible in the finder window and * ahem * inspired certain parts of this extension's code
- [hierarchy-tree-go.nvim](https://github.com/crusj/hierarchy-tree-go.nvim) not integrated with Telescope, tied to Go &
  looks to be no longer maintained but it does exactly what we're trying to do here and the LSP calls all seem to be of
  the same structure
- [calltree.nvim](https://github.com/marcomayer/calltree.nvim) Another dormant project (which is not to say that it
  doesn't work!) and with no Telescope integration. This project also includes a symbols navigation, which is pretty
  neat
- [nvimdev / lspsaga](https://nvimdev.github.io/lspsaga/callhierarchy/) not integrated with Telescope & part of a larger
  suite of LSP tools. This is a better, more mature solution to the problem
- [hierarchy.nvim](https://github.com/lafarr/hierarchy.nvim) A very new plugin that offers stand-alone hierarchy
  navigation
- [Slyces/hierarchy.nvim](https://github.com/Slyces/hierarchy.nvim) Looks like a hack to get type hierarchy working in
  the absence of LSP providing the functionality
- [Telescope builtin](https://github.com/nvim-telescope/telescope.nvim/blob/master/lua/telescope/builtin/__lsp.lua#L113)
  Telescope has it's own call hierarchy builtin. It just makes the first level call, and so to get recursive search you
  would need to navigate to the next code call and then call hierarchy again
- [Trouble.nvim](https://github.com/folke/trouble.nvim) Folke's own add-in. It only works one layer deep though, like
  the Telescope built-in and so suffers the same limitation. There is [a closed issue to enhance
  this](https://github.com/folke/trouble.nvim/issues/463)
- [Neovim](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L907) The core Neovim runtime lua
  offers a way to run the call hierarchy. Like the Telescope builtin, it is only one level deep. It dumps the results in
  the quickfix list. Depending on your situation, you may just want to use the core stuff. It's good and will always be
  maintained. See also [this issue](https://github.com/neovim/neovim/issues/26817)

# Roadmap

- Make the Finder window a bit prettier?
  - We could have a setting for different tree styles. Could use right / down arrows to indicate collapsed nodes & show
    no lines as an alternate display mode
- ~~Sometimes two (or more) different nodes in a tree refer to the same code location. When we search one we should
  search them all~~
- ~~Could we auto-search all nodes to a depth of (say) 5 nodes? I wouldn't want to make it unlimited as recursive
  functions will generate an infinite call tree!~~
- Include a history, to go back to a previous call history state. This will be useful once we can toggle between
  incoming and outgoing calls, as this will need to re-render the root node, losing the previous root in the process
- ~~Use the same infrastructure to show Class hierarchies as well. It's basically the same thing~~ This is done but
  please see the type hierarchy section of this readme for more info
- Ditto for Document Symbols which also have a hierarchical nature
