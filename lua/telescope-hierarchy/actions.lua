local finders = require("telescope.finders")
local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local transform_mod = require("telescope.actions.mt").transform_mod

local ui = require("telescope-hierarchy.ui")

local M = {}

---General code to refresh the picker after the nodes tree has been updated
---@param node Node
---@param picker Picker
---@param keep_selection? boolean Retain the current selection after refresh. If ommitted will assume true
local function refresh_picker(node, picker, keep_selection)
  local new_finder = finders.new_table({
    results = node:to_list(),
    -- LSP doesn't like entry_maker field of finder
    ---@diagnostic disable-next-line:undefined-field
    entry_maker = picker.finder.entry_maker,
  })

  if keep_selection or keep_selection == nil then
    local selection = picker:get_selection_row()
    local callbacks = { unpack(picker._completion_callbacks) } -- shallow copy
    picker:register_completion_callback(function(self)
      self:set_selection(selection)
      self._completion_callbacks = callbacks
    end)
  end
  picker:refresh(new_finder, {})
end

M.expand = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:expand(function(tree)
      refresh_picker(tree, picker)
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
      refresh_picker(tree, picker)
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
      refresh_picker(tree, picker)
    end)
  end
  return f
end

M.switch = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:switch_direction(function(tree)
      picker.results_border:change_title(ui.title())
      refresh_picker(tree, picker, false)
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

return transform_mod(M)
