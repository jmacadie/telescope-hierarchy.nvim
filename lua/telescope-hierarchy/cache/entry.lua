local state = require("telescope-hierarchy.state")
local lsp = require("telescope-hierarchy.lsp")
local cache = require("telescope-hierarchy.cache")

---@class CacheEntry
---@field location lsp.TextDocumentPositionParams
---@field name string
---@field searched "Yes" | "No" | "Pending"
---@field searched_node Node | nil
---@field children CacheEntry[]
---@field callbacks fun()[]
CacheEntry = {}
CacheEntry.__index = CacheEntry

---Create a new entry for the cache
---It is not added to the cache though
---@param name string
---@param location lsp.TextDocumentPositionParams
---@return CacheEntry
local function create_new(name, location)
  local obj = {
    location = location,
    name = name,
    searched = "No",
    searched_node = nil,
    children = {},
    callbacks = {},
  }
  setmetatable(obj, CacheEntry)
  return obj
end

---Extract the position params from a call heirarchy item
---@param item lsp.CallHierarchyItem
---@return lsp.TextDocumentPositionParams
local function to_position_params(item)
  return {
    textDocument = {
      uri = item.uri,
    },
    position = item.selectionRange.start,
  }
end

---Find the children of this entry. This always makes a call to the LSP and so should
---be guarded by a check that the entry has not yet been searched
---@async
---@param each_cb fun(call: lsp.CallHierarchyIncomingCall | lsp.CallHierarchyOutgoingCall, entry: CacheEntry)
---@param final_cb fun(pending: boolean | nil)
function CacheEntry:find_children(each_cb, final_cb)
  assert(self.searched == "No")
  self.searched = "Pending"
  local direction = assert(state.direction())

  ---@param calls lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]
  local add = function(calls)
    for _, call in ipairs(calls) do
      local inner = direction:is_incoming() and call.from or call.to
      local location = to_position_params(inner)
      local child_entry = cache.get(location)
      if not child_entry then
        child_entry = create_new(inner.name, location)
        cache.add(child_entry)
      end
      table.insert(self.children, child_entry)
      each_cb(call, child_entry)
    end
  end

  local final = function()
    self.searched = "Yes"
    final_cb()

    -- Process any callbacks that got added while the LSP request was pending
    ---@type fun() | nil
    local process_pending = table.remove(self.callbacks)
    while process_pending do
      process_pending()
      ---@type fun() | nil
      process_pending = table.remove(self.callbacks)
    end
  end

  lsp.get_calls(self.location, add, final)
  -- Pass true as this cb is only ever to trigger the refresh of the UI
  -- tree and never to run any processing that is intended for once the
  -- children have been async resolved by the LSP
  final_cb(true)
end

---Determine if this cache entry has the same location
---@param location lsp.TextDocumentPositionParams
---@return boolean
function CacheEntry:is_at(location)
  return self.location.position.character == location.position.character
    and self.location.position.line == location.position.line
    and self.location.textDocument.uri == location.textDocument.uri
end

---Wipe the cache, create a root entry and add it as the root entry
---@param name string
---@param location lsp.TextDocumentPositionParams
---@return CacheEntry
function CacheEntry.add_root(name, location)
  cache.init()
  local root = create_new(name, location)
  return cache.add(root)
end

---Clone the current cache entry & set it as the only entry in a reset cache
---@return CacheEntry
function CacheEntry:set_root()
  return self.add_root(self.name, self.location)
end

return CacheEntry
