local TreeSitter = {}

---@class ContainingFunction
---@field name string
---@field range Range4 Zero-based byte coordinates, end-exclusive
---@field selection_range Range4 The function name range, in the same byte coordinates

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
  if #names ~= 1 then
    return
  end

  local target = names[1]
  return {
    name = vim.treesitter.get_node_text(target, bufnr),
    range = { outer:range() },
    selection_range = { target:range() },
  }
end

return TreeSitter
