-- Collection errors must fail the gate too, rather than leave headless Neovim open.
local ok, err = xpcall(function()
  local test = require("mini.test")
  test.setup({
    collect = {
      emulate_busted = false,
      find_files = function()
        return vim.fn.globpath("tests/spec", "**/*_spec.lua", true, true)
      end,
    },
  })
  local cases = test.collect()
  assert(#cases > 0, "No test cases found in tests/spec")
  -- The stdout reporter exits Neovim with a non-zero status if any case fails.
  test.execute(cases, { reporter = test.gen_reporter.stdout({ quit_on_finish = true }) })
end, debug.traceback)

if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd("cquit 1")
end
