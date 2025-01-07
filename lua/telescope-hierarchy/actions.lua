local finders = require("telescope.finders")
local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local transform_mod = require("telescope.actions.mt").transform_mod

local M = {}

---General code to refresh the picker after the nodes tree has been updated
---@param node Node
---@param picker any -- Really a telescope.pickers.Picker ... but I don't know how to type that properly :(
local function refresh_picker(node, picker)
  local new_finder = finders.new_table({
    results = node:to_list(),
    entry_maker = picker.finder.entry_maker,
  })

  local selection = picker:get_selection_row()
  -- Despite the lua ls deprecation warning, Neovim is not running a recent
  -- enough version of LuaJIT (>5.1) and so the call to `table.unpack` will
  -- fail and we need to use the old `unpack` for now
  -- local callbacks = { table.unpack(picker._completion_callbacks) } -- shallow copy
  ---@diagnostic disable-next-line:deprecated
  local callbacks = { unpack(picker._completion_callbacks) } -- shallow copy
  picker:register_completion_callback(function(self)
    self:set_selection(selection)
    self._completion_callbacks = callbacks
  end)

  picker:refresh(new_finder)
end

M.expand = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry(prompt_bufnr).value

    node:expand(function()
      refresh_picker(node, picker)
    end)
  end
  return f
end

M.collapse = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry(prompt_bufnr).value

    node:collapse(function()
      refresh_picker(node, picker)
    end)
  end
  return f
end

M.toggle = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry(prompt_bufnr).value

    node:toggle(function()
      refresh_picker(node, picker)
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