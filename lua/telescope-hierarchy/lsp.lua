local state = require("telescope-hierarchy.state")
local ts = require("telescope-hierarchy.treesitter")
local Path = require("plenary.path")

local lsp = {}
lsp.__index = lsp

---Create a new LSP instance, which will cache all the info to make repeated
---requests to the LSP client
---@param client vim.lsp.Client
---@param bufnr integer
---@param mode Mode
---@param direction Direction
---@param using_fallback? boolean Whether we're using the reference fallback
function lsp.init(client, bufnr, mode, direction, using_fallback)
  state.set("lsp", {
    client = client,
    bufnr = bufnr,
  })
  state.set("mode", mode)
  state.set("direction", direction)
  state.set("using_fallback", using_fallback or false)
end

---Retrieve from global state
---@return vim.lsp.Client | nil client The LSP client
---@return integer | nil bufnr The buffer number LSP calls are being made from
local function get_state()
  local lsp_info = state.get("lsp")
  if not lsp_info then
    vim.notify("Must initialise the LSP first", vim.log.levels.ERROR)
    return
  end
  return lsp_info.client, lsp_info.bufnr
end

---@async
---@param method string: The method being called
---@param params table
---@param callback function: The function to be called _after_ the LSP request has returned
local function make_request(method, params, callback)
  local client, bufnr = assert(get_state())

  ---Process the result of making the request to the LSP with the native neovim API
  ---@param err lsp.ResponseError
  ---@param result any
  local process_result = function(err, result)
    if err then
      -- local msg = string.format(
      --   "Got Error!\nmethod: %s\nparams: %s\nresult: %s\nerr: %s",
      --   method,
      --   vim.inspect(params),
      --   vim.inspect(result),
      --   vim.inspect(err)
      -- )
      -- vim.notify(msg, vim.log.levels.INFO)
      callback({}, err)
      return
    end
    if result == nil then
      -- local msg = string.format(
      --   "Got NIL result!\nmethod: %s\nparams: %s\nresult: %s\nerr: %s",
      --   method,
      --   vim.inspect(params),
      --   vim.inspect(result),
      --   vim.inspect(err)
      -- )
      -- vim.notify(msg, vim.log.levels.INFO)
      callback({})
      return
    end
    -- local msg = string.format(
    --   "Got something!\nmethod: %s\nparams: %s\nresult: %s\nerr: %s",
    --   method,
    --   vim.inspect(params),
    --   vim.inspect(result),
    --   vim.inspect(err)
    -- )
    -- vim.notify(msg, vim.log.levels.INFO)
    callback(result)
  end

  local version = vim.version()
  if version.minor == 10 then
    -- The disables are for me on nightly, to silence the Lua LS diagnostics about calling this
    -- function incorrectly
    client.request(method, params, process_result, bufnr) ---@diagnostic disable-line:param-type-mismatch
  else
    client:request(method, params, process_result, bufnr)
  end
end

--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_prepareCallHierarchy
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param callback fun(items: lsp.CallHierarchyItem[])
local function prepare_call_hierarchy(position, callback)
  -- We should not proceed with call hierarchy when if the LSP is in type hierarchy mode
  local mode = assert(state.mode())
  if not mode:is_call() then
    return
  end

  ---clangd will error if you try to call prepareCallHierarchy on a file that is not
  ---loaded in memory. So let's catch the error code and if it's the right one
  ---open the file in a background buffer, before trying again
  ---https://github.com/jmacadie/telescope-hierarchy.nvim/issues/9
  ---@param result lsp.CallHierarchyItem[]
  ---@param err? lsp.ResponseError
  local catch_clangd_non_added_error = function(result, err)
    if err then
      if err.code == -32602 then
        --load the file into a background buffer...
        local filename = vim.uri_to_fname(position.textDocument.uri)
        filename = Path:new(filename):normalize(vim.uv.cwd())
        pcall(function()
          vim.cmd(string.format("bufadd %s", vim.fn.fnameescape(filename)))
        end)
        local bufnr = vim.fn.bufnr(vim.fn.fnameescape(filename), true)
        vim.fn.bufload(bufnr)
        --& go again
        prepare_call_hierarchy(position, callback)
      else
        -- For any other type of error warn & carry on with an empty list
        vim.notify(err.message, vim.log.levels.ERROR)
        callback({})
      end
      return
    end
    callback(result)
  end

  make_request("textDocument/prepareCallHierarchy", position, catch_clangd_non_added_error)
end

---Run the incoming / outgoing calls LSP call
---It takes two callbacks, as interaction with the LSP is in two parts:
---1) We call prepareCallHierarchy, which returns a list of CallHierarchyItems
---2) Then with each CallHierarchyItem, we can make the incomingCalls or outgoingCalls call
---The `each_cb` callback is run for each return of return of step 2. This is intended to be a processing step, such as adding the results to a table.
---The `final_cb` callback is called after all step 2's have returned. This is intened to hold refernce to the following code to be run once all the requests to the LSP have been fully resolved
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_incomingCalls
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_outgoingCalls
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param each_cb fun(calls: lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]) Callback to be run on every return from incomingCalls / outgoingCalls
---@param final_cb fun() Callback to be run once all requests have resolved
local function get_calls_from_hierarchy(position, each_cb, final_cb)
  ---Callback function to be called after the initial call to prepareCallHierarchy
  ---Takes the list of locations that were returned by the call to prepareCallHierarchy and on each of them
  ---makes the actual call to resolve either the incoming or outgoing calls
  ---@async
  ---@param items lsp.CallHierarchyItem[]
  local after_prep = function(items)
    local items_counter = #items
    -- If there are no items returned by prepareCallHierarchy then just run the closing
    -- callback & quit out
    if items_counter == 0 then
      final_cb()
      return
    end

    ---Callback to process the return from incomingCalls or outgoingCalls
    ---Takes a list of calls that are the incoming / outgoing for each CallHierarchyItem
    ---On each return it will call `each_cb` on the resulting list of locations
    ---On the return from the final CallHierarchyItem, we also call `final_cb`
    ---
    ---Since we moved `make_request` to bubble up the error we need to handle it in
    ---this callback. We warn of the error but carry on processing as there are other
    ---countdown mechanisms in the code that are relying on all these inner calls returning
    ---correctly. This may not be the correct behaviour but it is what I have gone with
    ---for now
    ---@param calls lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]
    ---@param err? lsp.ResponseError
    local process_calls = function(calls, err)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
      else
        each_cb(calls)
      end
      items_counter = items_counter - 1
      if items_counter == 0 then
        final_cb()
      end
    end

    local direction = assert(state.direction())
    local method = direction:is_incoming() and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
    for _, item in ipairs(items) do
      make_request(method, { item = item }, process_calls)
    end
  end

  prepare_call_hierarchy(position, after_prep)
end

---Convert between LSP character offsets and Tree-sitter byte offsets.
---Neovim 0.11 added the encoding argument to these string helpers.
---@param text string
---@param character integer
---@param encoding string
---@return integer
local function to_byte_col(text, character, encoding)
  if encoding == "utf-8" then
    return character
  end
  if vim.version().minor == 10 then
    return vim.str_byteindex(text, character, encoding == "utf-16") ---@diagnostic disable-line:param-type-mismatch
  end
  return vim.str_byteindex(text, encoding, character, false)
end

---@param bufnr integer
---@param row integer Zero-based row
---@param byte_col integer Zero-based byte column
---@param encoding string
---@return lsp.Position
local function to_lsp_position(bufnr, row, byte_col, encoding)
  local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local character = byte_col
  if encoding ~= "utf-8" then
    if vim.version().minor == 10 then
      local utf32, utf16 = vim.str_utfindex(text, byte_col) ---@diagnostic disable-line:param-type-mismatch
      character = encoding == "utf-16" and utf16 or utf32
    else
      character = vim.str_utfindex(text, encoding, byte_col, false)
    end
  end
  return { line = row, character = character }
end

---@param bufnr integer
---@param range Range4 Zero-based Tree-sitter range, with byte columns
---@param encoding string
---@return lsp.Range
local function to_lsp_range(bufnr, range, encoding)
  return {
    start = to_lsp_position(bufnr, range[1], range[2], encoding),
    ["end"] = to_lsp_position(bufnr, range[3], range[4], encoding),
  }
end

---Format an explicit buffer position for the selected LSP, without moving the cursor.
---@param bufnr integer
---@param row integer Zero-based row
---@param byte_col integer Zero-based byte column
---@return lsp.TextDocumentPositionParams
function lsp.make_position_params(bufnr, row, byte_col)
  local client = assert(get_state())
  return {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = to_lsp_position(bufnr, row, byte_col, client.offset_encoding),
  }
end

---Resolve a reference's caller without changing the current buffer or cursor.
---Load referenced files in background buffers so Tree-sitter can parse them.
---@param location lsp.Location
---@param encoding string
---@return lsp.CallHierarchyItem | nil
local function find_containing_function(location, encoding)
  local ok, bufnr = pcall(vim.uri_to_bufnr, location.uri)
  if not ok then
    return
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    local loaded = pcall(vim.fn.bufload, bufnr)
    if not loaded or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
  end

  local start = location.range.start
  local text = vim.api.nvim_buf_get_lines(bufnr, start.line, start.line + 1, false)[1]
  if not text then
    return
  end
  local target = ts.containing_function(bufnr, start.line, to_byte_col(text, start.character, encoding))
  if not target then
    return
  end

  return {
    name = target.name,
    uri = location.uri,
    kind = vim.lsp.protocol.SymbolKind.Function,
    range = to_lsp_range(bufnr, target.range, encoding),
    selectionRange = to_lsp_range(bufnr, target.selection_range, encoding),
  }
end

---Preserve the existing display fallback for unresolved references.
---@param location lsp.Location
---@return lsp.CallHierarchyItem
local function hierarchy_item_from_location(location)
  local name = "reference"
  local bufnr = vim.fn.bufnr(vim.uri_to_fname(location.uri))
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local line = location.range.start.line
    local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
    if text then
      name = text:match("^%s*(.-)%s*$") or name
    end
  end
  return {
    name = name,
    uri = location.uri,
    kind = vim.lsp.protocol.SymbolKind.Function,
    range = location.range,
    selectionRange = location.range,
  }
end

---Group by URI and the containing function's name position.
---@param locations lsp.Location[]
---@param encoding string
---@return lsp.CallHierarchyIncomingCall[]
local function locations_to_calls(locations, encoding)
  ---@type table<string, lsp.CallHierarchyIncomingCall>
  local grouped = {}
  ---@type lsp.CallHierarchyIncomingCall[]
  local calls = {}

  for _, location in ipairs(locations) do
    local caller = find_containing_function(location, encoding) or hierarchy_item_from_location(location)
    local start = caller.selectionRange.start
    local key = string.format("%s#%d#%d", location.uri, start.line, start.character)
    local call = grouped[key]
    if not call then
      call = { from = caller, fromRanges = {} }
      grouped[key] = call
      table.insert(calls, call)
    end
    table.insert(call.fromRanges, location.range)
  end

  return calls
end

---Convert LSP references to a batch of incoming calls
---This is used as a fallback when the LSP doesn't support call hierarchy
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_references
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param add_calls_cb fun(calls: lsp.CallHierarchyIncomingCall[]) Callback to process the resolved incoming calls
---@param final_cb fun() Callback to be run once all references have been processed
local function get_calls_from_references(position, add_calls_cb, final_cb)
  local client = assert(get_state())
  local encoding = client.offset_encoding
  local params = {
    textDocument = position.textDocument,
    position = position.position,
    context = {
      includeDeclaration = false, -- Exclude the definition itself
    },
  }

  ---@param locations lsp.Location[]
  ---@param err? lsp.ResponseError
  local process_references = function(locations, err)
    if err then
      vim.notify(err.message, vim.log.levels.ERROR)
      final_cb()
      return
    end

    local calls = locations_to_calls(locations, encoding)
    add_calls_cb(calls)
    final_cb()
  end

  make_request("textDocument/references", params, process_references)
end

---Retrieve incoming / outgoing calls using the selected backend.
---The references fallback provides incoming calls only.
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param each_cb fun(calls: lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]) Callback to process each successful batch
---@param final_cb fun() Callback to be run once all requests have resolved
function lsp.get_calls(position, each_cb, final_cb)
  if state.get("using_fallback") then
    get_calls_from_references(position, each_cb, final_cb)
  else
    get_calls_from_hierarchy(position, each_cb, final_cb)
  end
end

return lsp
