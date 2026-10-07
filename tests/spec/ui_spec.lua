local test = require("mini.test")
local eq = test.expect.equality
local ui = require("telescope-hierarchy.ui")
local state = require("telescope-hierarchy.state")
local direction = require("telescope-hierarchy.enums.direction")
local Node = require("telescope-hierarchy.tree.node")
local Entry = require("telescope-hierarchy.cache.entry")
local lsp = require("telescope-hierarchy.lsp")
local pickers = require("telescope.pickers")

local saved_state, originals, picker_config, requests
local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
      state.set("direction", direction.INCOMING)
      originals = { new_picker = pickers.new, get_calls = lsp.get_calls }
      requests = 0
      -- Exercise the real finder and entry display without opening picker windows.
      pickers.new = function(_, config)
        picker_config = config
        return { find = function() end }
      end
      lsp.get_calls = function(_, _, final_cb)
        requests = requests + 1
        final_cb()
      end
    end,
    post_case = function()
      pickers.new = originals.new_picker
      lsp.get_calls = originals.get_calls
      THGlobalState = saved_state
    end,
  },
})

local function node(leaf)
  local uri = vim.uri_from_fname(vim.fn.getcwd() .. "/example.lua")
  local location = { textDocument = { uri = uri }, position = { line = 0, character = 0 } }
  local entry = Entry.add_root("reference", location)
  entry.leaf = leaf or false
  return Node.new(uri, "reference", 1, 0, entry)
end

local function display(value)
  ui.show(value:to_list(false), { disable_devicons = true, previewer = {} })
  local entry = picker_config.finder.results[1]
  -- Rendering must preserve the navigation target.
  eq(entry.filename, value.filename)
  eq(entry.lnum, value.lnum)
  eq(entry.col, value.col)
  return entry.display(entry, { results_win = vim.api.nvim_get_current_win(), selection_caret = "" })
end

T["marks unresolved references as leaves before any expansion without searching them"] = function()
  local value = node(true)
  eq(value.cache.searched, "No")
  eq(value.cache.searched_node, nil)
  eq(display(value):find("reference (leaf) ", 1, true) ~= nil, true)
  eq(requests, 0)
  eq(value.cache.searched, "No")
  eq(value.expanded, false)
end

T["keeps the leaf marker after expansion and collapse without issuing requests"] = function()
  local value = node(true)
  local finished = 0
  value:expand(function()
    finished = finished + 1
  end)
  eq(finished, 1)
  eq(value.cache.searched, "Yes")
  eq(value.children, {})
  eq(display(value):find("reference (leaf) ", 1, true) ~= nil, true)
  value:collapse(function() end)
  eq(display(value):find("reference (leaf) ", 1, true) ~= nil, true)
  eq(requests, 0)
end

T["retains the unknown marker for searchable nodes"] = function()
  local value = node(false)
  eq(display(value):find("reference ? ", 1, true) ~= nil, true)
  eq(requests, 0)
end

T["distinguishes searched functions without callers from unresolved reference leaves"] = function()
  local value = node(false)
  value:expand(function() end)
  eq(value.cache.searched, "Yes")
  eq(display(value):find("reference (none) ", 1, true) ~= nil, true)
  eq(requests, 1)
end

return T
