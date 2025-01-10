local M = {}

---Navigate outwards until we find a node that is of type that has the word function in it
---@param node TSNode | nil
---@return TSNode | nil
local function find_outer_function_node(node)
  while true do
    if not node then
      return
    end
    local type = node:type()
    if type:find("function") then
      return node
    end
    node = node:parent()
  end
end

local function find_function_name_node(node)
  local outer = find_outer_function_node(node)
  if not outer then
    return
  end
  local names = outer:field("name")
  if #names == 0 then
    return
  end
  if #names > 1 then
    print("It's too much. Please take mercy on me")
    return
  end
  return names[1]
end

M.find_function = function()
  local node = vim.treesitter.get_node()
  local target = find_function_name_node(node)
  if target then
    local start_row, start_col, _ = target:start()
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  end
end

return M
