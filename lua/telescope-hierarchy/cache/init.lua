local state = require("telescope-hierarchy.state")

Cache = {}

---Initialise the cache in the global state
function Cache.init()
  state.set("cache", {})
end

---Get the cache from the global state
---@return CacheEntry[] | nil entries
local function get_cache()
  local entries = state.get("cache")
  if not entries then
    vim.notify("Must initialise the cache first", vim.log.levels.ERROR)
    return
  end
  return entries
end

---Adds a location to the cache if not already included
---Either way the function will return the reference to
---the cache entry
---@param entry CacheEntry
---@return CacheEntry
function Cache.add(entry)
  local in_cache = Cache.get(entry.location)
  if in_cache then
    return in_cache
  end
  local cache = assert(get_cache())
  table.insert(cache, entry)
  return entry
end

---Determines if a given location is already in the cache
---@param location lsp.TextDocumentPositionParams
---@return CacheEntry | nil
function Cache.get(location)
  local cache = assert(get_cache())
  for _, entry in ipairs(cache) do
    if entry:is_at(location) then
      return entry
    end
  end
  return nil
end

return Cache
