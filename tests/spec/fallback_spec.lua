local test = require("mini.test")
local eq = test.expect.equality
local Tree = require("telescope-hierarchy.tree")
local state = require("telescope-hierarchy.state")
local mode = require("telescope-hierarchy.enums.mode")
local direction = require("telescope-hierarchy.enums.direction")

local saved_state, originals, buffers, requests, queries, clients
local source, completed, root
local function buffer(lines, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  buffers[#buffers + 1] = bufnr
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", filetype or "lua", { buf = bufnr })
  return bufnr
end

local function reference(document_uri, row, col)
  return {
    uri = document_uri,
    range = { start = { line = row, character = col }, ["end"] = { line = row, character = col + 6 } },
  }
end

local function client(name)
  local obj = { name = name, offset_encoding = "utf-16" }
  local function request(method, params, callback, bufnr)
    requests[#requests + 1] = { method = method, params = params, callback = callback, bufnr = bufnr }
    return true, #requests
  end
  if vim.version().minor == 10 then
    obj.request = request
  else
    obj.request = function(_, ...)
      return request(...)
    end
  end
  return obj
end

local function new_tree(tree_direction)
  Tree.new(mode.CALL, tree_direction or direction.INCOMING, function(created, pending)
    if not pending then
      completed = completed + 1
      root = created
    end
  end)
end

local function reply(index, result, err)
  -- Exercise the deferred path, not just synchronous test doubles.
  local responded = false
  vim.schedule(function()
    requests[index].callback(err, result)
    responded = true
  end)
  eq(
    vim.wait(1000, function()
      return responded
    end),
    true
  )
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
      originals = {
        get_clients = vim.lsp.get_clients,
        select = vim.ui.select,
        bufnr = vim.api.nvim_get_current_buf(),
        cursor = vim.api.nvim_win_get_cursor(0),
      }
      buffers, requests, queries = {}, {}, {}
      completed, root = 0, nil
      source = buffer({ "local function target()", "  work()", "end" })
      vim.api.nvim_set_current_buf(source)
      vim.api.nvim_win_set_cursor(0, { 2, 2 })
      assert(vim.treesitter.get_parser(source, "lua"), "Lua test parser unavailable; run make deps")
      local server = client("test")
      clients = {
        ["textDocument/prepareCallHierarchy"] = {},
        ["textDocument/references"] = { server },
      }
      vim.lsp.get_clients = function(opts)
        queries[#queries + 1] = opts
        return clients[opts.method] or {}
      end
      state.set("enable_reference_fallback", true)
    end,
    post_case = function()
      vim.lsp.get_clients = originals.get_clients
      vim.ui.select = originals.select
      THGlobalState = saved_state
      vim.api.nvim_set_current_buf(originals.bufnr)
      vim.api.nvim_win_set_cursor(0, originals.cursor)
      for _, bufnr in ipairs(buffers) do
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
  },
})

for _, tree_direction in ipairs({ direction.INCOMING, direction.OUTGOING }) do
  T["prefers native " .. tree_direction.val .. " hierarchy even when fallback is enabled"] = function()
    clients["textDocument/prepareCallHierarchy"] = { client("native") }
    new_tree(tree_direction)
    eq(queries, { { method = "textDocument/prepareCallHierarchy", bufnr = source } })
    eq(state.get("using_fallback"), false)
    eq(#requests, 1)
    eq(requests[1].method, "textDocument/prepareCallHierarchy")
    reply(1, { { name = "target" } })
    local method = tree_direction:is_incoming() and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
    eq(requests[2].method, method)
    eq(completed, 0)
    reply(2, {})
    eq(completed, 1)
    eq(#requests, 2)
  end
end

T["does not switch to references when native preparation is empty"] = function()
  clients["textDocument/prepareCallHierarchy"] = { client("native") }
  new_tree()
  eq(requests[1].method, "textDocument/prepareCallHierarchy")
  reply(1, {})
  eq(completed, 1)
  eq(#requests, 1)
  eq(state.get("using_fallback"), false)
end

for _, fallback in ipairs({ false, true }) do
  T["cancels " .. (fallback and "fallback" or "native") .. " client selection without starting work"] = function()
    local method = fallback and "textDocument/references" or "textDocument/prepareCallHierarchy"
    clients[method] = { client("one"), client("two") }
    local selection
    vim.ui.select = function(items, opts, callback)
      eq(#items, 2)
      eq(opts.format_item(items[1]), "one")
      selection = callback
    end
    local before = vim.deepcopy(THGlobalState)
    local cursor = vim.api.nvim_win_get_cursor(0)
    new_tree()
    eq(type(selection), "function")
    eq(pcall(selection, nil), true)
    eq(requests, {})
    eq(completed, 0)
    eq(root, nil)
    eq(THGlobalState, before)
    eq(vim.api.nvim_get_current_buf(), source)
    eq(vim.api.nvim_win_get_cursor(0), cursor)
  end
end

T["groups nested and same-line callers by their own identifiers"] = function()
  local line = "local function first() target() end; local function second() target() end"
  local same_line = buffer({ line })
  local nested =
    buffer({ "local function outer()", "  local function inner()", "    target()", "  end", "  target()", "end" })
  local first_col = assert(line:find("target", 1, true)) - 1
  local second_col = assert(line:find("target", first_col + 2, true)) - 1
  local nested_uri, same_uri = vim.uri_from_bufnr(nested), vim.uri_from_bufnr(same_line)
  new_tree()
  eq(requests[1].method, "textDocument/references")
  reply(1, {
    reference(nested_uri, 2, 4),
    reference(nested_uri, 4, 2),
    reference(same_uri, 0, first_col),
    reference(same_uri, 0, second_col),
  })
  eq(completed, 1)
  eq(#root.children, 4)
  local locations = {}
  for _, child in ipairs(root.children) do
    locations[child.text] = child.cache.location.position
  end
  eq(locations, {
    inner = { line = 1, character = 17 },
    outer = { line = 0, character = 15 },
    first = { line = 0, character = 15 },
    second = { line = 0, character = assert(line:find("second", 1, true)) - 1 },
  })
  eq(vim.api.nvim_get_current_buf(), source)
  eq(vim.api.nvim_win_get_cursor(0), { 2, 2 })
end

T["keeps unresolved references navigable but never queries them as callers"] = function()
  local top_level = buffer({ "  target()" })
  local no_parser = buffer({ "  target()" }, "hierarchy_missing_parser")
  new_tree()
  reply(1, { reference(vim.uri_from_bufnr(top_level), 0, 2), reference(vim.uri_from_bufnr(no_parser), 0, 2) })
  eq(completed, 1)
  eq(#root.children, 2)
  local filenames = {}
  for _, child in ipairs(root.children) do
    eq(child.text, "target()")
    eq(child.lnum, 1)
    eq(child.col, 2) -- Telescope passes entry.col directly to nvim_win_set_cursor.
    filenames[child.filename] = true
    local finished = 0
    child:expand(function(_, pending)
      if not pending then
        finished = finished + 1
      end
    end, true)
    eq(finished, 1)
    eq(child.children, {})
  end
  eq(filenames, { [vim.api.nvim_buf_get_name(top_level)] = true, [vim.api.nvim_buf_get_name(no_parser)] = true })
  local refreshes = 0
  root:multi_expand(3, function()
    refreshes = refreshes + 1
  end)
  eq(refreshes, 1)
  eq(#requests, 1)
end

T["ignores flat symbols and makes zero document-symbol requests per URI on each expansion"] = function()
  local caller = buffer({ "local function caller()", "  target()", "  target()", "end" })
  local other = buffer({ "local function other()", "  target()", "end" })
  local caller_uri, other_uri = vim.uri_from_bufnr(caller), vim.uri_from_bufnr(other)
  -- SymbolInformation has no enclosing function range. It must not be used to
  -- guess a caller from the nearest preceding symbol; resolution is Tree-sitter only.
  local flat_symbols = {
    { name = "misleading", kind = 12, location = reference(caller_uri, 0, 0) }, -- SymbolKind.Function
  }
  local server = clients["textDocument/references"][1]
  local original_request = server.request
  local symbol_requests = 0
  server.request = function(...)
    local args = { ... }
    local method = args[vim.version().minor == 10 and 1 or 2]
    if method == "textDocument/documentSymbol" then
      symbol_requests = symbol_requests + 1
      args[vim.version().minor == 10 and 3 or 4](nil, flat_symbols)
      return true, 99
    end
    return original_request(...)
  end
  new_tree()
  reply(1, { reference(caller_uri, 1, 2), reference(other_uri, 1, 2), reference(caller_uri, 2, 2) })
  eq(completed, 1)
  eq(#root.children, 3)
  local caller_nodes = {}
  for _, child in ipairs(root.children) do
    eq(child.text == "caller" or child.text == "other", true)
    if child.text == "caller" then
      caller_nodes[#caller_nodes + 1] = child
    end
  end
  eq(#caller_nodes, 2)
  eq(rawequal(caller_nodes[1].cache, caller_nodes[2].cache), true)
  local finished = 0
  for _, child in ipairs(caller_nodes) do
    child:expand(function(_, pending)
      if not pending then
        finished = finished + 1
      end
    end)
  end
  eq(#requests, 2) -- Both call sites share one pending caller expansion.
  eq(requests[2].method, "textDocument/references")
  eq(requests[2].params.textDocument.uri, caller_uri)
  reply(2, { reference(other_uri, 1, 2) })
  eq(finished, 2)
  eq(symbol_requests, 0)
  eq(#requests, 2)
end

return T
