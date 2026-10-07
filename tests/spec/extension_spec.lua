local test = require("mini.test")
local eq = test.expect.equality
local state = require("telescope-hierarchy.state")
local direction = require("telescope-hierarchy.enums.direction")
local mode = require("telescope-hierarchy.enums.mode")

local saved_state, originals, extension
local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
      extension = require("telescope._extensions.hierarchy")
      local hierarchy = require("telescope-hierarchy")
      originals =
        { incoming = hierarchy.incoming_calls, outgoing = hierarchy.outgoing_calls, config = extension.config }
    end,
    post_case = function()
      local hierarchy = require("telescope-hierarchy")
      hierarchy.incoming_calls = originals.incoming
      hierarchy.outgoing_calls = originals.outgoing
      extension.config = originals.config
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

T["selects expansion depth from the active backend rather than fallback eligibility"] = function()
  state.set("multi_depth", 5)
  state.set("multi_depth_reference_fallback", 2)
  state.set("enable_reference_fallback", true)
  eq(state.multi_depth(), 5)
  state.set("using_fallback", false)
  eq(state.multi_depth(), 5)
  state.set("using_fallback", true)
  eq(state.multi_depth(), 2)
  state.set("multi_depth_reference_fallback", 3)
  eq(state.multi_depth(), 3)
  state.set("using_fallback", false)
  eq(state.multi_depth(), 5)
end

T["uses the direction in the picker title"] = function()
  local ui = require("telescope-hierarchy.ui")
  state.set("direction", direction.INCOMING)
  eq(ui.title(), "Incoming Calls")
  state.switch_direction()
  eq(ui.title(), "Outgoing Calls")
  eq(ui.show({}, {}), nil)
end

for _, command in ipairs({ "hierarchy", "incoming_calls", "outgoing_calls" }) do
  for _, reset in ipairs({ { name = "nil" }, { name = "empty", config = {} } }) do
    T[command .. " restores setup settings after overrides followed by " .. reset.name .. " options"] = function()
      local setup = { enable_reference_fallback = false, multi_depth = 4, multi_depth_reference_fallback = 2 }
      extension.setup(setup)
      local baseline = vim.deepcopy(extension.config)
      local invocations = {}
      local function capture(opts)
        invocations[#invocations + 1] = {
          opts = vim.deepcopy(opts),
          fallback = state.get("enable_reference_fallback"),
          depth = state.get("multi_depth"),
          fallback_depth = state.get("multi_depth_reference_fallback"),
        }
      end
      local hierarchy = require("telescope-hierarchy")
      hierarchy.incoming_calls, hierarchy.outgoing_calls = capture, capture
      local overrides = { enable_reference_fallback = true, multi_depth = 9, multi_depth_reference_fallback = 7 }
      extension.exports[command](overrides)
      eq(invocations[1].fallback, true)
      eq(invocations[1].depth, 9)
      eq(invocations[1].fallback_depth, 7)
      eq(invocations[1].opts.enable_reference_fallback, true)
      eq(invocations[1].opts.multi_depth, 9)
      eq(invocations[1].opts.multi_depth_reference_fallback, 7)
      extension.exports[command](reset.config)
      eq(invocations[2].fallback, false)
      eq(invocations[2].depth, 4)
      eq(invocations[2].fallback_depth, 2)
      eq(invocations[2].opts, baseline)
      eq(extension.config, baseline)
      eq(setup, { enable_reference_fallback = false, multi_depth = 4, multi_depth_reference_fallback = 2 })
      eq(overrides, { enable_reference_fallback = true, multi_depth = 9, multi_depth_reference_fallback = 7 })
    end
  end
end

return T
