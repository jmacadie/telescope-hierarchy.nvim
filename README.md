# Telescope Hierarchy

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) extension for navigating the call hierarchy. It works through the attached LSP, so if the LSP doesn't offer call hierarchy, [Lua-ls](https://github.com/LuaLS/lua-language-server) I'm 👀 at you, this extension won't do anything.

![image](https://github.com/user-attachments/assets/4120f28c-52f2-4c92-8c1e-147dd37efa25)

# Usage

`:Telescope hierarchy incoming_calls` opens a Telescope window. It finds all incoming calls (i.e. other functions) of the function under the current cursor. Recursive searches are only done on request when the function node is first attempted to be expanded.

`:Telescope hierarchy outgoing_calls` will do the same but in the other direction, so find the definition location of all functions the current function calls.

The finder window is opened in normal mode, since filtering the results tree doesn't make much sense.

The following keymaps are set:

| Key | Action |
| --- | --- |
| `e`, `l` or `→` | Expand the current node: this will recursively find all incoming calls of the current node. It will only go the next level deep though |
| `c`, `h` or `←` | Collapse the current node: the child calls are still found, just hidden in the finder window |
| `t` | Toggle the expanded state of the current node |
| `s` | Switch the direction of the Call hierarchy and toggle between incoming and outgoing calls |
| `CR` | Navigate to the function call shown |
| `q` or `ESC` | Quit the Telescope finder |

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

# See Also

This extension is very new, there may well be better options for you

- [telescope-undo.nvim](https://github.com/debugloop/telescope-undo.nvim/tree/main) showed me that a treeview was possible in the finder window and * ahem * inspired certain parts of this extension's code
- [hierarchy-tree-go.nvim](https://github.com/crusj/hierarchy-tree-go.nvim) not integrated with Telescope, tied to Go & looks to be no longer maintained but it does exactly what we're trying to do here and the LSP calls all seem to be of the same structure
- [calltree.nvim](https://github.com/marcomayer/calltree.nvim) Another dormant project (which is not to say that it doesn't work!) and with no Telescope integration. This project also includes a symbols navigation, which is pretty neat
- [nvimdev](https://nvimdev.github.io/lspsaga/callhierarchy/) not integrated with Telescope & part of a larger suite of LSP tools. This is a better, more mature solution to the problem
- [Telescope builtin](https://github.com/nvim-telescope/telescope.nvim/blob/master/lua/telescope/builtin/__lsp.lua#L113) Telescope has it's own call hierarchy builtin. It just makes the first level call, and so to get recursive search you would need to navigate to the next code call and then call hierarchy again
- [Trouble.nvim](https://github.com/folke/trouble.nvim) Folke's own add-in. It only works one layer deep though, like the Telescope built-in and so suffers the same limitation. There is [a closed issue to enhance this](https://github.com/folke/trouble.nvim/issues/463)
- [Neovim](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/buf.lua#L907) The core Neovim runtime lua offers a way to run the call hierarchy. Like the Telescope builtin, it is only one level deep. It dumps the results in the quickfix list. Depending on your situation, you may just want to use the core stuff. It's good and will always be maintained. See also [this issue](https://github.com/neovim/neovim/issues/26817)

# Roadmap

- Make the initial find smarter. It will _only_ work if the cursor is on the function name. I think it would be preferable to be triggerable from anywhere on the function declaration line (or lines)
- Make the Finder window a bit prettier?
  - We could have a setting for different tree styles. Could use right / down arrows to indicate collapsed nodes & show no lines as an alternate display mode
- Include a history, to go back to a previous call history state. This will be useful once we can toggle between incoming and outgoing calls, as this will need to re-render the root node, losing the previous root in the process
- Use the same infrastructure to show Class hierarchies as well. It's basically the same thing
- Ditto for Document Symbols which also have a hierarchical nature
