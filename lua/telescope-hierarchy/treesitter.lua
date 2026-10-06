local TreeSitter = {}

---@class ContainingFunction
---@field name string
---@field range Range4 Zero-based byte coordinates, end-exclusive
---@field selection_range Range4 The callable identifier range, in the same byte coordinates

---Navigate outwards to the nearest function definition, not a function call.
---Do not skip anonymous functions: references inside them must not be attributed
---to an enclosing named function.
---@param node TSNode | nil
---@return TSNode | nil
local function find_outer_function_node(node)
  while node do
    local node_type = node:type()
    if node_type:find("function") and not node_type:find("call") then
      return node
    end
    node = node:parent()
  end
end

---Resolve a Lua function literal directly assigned to a variable or table field.
---Match the RHS position to the LHS; do not walk past anonymous callbacks.
---@param outer TSNode
---@return TSNode | nil name
---@return TSNode | nil definition
local function assigned_lua_function(outer)
  local expressions = outer:parent()
  local assignment = expressions and expressions:parent()
  if not expressions or expressions:type() ~= "expression_list" then
    return
  end
  if not assignment or assignment:type() ~= "assignment_statement" then
    return
  end
  local variables = assignment:named_child(0)
  if not variables or variables:type() ~= "variable_list" then
    return
  end
  local names = variables:field("name")
  for index, value in ipairs(expressions:field("value")) do
    if value == outer then
      local name = names[index]
      -- Dynamic keys cannot be used as a stable callable identifier.
      if name and (name:type() == "identifier" or name:type() == "dot_index_expression") then
        return name, assignment
      end
      return
    end
  end
end

---Find the nearest containing named function without changing buffers or cursors.
---Positions and returned ranges use Tree-sitter's zero-based byte coordinates.
---Returns nil if no named function or parser is available.
---@param bufnr integer
---@param row integer
---@param byte_col integer
---@return ContainingFunction | nil
function TreeSitter.containing_function(bufnr, row, byte_col)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local filetype = vim.bo[bufnr].filetype
  if filetype == "" then
    filetype = vim.filetype.match({ buf = bufnr })
  end
  local lang = filetype and vim.treesitter.language.get_lang(filetype)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return
  end

  -- Background buffers may not have a highlighter to keep their parse up to date.
  local parsed = pcall(function()
    parser:parse()
  end)
  if not parsed then
    return
  end

  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, byte_col }, lang = lang })
  local outer = find_outer_function_node(node)
  if not outer then
    return
  end
  local names = outer:field("name")
  local target = #names == 1 and names[1] or nil
  ---@type TSNode | nil
  local definition = outer
  if not target and lang == "lua" and outer:type() == "function_definition" then
    target, definition = assigned_lua_function(outer)
  end
  if not target or not definition then
    return
  end

  local selection = target
  -- Lua's qualified name starts at the table, but references must target the
  -- final field/method identifier. Keep the full name for display.
  if target:type() == "dot_index_expression" then
    selection = target:field("field")[1] or target
  elseif target:type() == "method_index_expression" then
    selection = target:field("method")[1] or target
  end
  return {
    name = vim.treesitter.get_node_text(target, bufnr),
    range = { definition:range() },
    selection_range = { selection:range() },
  }
end

return TreeSitter
