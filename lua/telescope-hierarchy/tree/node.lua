--- Holds reference to a function location in the codebase that represents
--- a part of the call hierarchy
---@class Node
---@field text string: The display name of the node
---@field filename string: The filename that contains this node
---@field lnum integer: The (l-based) line number of the reference
---@field col integer: The (1-based) column number of the reference
---@field search_loc lsp.TextDocumentPositionParams: The location in the code to recursively search from
---@field searched boolean: Has this node been searched yet? Searches are expensive so use this flag to only search once
---@field expanded boolean: Is the node expanded in the current representation of the heirarchy tree
---@field root Node: The root of the tree this node is in
---@field children Node[]: A list of the children of this node
---@field directon string: Are we running incoming or outgoing calls?
---@field lsp LSP: Reference to the module for running calls to the LSP
Node = {}
Node.__index = Node

--- Create a new (unattached) node
---@param uri string: The URI representation of the filename where the node is found
---@param text string: The display name of the node
---@param lnum integer: The (l-based) line number of the reference
---@param col integer: The (1-based) column number of the reference
---@param search_loc lsp.TextDocumentPositionParams: The location in the code to recursively search from
---@param directon string: Are we running incoming or outgoing calls?
---@param lsp_ref LSP
---@return Node
function Node.new(uri, text, lnum, col, search_loc, directon, lsp_ref)
  local node = {
    filename = vim.uri_to_fname(uri),
    text = text,
    lnum = lnum,
    col = col,
    search_loc = search_loc,
    searched = false,
    expanded = false,
    children = {},
    directon = directon,
    lsp = lsp_ref,
  }
  -- We need to have a reference to a "root" node to make a valid node
  -- For an unattached node, this will be a self reference
  -- It gets over-written in `add_children`
  node.root = node
  setmetatable(node, Node)
  return node
end

---Process the list of child calls (either incoming or outgoing depending on direction),
---adding each to the current node's children table
---@param calls lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]
function Node:add_children(calls)
  for _, call in ipairs(calls) do
    local inner = self.directon == "Incoming" and call.from or call.to
    for _, range in ipairs(call.fromRanges) do
      local loc = {
        textDocument = {
          uri = inner.uri,
        },
        position = inner.selectionRange.start,
      }
      local child =
        Node.new(inner.uri, inner.name, range.start.line + 1, range.start.character, loc, self.directon, self.lsp)
      child.root = self.root -- maintain a common root node
      table.insert(self.children, child)
    end
  end
end

---Search the current node
---It will do nothing if the current node has already been searched
---@param expand boolean Expand the node after searching?
---@param callback fun() Function to be run once all children have been processed
function Node:search(expand, callback)
  if self.searched then
    -- TODO: Maybe should error as this is not an expected state
    return
  end
  local add_cb = function(calls)
    self:add_children(calls)
  end
  local final_cb = function()
    self.expanded = expand
    self.searched = true
    callback()
  end
  self.lsp:get_calls(self.search_loc, self.directon, add_cb, final_cb)
end

---Expand the node, searching for children if not already done
---The callback will not be called if the node is already expanded
---@param callback fun() Function to be run once children have been found (async) & the node expanded
function Node:expand(callback)
  if not self.expanded then
    if self.searched then
      self.expanded = true
      callback()
    else
      self:search(true, callback)
    end
  end
end

---Collapse the node.
---This function is not actually async but it makes sense to write it this way so it can be
---composed with `expand` in a `toggle` method. It also allows the same pattern of not running
---the callback if the node is already collapsed
---@param callback fun()
function Node:collapse(callback)
  if self.expanded then
    self.expanded = false
    callback()
  end
end

---Toggle the expanded state of the node
---Since expanding requires searching for child nodes on the first pass, which is async,
---the entire function is written with the async pattern. The callback contains the following
---code to be run once the node's expanded state has been toggled
---@param callback fun()
function Node:toggle(callback)
  if self.expanded then
    self:collapse(callback)
  else
    self:expand(callback)
  end
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
      -- Despite the lua ls deprecation warning, Neovim is not running a recent
      -- enough version of LuaJIT (>5.1) and so the call to `table.unpack` will
      -- fail and we need to use the old `unpack` for now
      -- local new_state = { table.unpack(tree_state) }
      ---@diagnostic disable-next-line:deprecated
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
