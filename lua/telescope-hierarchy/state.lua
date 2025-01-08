THGlobalState = THGlobalState or {}

local state = {}
state.__index = state

---Set a key in the global state to a value
---@param key string
---@param value any
function state.set(key, value)
  THGlobalState[key] = value
end

---Retrieve a value from the global state
---@param key string
---@return any | nil
function state.get(key)
  return THGlobalState[key]
end

---Switch the direction in which the lsp looks for the call hierarchy
---Outgoing <--> Incoming
function state.switch_direction()
  local direction = state.get("direction")
  if not direction then
    return
  end
  state.set("direction", direction:switch())
end

---Retrieve the direction from global state
---@return CallDirection | TypeDirection | nil direction Is the plugin working in call or type hierarchy mode?
function state.direction()
  local direction = state.get("direction")
  if not direction then
    vim.notify("Must initialise the direction first", vim.log.levels.ERROR)
    return
  end
  return direction
end

---Retrieve the mode from global state
---@return Mode | nil mode Is the plugin working in type or call hierarchy mode?
function state.mode()
  local mode = state.get("mode")
  if not mode then
    vim.notify("Must initialise the mode first", vim.log.levels.ERROR)
    return
  end
  return mode
end

return state
