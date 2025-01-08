local tree = require("telescope-hierarchy.tree")
local ui = require("telescope-hierarchy.telescope-ui")

local M = {}

M.incoming_calls = function(opts)
  tree.new("Call", "Incoming", function(root)
    ui.show(root:to_list(false), opts)
  end)
end

M.outgoing_calls = function(opts)
  tree.new("Call", "Outgoing", function(root)
    ui.show(root:to_list(false), opts)
  end)
end

return M
