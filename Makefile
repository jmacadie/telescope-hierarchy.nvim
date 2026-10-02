NVIM ?= nvim
STYLUA ?= stylua
LUACHECK ?= luacheck

# Pin the test runtime so local development and CI use the same dependencies.
MINITEST_REV := 3cc4c29be99531b3fc4fb99f3fa964b492166728
# Plenary is still required by the plugin and Telescope, not by the test runner.
PLENARY_REV := 74b06c6c75e4eeb3108ec01852001636d85a932b
TELESCOPE_REV := a0bbec21143c7bc5f8bb02e0005fa0b982edc026

.PHONY: check lint format-check format test deps

# Recursive makes deliberately run sequentially, even with make -j.
check:
	$(MAKE) lint
	$(MAKE) format-check
	$(MAKE) test

lint:
	$(LUACHECK) lua tests/minimal_init.lua tests/run.lua tests/spec

format-check:
	$(STYLUA) --check lua tests/minimal_init.lua tests/run.lua tests/spec

format:
	$(STYLUA) lua tests/minimal_init.lua tests/run.lua tests/spec

test: deps
	$(NVIM) --headless -u tests/minimal_init.lua -i NONE -n -c "lua dofile('tests/run.lua')"

deps: .deps/mini.test/$(MINITEST_REV) .deps/plenary.nvim/$(PLENARY_REV) .deps/telescope.nvim/$(TELESCOPE_REV)

.deps/mini.test/$(MINITEST_REV):
	mkdir -p .deps/mini.test
	git -C .deps/mini.test init -q
	git -C .deps/mini.test fetch --depth 1 https://github.com/nvim-mini/mini.test $(MINITEST_REV)
	git -C .deps/mini.test checkout --detach FETCH_HEAD
	touch $@

.deps/plenary.nvim/$(PLENARY_REV):
	mkdir -p .deps/plenary.nvim
	git -C .deps/plenary.nvim init -q
	git -C .deps/plenary.nvim fetch --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_REV)
	git -C .deps/plenary.nvim checkout --detach FETCH_HEAD
	touch $@

.deps/telescope.nvim/$(TELESCOPE_REV):
	mkdir -p .deps/telescope.nvim
	git -C .deps/telescope.nvim init -q
	git -C .deps/telescope.nvim fetch --depth 1 https://github.com/nvim-telescope/telescope.nvim $(TELESCOPE_REV)
	git -C .deps/telescope.nvim checkout --detach FETCH_HEAD
	touch $@
