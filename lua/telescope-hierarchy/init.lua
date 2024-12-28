local tree = require("telescope-hierarchy.tree")
local ui = require("telescope-hierarchy.telescope-ui")

local M = {}

M.show = function(opts)
  tree.new(function(root)
    ui.show_hierarchy(root:to_list(false), opts)
  end)
end

return M
