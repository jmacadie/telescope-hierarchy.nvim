std = "luajit"
read_globals = {
  vim = {
    other_fields = true,
    fields = { opt = { other_fields = true, read_only = false } },
  },
}
-- This is the plugin's existing shared state, not a blanket allowance for globals.
globals = { "THGlobalState" }
-- Formatting and comment width are handled separately from correctness linting.
max_line_length = false

files["tests/spec/**/*.lua"] = {
  -- Tests may temporarily replace Neovim's notification transport.
  globals = { "vim.notify" },
}
