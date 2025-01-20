local state = require("telescope-hierarchy.state")

--- Holds reference to a function location in the codebase that represents
--- a part of the call hierarchy
---@class Node
---@field text string The display name of the node
---@field filename string The filename that contains this node
---@field lnum integer The (l-based) line number of the reference
---@field col integer The (1-based) column number of the reference
---@field expanded boolean Is the node expanded in the current representation of the heirarchy tree
---@field cache CacheEntry The cached information about the function location, so we only find a function once
---@field root Node The root of the tree this node is in
---@field children Node[] A list of the children of this node
Node = {}
Node.__index = Node

--- Create a new (unattached) node
---@param uri string The URI representation of the filename where the node is found
---@param text string The display name of the node
---@param lnum integer The (l-based) line number of the reference
---@param col integer The (1-based) column number of the reference
---@param cache CacheEntry
---@return Node
function Node.new(uri, text, lnum, col, cache)
  local node = {
    filename = vim.uri_to_fname(uri),
    text = text,
    lnum = lnum,
    col = col,
    expanded = false,
    cache = cache,
    children = {},
  }
  -- We need to have a reference to a "root" node to make a valid node
  -- For an unattached node, this will be a self reference
  -- It gets over-written in `add_children`
  node.root = node
  setmetatable(node, Node)
  return node
end

---Clone this node to create a copy, that can be put elsewhere in the user tree
---@return Node
function Node:clone()
  local uri = self.cache.location.textDocument.uri
  local clone = Node.new(uri, self.text, self.lnum, self.col, self.cache)
  clone.root = self.root
  return clone
end

---Search the current node
---It will do nothing if the current node has already been searched
---@async
---@param callback fun(node: Node) Function to be run once all children have been processed
function Node:search(callback)
  assert(not self.cache.searched)
  local direction = assert(state.direction())

  ---@param call lsp.CallHierarchyIncomingCall | lsp.CallHierarchyOutgoingCall
  ---@param entry CacheEntry
  local each_cb = function(call, entry)
    local last_line = -1
    local last_char = -1
    local inner = direction:is_incoming() and call.from or call.to
    for _, range in ipairs(call.fromRanges) do
      -- Check for duplicate ranges from LSP
      -- Assumes the duplicates are sequential. Would need to do more work if they are unordered
      if range.start.line ~= last_line and range.start.character ~= last_char then
        local uri = self.cache.location.textDocument.uri
        local child = Node.new(uri, inner.name, range.start.line + 1, range.start.character, entry)
        child.root = self.root -- maintain a common root node
        table.insert(self.children, child)
        last_line = range.start.line
        last_char = range.start.character
      end
    end
  end

  local final_cb = function()
    self.expanded = true
    self.cache.searched_node = self
    callback(self)
  end

  self.cache:find_children(each_cb, final_cb)
end

---Expand the node, searching for children if not already done
---The callback will not be called if the node is already expanded
---@async
---@param callback fun(node: Node) Function to be run once children have been found (async) & the node expanded
function Node:expand(callback)
  if self.expanded then
    return
  end

  if not self.cache.searched then
    self:search(callback)
    return
  end

  if #self.children == 0 then
    local searched = assert(self.cache.searched_node)
    for _, node in ipairs(searched.children) do
      table.insert(self.children, node:clone())
    end
  end

  self.expanded = true
  callback(self)
end

---Collapse the node.
---This function is not actually async but it makes sense to write it this way so it can be
---composed with `expand` in a `toggle` method. It also allows the same pattern of not running
---the callback if the node is already collapsed
---@async
---@param callback fun(node: Node)
function Node:collapse(callback)
  if not self.expanded then
    return
  end

  self.expanded = false
  callback(self)
end

---Toggle the expanded state of the node
---Since expanding requires searching for child nodes on the first pass, which is async,
---the entire function is written with the async pattern. The callback contains the following
---code to be run once the node's expanded state has been toggled
---@async
---@param callback fun(node: Node)
function Node:toggle(callback)
  if self.expanded then
    self:collapse(callback)
  else
    self:expand(callback)
  end
end

---@async
---@param callback fun(node: Node)
function Node:switch_direction(callback)
  local cache_root = self.cache:set_root()
  state.switch_direction()
  local uri = self.cache.location.textDocument.uri
  local lnum = self.cache.location.position.line + 1
  local col = self.cache.location.position.character + 1
  local new_root = Node.new(uri, self.text, lnum, col, cache_root)
  new_root:search(callback)
end

---@alias NodeLevel {node: Node, tree_state: boolean[]}
---@alias NodeList NodeLevel[]

---Add a node to the list reprsentation of the tree
---There is no return as the list is mutated in place.
---The mutated list is the effective return of this function
---@param list NodeList The list being built up
---@param node Node
---@param tree_state boolean[] A list of true/false flags that, for each level in indicate whether this is the last node. This information is needed for rendering the tree in the Telescope finder
local function add_node_to_list(list, node, tree_state)
  local entry = {
    node = node,
    tree_state = tree_state,
  }
  table.insert(list, entry)
  if node.expanded and #node.children > 0 then
    for idx, child in ipairs(node.children) do
      local last_child = idx == #node.children
      local new_state = { unpack(tree_state) }
      table.insert(new_state, last_child)
      add_node_to_list(list, child, new_state)
    end
  end
end

---Convert a tree of nodes into a list representation
---This is needed for Telescope which only works with lists. We retain a memory of the nestedness
---through the level field of the inner table
---@param from_root? boolean Optional flag to render from the node's root, if missing will assume the root is wanted
---@return NodeList
function Node:to_list(from_root)
  ---@type NodeList
  local results = {}
  local render_root = (from_root == nil or from_root) and self.root or self
  add_node_to_list(results, render_root, {})
  return results
end

return Node
