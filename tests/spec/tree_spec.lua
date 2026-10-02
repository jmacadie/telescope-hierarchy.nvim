local test = require("mini.test")
local eq = test.expect.equality
local Node = require("telescope-hierarchy.tree.node")
local Entry = require("telescope-hierarchy.cache.entry")
local cache = require("telescope-hierarchy.cache")
local state = require("telescope-hierarchy.state")
local direction = require("telescope-hierarchy.enums.direction")
local lsp = require("telescope-hierarchy.lsp")

local uri = vim.uri_from_fname(vim.fn.getcwd() .. "/example.lua")
local function position(line, character, document_uri)
  return { textDocument = { uri = document_uri or uri }, position = { line = line, character = character or 0 } }
end

local function call(name, line, ranges)
  local item = { name = name, uri = uri, selectionRange = { start = { line = line, character = 0 } } }
  return { from = item, to = item, fromRanges = ranges or { { start = { line = line, character = 2 } } } }
end

local original_get_calls, saved_state, pending
local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
      state.set("direction", direction.INCOMING)
      original_get_calls = lsp.get_calls
      pending = {}
      lsp.get_calls = function(location, each_cb, final_cb)
        table.insert(pending, { location = location, each = each_cb, final = final_cb })
      end
    end,
    post_case = function()
      lsp.get_calls = original_get_calls
      THGlobalState = saved_state
    end,
  },
})

local function root()
  return Node.new(uri, "root", 1, 1, Entry.add_root("root", position(0)))
end

local function complete(index, calls)
  pending[index].each(calls or {})
  pending[index].final()
end

T["deduplicates cache locations by URI, line and column and resets on a new root"] = function()
  local node = root()
  eq(rawequal(node.cache, cache.get(position(0))), true)
  eq(rawequal(node.cache, cache.add({ location = position(0) })), true)
  eq(cache.get(position(1)), nil)
  eq(cache.get(position(0, 1)), nil)
  eq(cache.get(position(0, 0, uri .. ".other")), nil)
  local replacement = Entry.add_root("replacement", position(5))
  eq(cache.get(position(0)), nil)
  eq(rawequal(replacement, cache.get(position(5))), true)
end

T["shares pending searches, clones children and reuses the cache after collapse"] = function()
  local first = root()
  local second = Node.new(uri, "same", 1, 1, first.cache)
  local events = {}
  first:expand(function(_, is_pending)
    table.insert(events, is_pending and "pending" or "done")
  end)
  second:expand(function()
    table.insert(events, "clone")
  end)
  eq(first.cache.searched, "Pending")
  eq(#pending, 1)
  complete(1, { call("child", 3) })
  eq(events, { "pending", "done", "clone" })
  eq(first.cache.searched, "Yes")
  eq(second.expanded, true)
  eq(rawequal(second, second.children[1].parent), true)
  eq(rawequal(first.children[1], second.children[1]), false)
  eq(rawequal(first.children[1].cache, second.children[1].cache), true)
  first:collapse(function() end)
  first:expand(function() end)
  eq(#first.children, 1)
  eq(#pending, 1)
end

T["retains distinct call sites, removes sequential duplicates, and sorts numerically"] = function()
  local node = root()
  node:expand(function() end)
  local ranges = {
    { start = { line = 99, character = 2 } },
    { start = { line = 99, character = 2 } },
    { start = { line = 48, character = 2 } },
  }
  complete(1, { call("child", 3, ranges) })
  eq(#node.children, 2)
  eq(node.children[1].lnum, 49)
  eq(node.children[2].lnum, 100)
  eq(rawequal(node.children[1].cache, node.children[2].cache), true)
end

T["detects recursion and does not request recursive children"] = function()
  local node = root()
  node:expand(function() end)
  complete(1, { call("root", 0) })
  local recursive = node.children[1]
  eq(recursive.recursive, true)
  local called = false
  recursive:expand(function()
    called = true
  end)
  eq(called, false)
  recursive:expand(function()
    called = true
  end, true)
  eq(called, true)
  eq(#pending, 1)
end

T["renders only visible descendants with tree branch flags"] = function()
  local node = root()
  node:new_child(uri, "first", 2, 1, {})
  node:new_child(uri, "last", 3, 1, {})
  node.children[1]:new_child(uri, "grandchild", 4, 1, {})
  eq(#node:to_list(), 1)
  node.expanded = true
  node.children[1].expanded = true
  local list = node:to_list()
  eq(#list, 4)
  eq(list[1].tree_state, {})
  eq(list[2].tree_state, { false })
  eq(list[3].tree_state, { false, true })
  eq(list[4].tree_state, { true })
  eq(#node.children[1]:to_list(false), 2)
  eq(#node.children[1]:to_list(), 4)
end

T["multi-expands to the requested depth without searching the next layer"] = function()
  local node = root()
  local refreshes = 0
  node:multi_expand(2, function()
    refreshes = refreshes + 1
  end)
  complete(1, { call("child", 1) })
  eq(#pending, 2)
  complete(2, { call("grandchild", 2) })
  eq(node.expanded, true)
  eq(node.children[1].expanded, true)
  eq(node.children[1].children[1].expanded, false)
  eq(#pending, 2)
  eq(refreshes, 3) -- two pending refreshes and one completion
end

T["uses the caller's file for outgoing call sites"] = function()
  state.set("direction", direction.OUTGOING)
  local node = root()
  node:expand(function() end)
  local outgoing = call("callee", 10)
  outgoing.to.uri = uri .. ".other"
  complete(1, { outgoing })
  eq(node.children[1].filename, vim.uri_to_fname(uri))
  eq(node.children[1].cache.location.textDocument.uri, uri .. ".other")
end

return T
