local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("telescope-hierarchy.nvim requires telescope.nvim - https://github.com/nvim-telescope/telescope.nvim")
end

local hierarchy = require("telescope-hierarchy")
local defaults = require("telescope-hierarchy.defaults")

local function extend_config(base, extend)
  local config = vim.tbl_deep_extend("force", base, extend)

  -- remove default keymaps that have been disabled by the user
  for _, mode in ipairs({ "i", "n" }) do
    config.mappings[mode] = vim.tbl_map(function(val)
      return val ~= false and val or nil
    end, config.mappings[mode])
  end

  -- expand theme configs
  if config.theme then
    config = require("telescope.themes")["get_" .. config.theme](config)
  end
  return config
end

local M = {
  exports = {},
}

local function final_config(config)
  -- skip reevaluation of extend_config if we're updating with an empty table
  if config == nil or next(config) == nil then
    return M.config
  else
    return extend_config(M.config, config)
  end
end

M.exports.incoming_calls = function(config)
  hierarchy.incoming_calls(final_config(config))
end

M.exports.outgoing_calls = function(config)
  hierarchy.outgoing_calls(final_config(config))
end

M.setup = function(extension_config, _)
  M.config = extend_config(defaults.opts, extension_config)
end

return telescope.register_extension(M)
