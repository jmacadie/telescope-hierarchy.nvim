local tree = require("telescope-hierarchy.tree")
local ui = require("telescope-hierarchy.ui")
local call = require("telescope-hierarchy.enums.call")
local type = require("telescope-hierarchy.enums.type")
local mode = require("telescope-hierarchy.enums.mode")

local M = {}

M.incoming_calls = function(opts)
  tree.new(mode.CALL, call.INCOMING, function(root)
    ui.show(root:to_list(false), opts)
  end)
end

M.outgoing_calls = function(opts)
  tree.new(mode.CALL, call.OUTGOING, function(root)
    ui.show(root:to_list(false), opts)
  end)
end

M.supertypes = function(opts)
  tree.new(mode.TYPE, type.SUPER, function(root)
    ui.show(root:to_list(false), opts)
  end)
end

M.subtypes = function(opts)
  tree.new(mode.TYPE, type.SUB, function(root)
    ui.show(root:to_list(false), opts)
  end)
end

return M
