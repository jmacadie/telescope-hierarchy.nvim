---@class TypeDirection
---@field val string
local TypeDirection = {}
TypeDirection.__index = TypeDirection

TypeDirection.__eq = function(a, b)
  return a.val == b.val
end

function TypeDirection:is_super()
  return self.val == "super"
end

---@param val string
---@return TypeDirection
local function set_enum(val)
  local inner = {
    val = val,
  }
  setmetatable(inner, TypeDirection)
  return inner
end

---Switch direction. Will convert INCOMING to OUTGOING and vice versa
---@return TypeDirection
function TypeDirection:switch()
  if self.val == "super" then
    return set_enum("sub")
  end
  return set_enum("super")
end

local direction = {
  SUPER = set_enum("super"),
  SUB = set_enum("sub"),
}

return direction
