---@class Mode
---@field val string
local Mode = {}
Mode.__index = Mode

Mode.__eq = function(a, b)
  return a.val == b.val
end

function Mode:is_call()
  return self.val == "call"
end

---@param val string
---@return Mode
local function set_enum(val)
  local inner = {
    val = val,
  }
  setmetatable(inner, Mode)
  return inner
end

local mode = {
  CALL = set_enum("call"),
  TYPE = set_enum("type"),
}

return mode
