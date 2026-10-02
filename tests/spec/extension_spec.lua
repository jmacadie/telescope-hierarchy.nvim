local test = require("mini.test")
local eq = test.expect.equality
local state = require("telescope-hierarchy.state")
local direction = require("telescope-hierarchy.enums.direction")
local mode = require("telescope-hierarchy.enums.mode")

local saved_state
local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
    end,
    post_case = function()
      THGlobalState = saved_state
    end,
  },
})

T["loads through Telescope and exposes the public commands"] = function()
  local telescope = require("telescope")
  telescope.setup({ extensions = { hierarchy = { multi_depth = 3 } } })
  telescope.load_extension("hierarchy")
  eq(type(telescope.extensions.hierarchy.hierarchy), "function")
  eq(type(telescope.extensions.hierarchy.incoming_calls), "function")
  eq(type(telescope.extensions.hierarchy.outgoing_calls), "function")
  eq(state.get("multi_depth"), 3)
end

T["switches direction without changing the original enum"] = function()
  state.set("direction", direction.INCOMING)
  state.switch_direction()
  eq(state.direction(), direction.OUTGOING)
  eq(direction.INCOMING:is_incoming(), true)
  state.switch_direction()
  eq(state.direction(), direction.INCOMING)
  eq(mode.CALL:is_call(), true)
  eq(mode.TYPE:is_call(), false)
end

T["uses the direction in the picker title"] = function()
  local ui = require("telescope-hierarchy.ui")
  state.set("direction", direction.INCOMING)
  eq(ui.title(), "Incoming Calls")
  state.switch_direction()
  eq(ui.title(), "Outgoing Calls")
  eq(ui.show({}, {}), nil)
end

return T
