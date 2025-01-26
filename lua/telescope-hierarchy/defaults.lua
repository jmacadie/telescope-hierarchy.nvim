local actions = require("telescope-hierarchy.actions")

local M = {}

M.opts = {
  mappings = {
    i = {},
    n = {
      ["e"] = actions.expand,
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
