---@class Direction
---@field val string
local Direction = {}
Direction.__index = Direction

Direction.__eq = function(a, b)
  return a.val == b.val
end

function Direction:is_incoming()
  return self.val == "incoming"
end

---@param val string
---@return Direction
local function set_enum(val)
  local inner = {
    val = val,
  }
  setmetatable(inner, Direction)
  return inner
end

---Switch direction. Will convert INCOMING to OUTGOING and vice versa
---@return Direction
function Direction:switch()
  if self.val == "incoming" then
    return set_enum("outgoing")
  end
  return set_enum("incoming")
end

local direction = {
  INCOMING = set_enum("incoming"),
  OUTGOING = set_enum("outgoing"),
}

return direction
