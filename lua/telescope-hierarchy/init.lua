local tree = require("telescope-hierarchy.tree")
local ui = require("telescope-hierarchy.ui")
local direction = require("telescope-hierarchy.enums.direction")

local M = {}

M.incoming_calls = function(opts)
  tree.new("Call", direction.INCOMING, function(root)
    ui.show(root:to_list(false), opts)
  end)
end

M.outgoing_calls = function(opts)
  tree.new("Call", direction.OUTGOING, function(root)
    ui.show(root:to_list(false), opts)
  end)
end

return M
