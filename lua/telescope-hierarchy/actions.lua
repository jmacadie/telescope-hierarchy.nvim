local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
-- local transform_mod = require("telescope.actions.mt").transform_mod
local Path = require("plenary.path")

local ui = require("telescope-hierarchy.ui")
local state = require("telescope-hierarchy.state")

local M = {}
M.expand = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:expand(function(tree)
      ui.refresh(tree, picker)
    end)
  end
  return f
end

M.multi_expand = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value
    ---@type integer
    local using_fallback = state.get("using_fallback")
    local depth = using_fallback and state.get("multi_depth_reference_fallback") or state.get("multi_depth")

    node:multi_expand(depth, function(tree)
      ui.refresh(tree, picker)
    end)
  end
  return f
end

M.collapse = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:collapse(function(tree)
      ui.refresh(tree, picker)
    end)
  end
  return f
end

M.toggle = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:toggle(function(tree)
      ui.refresh(tree, picker)
    end)
  end
  return f
end

M.switch = function(prompt_bufnr)
  local function f()
    -- Check if we're using reference fallback
    local using_fallback = state.get("using_fallback")
    if using_fallback then
      vim.notify("Direction switching is not available in Reference Fallback mode", vim.log.levels.WARN)
      return
    end
    
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:switch_direction(function(tree)
      picker.results_border:change_title(ui.title())
      ui.refresh(tree, picker, false)
    end)
  end
  return f
end

M.goto_definition = function(prompt_bufnr)
  local function f()
    -- Shamelessly stolen from Telescope
    -- I had to copy paste as I needed to very slightly modify the inner workings
    -- of this one rather long function, so I was unable to import and call Telescope code
    local entry = actions_state.get_selected_entry()
    ---@type Node
    local node = entry.value
    local loc = node.cache.location
    local filename = vim.uri_to_fname(loc.textDocument.uri)
    local row = loc.position.line + 1
    local col = loc.position.character

    local picker = actions_state.get_current_picker(prompt_bufnr)
    require("telescope.pickers").on_close_prompt(prompt_bufnr)
    pcall(function()
      vim.api.nvim_set_current_win(picker.original_win_id)
    end)
    local win_id = picker.get_selection_window(picker, entry)

    if picker.push_cursor_on_edit then
      vim.cmd("normal! m'")
    end

    if picker.push_tagstack_on_edit then
      local from = { vim.fn.bufnr("%"), vim.fn.line("."), vim.fn.col("."), 0 }
      local items = { { tagname = vim.fn.expand("<cword>"), from = from } }
      vim.fn.settagstack(vim.fn.win_getid(), { items = items }, "t")
    end

    if win_id ~= 0 and vim.nvim_get_current_win() ~= win_id then
      vim.api.nvim_set_current_win(win_id)
    end

    -- check if we didn't pick a different buffer
    -- prevents restarting lsp server
    if vim.api.nvim_buf_get_name(0) ~= filename then
      filename = Path:new(filename):normalize(vim.uv.cwd())
      pcall(function()
        vim.cmd(string.format("edit %s", vim.fn.fnameescape(filename)))
      end)
    end

    -- HACK: fixes folding: https://github.com/nvim-telescope/telescope.nvim/issues/699
    if vim.wo.foldmethod == "expr" then
      vim.schedule(function()
        vim.opt.foldmethod = "expr"
      end)
    end

    if vim.api.nvim_buf_get_name(0) == filename then
      vim.cmd([[normal! m']])
    end
    pcall(function()
      vim.api.nvim_win_set_cursor(0, { row, col })
    end)
  end
  return f
end

M.quit = function(prompt_bufnr)
  local function f()
    actions.close(prompt_bufnr)
  end
  return f
end

-- return transform_mod(M)
return M
