# Telescope Hierarchy

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) extension for navigating the call hierarchy. It works through the attached LSP, so if the LSP doesn't offer call hierarchy, [Lua-ls](https://github.com/LuaLS/lua-language-server) I'm 👀 at you, this extension won't do anything by default. However, an optional reference-based fallback can be enabled (see [Config](#config) section) that uses LSP references to build the incoming call hierarchy when call hierarchy is not supported.

![image](https://github.com/user-attachments/assets/4120f28c-52f2-4c92-8c1e-147dd37efa25)

# Usage

`:Telescope hierarchy incoming_calls` opens a Telescope window. It finds all incoming calls (i.e. other functions) of the function under the current cursor. Recursive searches are only done on request when the function node is first attempted to be expanded.

`:Telescope hierarchy outgoing_calls` will do the same but in the other direction, so find the definition location of all functions the current function calls.

Don't worry about committing to the right 'direction', the plugin can also toggle the direction it is looking in whilst the Telescope session is running. This means switching from functions that call the current function to functions the current function
calls (incoming -> outgoing) and vice versa. See below in the keymaps for how to do this.

The finder window is opened in normal mode, since filtering the results tree doesn't make much sense.

The following keymaps are set:

| Key | Action |
| --- | --- |
| `e`, `l` or `→` | Expand the current node: this will recursively find all incoming calls of the current node. It will only go the next level deep though |
| `c`, `h` or `←` | Collapse the current node: the child calls are still found, just hidden in the finder window |
| `E` | Multi-expand several layers at once. Depends on the `multi-depth` setting how deep it will go, which defaults to 5 layers |
| `t` | Toggle the expanded state of the current node |
| `s` | Switch the direction of the Call hierarchy and toggle between incoming and outgoing calls |
| `d` | Goto the definition of the current node, not the place it is being called, which is what Telescope shows |
| `CR` | Navigate to the function call shown |
| `q` or `ESC` | Quit the Telescope finder |

# Type Hierarchy

The LSP specification also includes the possibility to explore the type hierarchy (i.e. supertypes and subtypes) and the request pattern is almost identical to call hierarchy. So much so that you may be wondering why this plugin doesn't support it.
Well the truth is that I have blindly written out the code to support type hierarchy ... but I don't run an LSP that offers this capability so I cannot test my code. The two LSPs I have found that do offer type hierarchy support are clangd and
Eclipse JDT, there may well be more out there and over time the pool of working LSPs will grow. However, since I can't test the code I'm not super happy about pushing it into main. I have pushed up a branch: 'feature/types' with my untested code,
which I will endeavour to keep rebased on top of main.

If you are a kindly soul, in possession of a valid LSP and are interested in testing for me, please let me know by raising an issue. It would be nice to get it merged in.

# Install

**This plugin requires Neovim v0.10 or greater**

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

The extension can also be configured directly as part of the Telescope plugin. Rather than write out my own, I refer you to [debugloop's excellent documentation](https://github.com/debugloop/telescope-undo.nvim/tree/main?tab=readme-ov-file#installation)

# Config

The usual [Telescope config options](https://github.com/nvim-telescope/telescope.nvim?tab=readme-ov-file#customization) can be used with this extension

Telescope hierarchy specific settings default to the following, so you only need specify these if you want to change any of the settings. Insert the below in place of the Install instructions to change settings

```lua
  opts = {
    extensions = {
      hierarchy = {
        -- telescope-hierarchy.nvim config
        initial_multi_expand = false, -- Run a multi-expand on open? If false, will only expand one layer deep by default
        multi_depth = 5, -- How many layers deep should a multi-expand go?
        multi_depth_reference_fallback = 2, -- How many layers deep should a multi-expand go when using reference fallback?
        enable_reference_fallback = false, -- Use LSP references as fallback when call hierarchy is not supported (incoming calls only)
        layout_strategy = "horizontal",
      },
    },
  },
```

Settings can be included by exception, so if you only want 'Multi-expand' to go to 10 layers deep, but the rest of the defaults are fine, then you settings will look like this:

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

## Reference Fallback

When an LSP doesn't support call hierarchy (e.g., Lua-ls), you can enable the reference-based fallback by setting `enable_reference_fallback = true`. This feature:

- **Only works for incoming calls** (finding who calls a function)
- Uses `textDocument/references` LSP method instead of `textDocument/prepareCallHierarchy`
- Shows "(Reference Fallback Mode)" in the picker title when active
- Disables direction switching (the `s` keymap) since outgoing calls cannot be determined from references alone
- Supports recursive expansion using the `multi_depth_reference_fallback` setting (defaults to 2 layers)

Note: The reference-based approach is less precise than true call hierarchy as it shows all references, not just function calls.

# See Also

This extension is very new, there may well be better options for you

- [telescope-undo.nvim](https://github.com/debugloop/telescope-undo.nvim/tree/main) showed me that a treeview was possible in the finder window and * ahem * inspired certain parts of this extension's code
- [hierarchy-tree-go.nvim](https://github.com/crusj/hierarchy-tree-go.nvim) not integrated with Telescope, tied to Go & looks to be no longer maintained but it does exactly what we're trying to do here and the LSP calls all seem to be of the same structure
- [calltree.nvim](https://github.com/marcomayer/calltree.nvim) Another dormant project (which is not to say that it doesn't work!) and with no Telescope integration. This project also includes a symbols navigation, which is pretty neat
- [nvimdev / lspsaga](https://nvimdev.github.io/lspsaga/callhierarchy/) not integrated with Telescope & part of a larger suite of LSP tools. This is a better, more mature solution to the problem
- [hierarchy.nvim](https://github.com/lafarr/hierarchy.nvim) A very new plugin that offers stand-alone hierarchy navigation
- [Slyces/hierarchy.nvim](https://github.com/Slyces/hierarchy.nvim) Looks like a hack to get type hierarchy working in the absence of LSP providing the functionality
- [Telescope builtin](https://github.com/nvim-telescope/telescope.nvim/blob/master/lua/telescope/builtin/__lsp.lua#L113) Telescope has it's own call hierarchy builtin. It just makes the first level call, and so to get recursive search you would need to navigate to the next code call and then call hierarchy again
- [Trouble.nvim](https://github.com/folke/trouble.nvim) Folke's own add-in. It only works one layer deep though, like the Telescope built-in and so suffers the same limitation. There is [a closed issue to enhance this](https://github.com/folke/trouble.nvim/issues/463)
- [Neovim](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L907) The core Neovim runtime lua offers a way to run the call hierarchy. Like the Telescope builtin, it is only one level deep. It dumps the results in the quickfix list. Depending on your situation, you may just want to use the core stuff. It's good and will always be maintained. See also [this issue](https://github.com/neovim/neovim/issues/26817)

# Roadmap

- Make the Finder window a bit prettier?
  - We could have a setting for different tree styles. Could use right / down arrows to indicate collapsed nodes & show no lines as an alternate display mode
- ~~Sometimes two (or more) different nodes in a tree refer to the same code location. When we search one we should search them all~~
- ~~Could we auto-search all nodes to a depth of (say) 5 nodes? I wouldn't want to make it unlimited as recursive functions will generate an infinite call tree!~~
- Include a history, to go back to a previous call history state. This will be useful once we can toggle between incoming and outgoing calls, as this will need to re-render the root node, losing the previous root in the process
- ~~Use the same infrastructure to show Class hierarchies as well. It's basically the same thing~~ This is done but please see the type hierarchy section of this readme for more info
- Ditto for Document Symbols which also have a hierarchical nature
