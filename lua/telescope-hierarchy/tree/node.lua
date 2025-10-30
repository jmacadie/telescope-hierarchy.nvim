local state = require("telescope-hierarchy.state")
local lsp = require("telescope-hierarchy.lsp")
local Path = require("plenary.path")

--- Return the buffer assiciated to a uri if the buffer exists, creates it otherwise
---@param uri string The URI representation of the filename where the node is found
---@return integer
local function get_bufnr_from_uri(uri)
  local filename = vim.uri_to_fname(uri)
  filename = Path:new(filename):normalize(vim.uv.cwd())
  pcall(function()
    vim.cmd(string.format("bufadd %s", vim.fn.fnameescape(filename)))
  end)
  local bufnr = vim.fn.bufnr(vim.fn.fnameescape(filename), true)
  vim.fn.bufload(bufnr)
  return bufnr
end

--- Return the calling function name and position
---@param location table The position from where we want to find the caller
---@return table | nil The name of the caller and its position
local function get_outer_function_info_from_c_file(location)
  -- Load buf if not already loaded
  local bufnr = get_bufnr_from_uri(location.uri)

  -- Now that the buffer is loaded, get the parser for that buffer
  local parser = vim.treesitter.get_parser(bufnr)
  local tree = parser:parse()
  local root = tree[1]:root()

  -- Get the start and end lines and columns from the range
  local start_line = location.range.start.line
  local start_char = location.range.start.character
  local end_line = location.range["end"].line
  local end_char = location.range["end"].character

  -- Find the node at the specified range
  local node_at_location = root:named_descendant_for_range(start_line, start_char, end_line, end_char)

  -- The best way to understand how a file is parsed is to open the treesitter tree with :InspectTree
  while node_at_location do
    -- We go up the tree until we find the node corresponding to the function definition
    -- find("function_definition") will find anything that contains the string "function_definition"
    -- so it will also work (maybe more robust?) if we used find("function")
    if node_at_location:type():find("function_definition") or node_at_location:type():find("declaration") then
      -- now that we found the "function definition" node, we need to parse its sub node to find
      -- the node function_declarator
      for child, _ in node_at_location:iter_children() do
        if child:type():find("function_declarator") or child:type():find("init_declarator") then
          -- and now we want to isolate the node corresponding to the function name
          for sub_child, _ in child:iter_children() do
            local node_type = sub_child:type()
            if
              node_type:match("identifier")
              or node_type:match("func")
              or node_type:match("function")
              or node_type:match("method")
              or node_type:match("declaration")
            then
              local function_name = vim.treesitter.get_node_text(sub_child, bufnr)
              local line, col, _, _ = sub_child:range()
              return {
                function_name = function_name,
                position = {
                  line = line,
                  character = col,
                },
              }
            end
          end
        end
      end
      break
    end
    node_at_location = node_at_location:parent()
  end

  return nil
end

--- Return the references assiciated to the symbol
---@sync
---@param symbol_info table The position of the symbol we want to search
---@param client table The lsp client
---@return table | nil The references found
local function find_references_for_symbol(symbol_info, client)
  local timeout_ms = 1000
  local bufnr = get_bufnr_from_uri(symbol_info.location.textDocument.uri)
  return client.request_sync("textDocument/references", symbol_info.location, timeout_ms, bufnr)
end

--- Holds reference to a function location in the codebase that represents
--- a part of the call hierarchy
---@class Node
---@field text string The display name of the node
---@field filename string The filename that contains this node
---@field lnum integer The (l-based) line number of the reference
---@field col integer The (1-based) column number of the reference
---@field expanded boolean Is the node expanded in the current representation of the heirarchy tree
---@field recursive boolean Is this node recursive? Will be true if the same node exists in the parent chain
---@field cache CacheEntry The cached information about the function location, so we only find a function once
---@field root Node The root of the tree this node is in
---@field parent Node | nil The parent node of this node
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
    recursive = false,
    cache = cache,
    parent = nil,
    children = {},
  }
  -- We need to have a reference to a "root" node to make a valid node
  -- For an unattached node, this will be a self reference
  -- It gets over-written in `new_child`
  node.root = node
  setmetatable(node, Node)
  return node
end

---Work out if a cache entry is recursive, given a parent
---Will recursively call this function going up the parent chain until
---either a cache match is found or we reach the root (which has a nil
---parent)
---@param cache CacheEntry
---@param parent Node | nil
---@return boolean
local function is_recursive(cache, parent)
  if not parent then
    return false
  end

  if parent.cache == cache then
    return true
  end

  return is_recursive(cache, parent.parent)
end

--- Create a new node that is a child of the current node
---@param uri string The URI representation of the filename where the node is found
---@param text string The display name of the node
---@param lnum integer The (l-based) line number of the reference
---@param col integer The (1-based) column number of the reference
---@param cache CacheEntry
function Node:new_child(uri, text, lnum, col, cache)
  local child = Node.new(uri, text, lnum, col, cache)
  child.root = self.root
  child.parent = self
  child.recursive = is_recursive(cache, self)
  table.insert(self.children, child)
end

---Clone this node to create a copy, that can be put elsewhere in the user tree
---@return Node
function Node:clone()
  local direction = assert(state.direction())
  local uri = ""
  if direction:is_incoming() then
    uri = self.cache.location.textDocument.uri
  else
    uri = vim.uri_from_fname(self.filename)
  end

  local clone = Node.new(uri, self.text, self.lnum, self.col, self.cache)
  clone.root = self.root
  return clone
end

---Search the current node
---It will do nothing if the current node has already been searched
---@async
---@param callback fun(node: Node, pending: boolean | nil) Function to be run once all children have been processed
function Node:search(callback)
  assert(self.cache.searched == "No")
  local direction = assert(state.direction())

  ---@param call lsp.CallHierarchyIncomingCall | lsp.CallHierarchyOutgoingCall
  ---@param entry CacheEntry
  local each_cb = function(call, entry)
    local last_line = -1
    local last_char = -1
    local inner
    local uri
    if direction:is_incoming() then
      inner = call.from
      uri = inner.uri
    else
      inner = call.to
      uri = self.cache.location.textDocument.uri
    end

    -- Clangd has a known bug/limitation where a 'call Hierarchy incoming call' can't find the correct file when similar functions are implemented in different files
    -- Emperically, (tested on clangd 20.1.8 and clangd 21.1.0, aka the first versions to release lsp outgoing call),
    -- we know the server returned the wrong file when the field "range" from the server response is empty.
    -- We find the correct location via a call to lsp textDocument/references instead (as this seems to consistently returns the correct references)
    -- and use treesitter to get the name and position of its caller
    local client, _ = assert(lsp.get_state())
    if
      direction:is_incoming()
      and client.name == "clangd"
      and #call.fromRanges == 0
      and inner.name ~= ""
      and uri ~= ""
    then
      local parent_node_symbol_info = {
        location = {
          position = {
            character = self.cache.location.position.character,
            line = self.cache.location.position.line,
          },
          textDocument = {
            uri = self.cache.location.textDocument.uri,
          },
        },
        symbol_name = self.cache.name,
      }

      local references = find_references_for_symbol(parent_node_symbol_info, client)
      if references then
        for _, ref in pairs(references.result) do
          local outter_func = get_outer_function_info_from_c_file(ref)
          if outter_func and outter_func.function_name == inner.name then
            local wrong_uri = uri
            -- Update the cache with the correct information
            for _, child in pairs(self.cache.children) do
              -- if the cache contains a reference to the correct function but not from the correct file
              if child.location.textDocument.uri == wrong_uri and child.name == outter_func.function_name then
                child.location.position = outter_func.position
                child.location.textDocument.uri = ref.uri
              end
            end

            -- create new child with correct info
            self:new_child(
              ref.uri,
              outter_func.function_name,
              ref.range.start.line + 1,
              ref.range.start.character + 1,
              entry
            )
          end
        end
      end
    else
      for _, range in ipairs(call.fromRanges) do
        -- Check for duplicate ranges from LSP
        -- Assumes the duplicates are sequential. Would need to do more work if they are unordered
        if range.start.line ~= last_line or range.start.character ~= last_char then
          self:new_child(uri, inner.name, range.start.line + 1, range.start.character + 1, entry)
          last_line = range.start.line
          last_char = range.start.character
        end
      end
    end
  end

  ---Callback to be run once all children have been found
  ---This also triggers the refresh of the tree on the UI so it can be
  ---called in just pending mode, while we wait for the LSP to return & we just
  ---trigger the refresh part of the callback
  ---@param pending boolean | nil
  local final_cb = function(pending)
    if not pending then
      self.expanded = true
      self.cache.searched_node = self
    end
    callback(self, pending)
  end

  self.cache:find_children(each_cb, final_cb)
end

---Expand the node, searching for children if not already done
---The callback will not be called if the node is already expanded or is recursive
---@async
---@param callback fun(node: Node, pending: boolean | nil) Function to be run once children have been found (async) & the node expanded
---@param force_cb boolean | nil
function Node:expand(callback, force_cb)
  if self.expanded or self.recursive then
    if force_cb then
      callback(self)
    end
    return
  end

  if self.cache.searched == "No" then
    self:search(callback)
    return
  end

  -- Put this in a function as we might need to call this as a callback
  -- on the cache, if the search is currently pending
  local add_from_cache = function()
    if #self.children == 0 then
      local searched = assert(self.cache.searched_node)
      for _, node in ipairs(searched.children) do
        local cloned = node:clone()
        cloned.parent = self
        cloned.recursive = is_recursive(cloned.cache, self)
        table.insert(self.children, cloned)
      end
    end

    self.expanded = true
    callback(self)
  end

  if self.cache.searched == "Pending" then
    table.insert(self.cache.callbacks, add_from_cache)
    return
  end

  add_from_cache()
end

---Recursively expand the current node
---Since this could be quite expensive, it takes a depth parameter
---and will only expand to that many layers deep
---@async
---@param depth integer The depth to which to expand the current node
---@param refresh_cb fun(node: Node) A callback to trigger a repaint of the picker window
function Node:multi_expand(depth, refresh_cb)
  ---Recursive heart of this function
  ---@async
  ---@param level integer A counter for which level (counting down towards 1) we are in
  ---@param frontier Node[] A list of nodes that are to be processed at the current level
  local function process_level(level, frontier)
    ---@type Node[]
    local next = {}
    local remaining = #frontier

    ---Callback function to be run on the expanded node once the call to the LSP
    ---has resolved
    ---@async
    ---@param expanded Node
    ---@param pending boolean
    local once_expanded = function(expanded, pending)
      -- This allows us to repaint the picker window if the node is only in
      -- a pending state
      -- The early return will ensure that the remaining processing,
      -- which is intended for the node once expanded, is skipped
      if pending then
        refresh_cb(self)
        return
      end

      for _, child in ipairs(expanded.children) do
        table.insert(next, child)
      end

      remaining = remaining - 1
      if remaining == 0 then
        if level > 1 and #next > 0 then
          process_level(level - 1, next)
        else
          refresh_cb(self)
        end
      end
    end

    for _, node in ipairs(frontier) do
      -- Pass force_cb as true to ensure that even nodes that
      -- are known to have no children or be recursive trigger the callback
      -- This is necessary to ensure that the remaining counter above
      -- counts down to zero correctly and we don't hang mid-processing
      node:expand(once_expanded, true)
    end
  end

  process_level(depth, { self })
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
