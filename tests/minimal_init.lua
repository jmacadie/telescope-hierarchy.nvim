-- No user config, plugin manager, personal parsers, or live language servers.
local root = vim.fn.getcwd()
vim.opt.runtimepath = {
  root,
  root .. "/.deps/mini.test",
  root .. "/.deps/plenary.nvim",
  root .. "/.deps/telescope.nvim",
  root .. "/.deps/lua-parser",
  vim.env.VIMRUNTIME,
}
vim.opt.loadplugins = false
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.packpath = ""
-- Parser tests should not start runtime highlighting or depend on bundled queries.
vim.cmd("filetype plugin indent off")
-- Plenary's Lua modules remain available, but its test runner is not loaded.
