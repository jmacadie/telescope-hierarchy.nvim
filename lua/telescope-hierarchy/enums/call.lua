---@class CallDirection
---@field val string
local CallDirection = {}
CallDirection.__index = CallDirection

CallDirection.__eq = function(a, b)
  return a.val == b.val
end

function CallDirection:is_incoming()
  return self.val == "incoming"
end

---@param val string
---@return CallDirection
local function set_enum(val)
  local inner = {
    val = val,
  }
  setmetatable(inner, CallDirection)
  return inner
end

---Switch direction. Will convert INCOMING to OUTGOING and vice versa
---@return CallDirection
function CallDirection:switch()
  if self.val == "incoming" then
    return set_enum("outgoing")
  end
  return set_enum("incoming")
end

local direction = {
  INCOMING = set_enum("incoming"),
  OUTGOING = set_enum("outgoing"),
}

-- ---@enum Direction
-- local direction = {
--   INCOMING = 1,
--   OUTGOING = 2,
-- }

return direction
