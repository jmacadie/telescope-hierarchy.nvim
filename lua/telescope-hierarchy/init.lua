local tree = require("telescope-hierarchy.tree")
local ui = require("telescope-hierarchy.ui")
local call = require("telescope-hierarchy.enums.call")
local type = require("telescope-hierarchy.enums.type")
local mode = require("telescope-hierarchy.enums.mode")
local state = require("telescope-hierarchy.state")

local M = {}

M.incoming_calls = function(opts)
  tree.new(mode.CALL, call.INCOMING, function(root)
    local p = ui.show(root:to_list(false), opts)
    if p and opts.initial_multi_expand then
      local depth = state.get("multi_depth")
      root:multi_expand(depth, function(expanded_tree)
        ui.refresh(expanded_tree, p)
      end)
    end
  end)
end

M.outgoing_calls = function(opts)
  tree.new(mode.CALL, call.OUTGOING, function(root)
    local p = ui.show(root:to_list(false), opts)
    if p and opts.initial_multi_expand then
      local depth = state.get("multi_depth")
      root:multi_expand(depth, function(expanded_tree)
        ui.refresh(expanded_tree, p)
      end)
    end
  end)
end

M.supertypes = function(opts)
  tree.new(mode.TYPE, type.SUPER, function(root)
    local p = ui.show(root:to_list(false), opts)
    if p and opts.initial_multi_expand then
      local depth = state.get("multi_depth")
      root:multi_expand(depth, function(expanded_tree)
        ui.refresh(expanded_tree, p)
      end)
    end
  end)
end

M.subtypes = function(opts)
  tree.new(mode.TYPE, type.SUB, function(root)
    local p = ui.show(root:to_list(false), opts)
    if p and opts.initial_multi_expand then
      local depth = state.get("multi_depth")
      root:multi_expand(depth, function(expanded_tree)
        ui.refresh(expanded_tree, p)
      end)
    end
  end)
end

return M
