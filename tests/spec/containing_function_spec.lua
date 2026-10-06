local test = require("mini.test")
local eq = test.expect.equality
local ts = require("telescope-hierarchy.treesitter")
local lsp = require("telescope-hierarchy.lsp")
local Tree = require("telescope-hierarchy.tree")
local state = require("telescope-hierarchy.state")
local mode = require("telescope-hierarchy.enums.mode")
local direction = require("telescope-hierarchy.enums.direction")

local saved_state, originals, existing_buffers, files, current, cursor
local function buffer(lines, filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", filetype or "lua", { buf = bufnr })
  return bufnr
end

local function nested_buffer()
  return buffer({
    "local function outer()",
    "  local function inner()",
    "    target()",
    "  end",
    "  inner()",
    "end",
  })
end

local function unchanged()
  eq(vim.api.nvim_get_current_buf(), current)
  eq(vim.api.nvim_win_get_cursor(0), cursor)
end

local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
      originals = {
        bufnr = vim.api.nvim_get_current_buf(),
        cursor = vim.api.nvim_win_get_cursor(0),
        containing_function = ts.containing_function,
        get_clients = vim.lsp.get_clients,
        get_calls = lsp.get_calls,
        select = vim.ui.select,
      }
      existing_buffers, files = {}, {}
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        existing_buffers[bufnr] = true
      end
      current = buffer({ "local function current()", "  target()", "end" })
      vim.api.nvim_set_current_buf(current)
      vim.api.nvim_win_set_cursor(0, { 2, 2 })
      cursor = vim.api.nvim_win_get_cursor(0)
      -- Fail rather than silently skip the real-parser regression coverage.
      assert(vim.treesitter.get_parser(current, "lua"), "Lua test parser unavailable; run make deps")
    end,
    post_case = function()
      ts.containing_function = originals.containing_function
      vim.lsp.get_clients = originals.get_clients
      lsp.get_calls = originals.get_calls
      vim.ui.select = originals.select
      THGlobalState = saved_state
      vim.api.nvim_set_current_buf(originals.bufnr)
      vim.api.nvim_win_set_cursor(0, originals.cursor)
      -- Also catches buffers loaded by reference resolution, even after a failed assertion.
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if not existing_buffers[bufnr] then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      for _, path in ipairs(files) do
        vim.fn.delete(path)
      end
    end,
  },
})

T["finds the nearest named function in a background buffer without moving the cursor"] = function()
  local nested = nested_buffer()
  eq(ts.containing_function(nested, 2, 4), {
    name = "inner",
    selection_range = { 1, 17, 1, 22 },
    range = { 1, 2, 3, 5 },
  })
  eq(ts.containing_function(nested, 4, 2).name, "outer")
  unchanged()
end

T["distinguishes same-line functions and excludes references outside their ranges"] = function()
  local line = "local function first() end; local function second() target() end; target()"
  local bufnr = buffer({ line })
  local call_col = assert(line:find("target", 1, true)) - 1
  eq(ts.containing_function(bufnr, 0, call_col).name, "second")
  local final_call = assert(line:find("target", call_col + 2, true)) - 1
  eq(ts.containing_function(bufnr, 0, final_call), nil)
  local ending = buffer({ "local function caller()", "  target()", "end", "target()" })
  eq(ts.containing_function(ending, 3, 0), nil)
  unchanged()
end

T["does not attribute anonymous-function references to an outer named function"] = function()
  local anonymous = buffer({
    "local function outer()",
    "  local callback = function()",
    "    target()",
    "  end",
    "end",
  })
  eq(ts.containing_function(anonymous, 2, 4), nil)
  unchanged()
end

T["returns nil when a parser is unavailable without moving the cursor"] = function()
  local missing = buffer({ "target()" }, "hierarchy_missing_parser")
  eq(ts.containing_function(missing, 0, 0), nil)
  unchanged()
end

T["reparses background buffers after edits without relying on a highlighter"] = function()
  local nested = nested_buffer()
  eq(vim.treesitter.highlighter.active[nested], nil)
  eq(ts.containing_function(nested, 2, 4).name, "inner")
  vim.api.nvim_buf_set_lines(nested, 1, 2, false, { "  local function renamed()" })
  eq(ts.containing_function(nested, 2, 4).name, "renamed")
  unchanged()
end

local function reference(uri, row, col, width)
  return {
    uri = uri,
    range = { start = { line = row, character = col }, ["end"] = { line = row, character = col + (width or 6) } },
  }
end

-- Mock only the request transport: caller resolution uses actual parsed buffers.
local function resolve(locations, encoding, before_response)
  local request_count, final_count = 0, 0
  local client = { offset_encoding = encoding }
  local function request(method, params, cb, bufnr)
    eq(method, "textDocument/references")
    eq(params.context.includeDeclaration, false)
    eq(bufnr, current)
    request_count = request_count + 1
    vim.schedule(function()
      if before_response then
        before_response()
      end
      cb(nil, locations)
    end)
    return true, request_count
  end
  if vim.version().minor == 10 then
    client.request = request
  else
    client.request = function(_, ...)
      return request(...)
    end
  end
  lsp.init(client, current, mode.CALL, direction.INCOMING, true)
  local calls, batch_count = {}, 0
  lsp.get_calls(
    { textDocument = { uri = vim.uri_from_bufnr(current) }, position = { line = 0, character = 0 } },
    function(batch)
      batch_count = batch_count + 1
      calls = batch
    end,
    function()
      eq(batch_count, 1)
      final_count = final_count + 1
    end
  )
  eq(
    vim.wait(1000, function()
      return final_count > 0
    end),
    true
  )
  eq(final_count, 1)
  eq(request_count, 1)
  return calls
end

T["loads referenced files in the background and groups call sites without documentSymbol requests"] = function()
  local filename = vim.fn.tempname() .. ".lua"
  table.insert(files, filename)
  eq(vim.fn.writefile({ "local function caller()", "  target()", "  target()", "end" }, filename), 0)
  local uri = vim.uri_from_fname(filename)
  eq(vim.fn.bufnr(filename), -1)
  local locations = { reference(uri, 1, 2), reference(uri, 2, 2) }
  local calls = resolve(locations, "utf-16")
  eq(#calls, 1)
  eq(calls[1].from.name, "caller")
  eq(calls[1].from.uri, uri)
  eq(calls[1].from.selectionRange, { start = { line = 0, character = 15 }, ["end"] = { line = 0, character = 21 } })
  eq(calls[1].from.range, { start = { line = 0, character = 0 }, ["end"] = { line = 3, character = 3 } })
  eq(calls[1].fromRanges, { locations[1].range, locations[2].range })
  unchanged()
end

T["delivers callers in first-reference order and groups interleaved call sites"] = function()
  local nested = nested_buffer()
  vim.api.nvim_buf_set_name(nested, vim.fn.tempname() .. ".lua")
  local uri = vim.uri_from_bufnr(nested)
  local locations = { reference(uri, 4, 2, 5), reference(uri, 2, 4), reference(uri, 4, 2, 5) }
  local calls = resolve(locations, "utf-16")
  eq(#calls, 2)
  eq(calls[1].from.name, "outer")
  eq(calls[2].from.name, "inner")
  eq(calls[1].fromRanges, { locations[1].range, locations[3].range })
  eq(calls[2].fromRanges, { locations[2].range })
  unchanged()
end

T["completes an empty reference response exactly once"] = function()
  eq(resolve({}, "utf-16"), {})
  unchanged()
end

local unicode_line = 'local marker = "😀"; local function caller() local text = "😀"; target() end'
local name_byte = assert(unicode_line:find("caller", 1, true)) - 1
local ref_byte = assert(unicode_line:find("target", 1, true)) - 1
local function unicode_buffer()
  local bufnr = buffer({ unicode_line })
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".lua")
  return bufnr
end

T["retains the requesting client's encoding when another client is initialised before the response"] = function()
  local unicode = unicode_buffer()
  local resolved_byte_col
  ts.containing_function = function(bufnr, row, byte_col)
    resolved_byte_col = byte_col
    return originals.containing_function(bufnr, row, byte_col)
  end
  local location = reference(vim.uri_from_bufnr(unicode), 0, ref_byte - 4)
  local calls = resolve({ location }, "utf-16", function()
    lsp.init({ offset_encoding = "utf-8" }, current, mode.CALL, direction.INCOMING, true)
  end)
  eq(resolved_byte_col, ref_byte)
  eq(#calls, 1)
  eq(calls[1].from.name, "caller")
  eq(calls[1].from.selectionRange.start.character, name_byte - 2)
  eq(calls[1].from.range["end"].character, #unicode_line - 4)
  eq(calls[1].fromRanges, { location.range })
  unchanged()
end

local function root_at(bufnr, row, byte_col, encoding, tree_direction, defer_selection)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { row + 1, byte_col })
  local original_cursor = vim.api.nvim_win_get_cursor(0)
  local client = { name = "test", offset_encoding = encoding }
  vim.lsp.get_clients = function()
    return defer_selection and { client, client } or { client }
  end
  local requested_position, root, selection_callback
  lsp.get_calls = function(position, _, final_cb)
    requested_position = position
    final_cb()
  end
  vim.ui.select = function(_, _, callback)
    selection_callback = callback
  end
  state.set("enable_reference_fallback", false)
  Tree.new(mode.CALL, tree_direction or direction.INCOMING, function(created)
    root = created
  end)
  if defer_selection then
    eq(type(selection_callback), "function")
    -- Client selection must not make root construction depend on the UI's buffer/cursor.
    vim.api.nvim_set_current_buf(current)
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    selection_callback(client)
    eq(vim.api.nvim_get_current_buf(), current)
    eq(vim.api.nvim_win_get_cursor(0), { 2, 3 })
  else
    eq(vim.api.nvim_get_current_buf(), bufnr)
    eq(vim.api.nvim_win_get_cursor(0), original_cursor)
  end
  assert(root)
  eq(requested_position, root.cache.location)
  eq(root.cache.location.textDocument.uri, vim.uri_from_bufnr(bufnr))
  return root
end

for _, encoding in ipairs({ "utf-8", "utf-16", "utf-32" }) do
  -- Each emoji occupies four bytes, two UTF-16 units, or one UTF-32 unit.
  local adjustment = encoding == "utf-8" and 0 or encoding == "utf-16" and 2 or 3
  T["converts reference positions and caller ranges using " .. encoding] = function()
    local unicode = unicode_buffer()
    local resolved_byte_col
    ts.containing_function = function(bufnr, row, byte_col)
      resolved_byte_col = byte_col
      return originals.containing_function(bufnr, row, byte_col)
    end
    local location = reference(vim.uri_from_bufnr(unicode), 0, ref_byte - 2 * adjustment)
    local calls = resolve({ location }, encoding)
    eq(resolved_byte_col, ref_byte)
    eq(#calls, 1)
    eq(calls[1].from.name, "caller")
    eq(calls[1].from.selectionRange.start.character, name_byte - adjustment)
    eq(calls[1].from.selectionRange["end"].character, name_byte + 6 - adjustment)
    eq(calls[1].from.range["end"].character, #unicode_line - 2 * adjustment)
    eq(calls[1].fromRanges, { location.range })
    unchanged()
  end

  T["uses byte columns for root display and " .. encoding .. " for LSP queries"] = function()
    local root = root_at(unicode_buffer(), 0, ref_byte, encoding)
    eq(root.text, "caller")
    eq({ root.lnum, root.col }, { 1, name_byte + 1 })
    eq(root.cache.location.position, { line = 0, character = name_byte - adjustment })
  end
end

for _, tree_direction in ipairs({ direction.INCOMING, direction.OUTGOING }) do
  T["creates a non-mutating " .. tree_direction.val .. " root at the nearest function"] = function()
    local nested = nested_buffer()
    local root = root_at(nested, 2, 4, "utf-16", tree_direction)
    eq(root.text, "inner")
    eq({ root.lnum, root.col }, { 2, 18 })
    eq(root.cache.location.position, { line = 1, character = 17 })
    -- Whitespace in the body also resolves without moving to the name first.
    root = root_at(nested, 2, 0, "utf-16", tree_direction)
    eq(root.text, "inner")
    eq(root.cache.location.position, { line = 1, character = 17 })
  end
end

T["retains the original root position outside a function or without a parser"] = function()
  local ending = buffer({ "local function caller()", "  target()", "end", "target()" })
  local root = root_at(ending, 3, 2, "utf-16")
  eq(root.text, "target")
  eq({ root.lnum, root.col }, { 4, 3 })
  eq(root.cache.location.position, { line = 3, character = 2 })
  local missing = buffer({ "target()" }, "hierarchy_missing_parser")
  root = root_at(missing, 0, 2, "utf-16")
  eq(root.text, "target")
  eq({ root.lnum, root.col }, { 1, 3 })
  eq(root.cache.location.position, { line = 0, character = 2 })
end

T["preserves the original source location during delayed LSP selection"] = function()
  local nested = nested_buffer()
  local root = root_at(nested, 2, 4, "utf-16", direction.INCOMING, true)
  eq(root.text, "inner")
  eq({ root.lnum, root.col }, { 2, 18 })
  eq(root.cache.location.position, { line = 1, character = 17 })
end

return T
