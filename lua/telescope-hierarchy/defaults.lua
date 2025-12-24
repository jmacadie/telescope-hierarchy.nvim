local actions = require("telescope-hierarchy.actions")

local M = {}

M.opts = {
  initial_multi_expand = false,
  multi_depth = 5,
  multi_depth_reference_fallback = 2,
  enable_reference_fallback = false,
  mappings = {
    i = {},
    n = {
      ["e"] = actions.expand,
      ["E"] = actions.multi_expand,
      ["l"] = actions.expand,
      ["<RIGHT>"] = actions.expand,

      ["c"] = actions.collapse,
      ["h"] = actions.collapse,
      ["<LEFT>"] = actions.collapse,

      ["t"] = actions.toggle,
      ["s"] = actions.switch,
      ["d"] = actions.goto_definition,

      ["q"] = actions.quit,
    },
  },
  layout_strategy = "horizontal",
}

return M
