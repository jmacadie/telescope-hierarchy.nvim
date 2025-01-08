local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("telescope-hierarchy.nvim requires telescope.nvim - https://github.com/nvim-telescope/telescope.nvim")
end

local hierarchy = require("telescope-hierarchy")
local defaults = require("telescope-hierarchy.defaults")
local state = require("telescope-hierarchy.state")

local function extend_config(base, extend)
  local config = vim.tbl_deep_extend("force", base, extend)

  -- set multi expansion depth in the global state
  state.set("multi_depth", config.multi_depth)

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

M.exports.hierarchy = function(config)
  hierarchy.incoming_calls(final_config(config))
end

M.exports.incoming_calls = function(config)
  hierarchy.incoming_calls(final_config(config))
end

M.exports.outgoing_calls = function(config)
  hierarchy.outgoing_calls(final_config(config))
end

M.exports.supertypes = function(config)
  hierarchy.supertypes(final_config(config))
end

M.exports.subtypes = function(config)
  hierarchy.subtypes(final_config(config))
end

M.setup = function(extension_config, _)
  M.config = extend_config(defaults.opts, extension_config)
end

local function check_version()
  local version = vim.version()

  -- Minimum required version
  local min_major = 0
  local min_minor = 10

  if version.major < min_major or (version.major == min_major and version.minor < min_minor) then
    vim.notify(
      string.format(
        "This plugin requires Neovim v%d.%d.0 or greater. Current version: v%d.%d.%d",
        min_major,
        min_minor,
        version.major,
        version.minor,
        version.patch
      ),
      vim.log.levels.ERROR
    )
    return false
  end

  return true
end

if check_version() then
  return telescope.register_extension(M)
end
