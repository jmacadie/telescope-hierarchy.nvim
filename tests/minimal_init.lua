-- No user config, plugin manager, installed parsers, or live language servers.
local root = vim.fn.getcwd()
vim.opt.runtimepath = {
  root,
  root .. "/.deps/mini.test",
  root .. "/.deps/plenary.nvim",
  root .. "/.deps/telescope.nvim",
  vim.env.VIMRUNTIME,
}
vim.opt.loadplugins = false
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.packpath = ""
-- Plenary's Lua modules remain available, but its test runner is not loaded.
