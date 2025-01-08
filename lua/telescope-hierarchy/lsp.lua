local state = require("telescope-hierarchy.state")

local lsp = {}
lsp.__index = lsp

---Create a new LSP instance, which will cache all the info to make repeated
---requests to the LSP client
---@param client vim.lsp.Client
---@param bufnr integer
---@param mode Mode
---@param direction CallDirection | TypeDirection
function lsp.init(client, bufnr, mode, direction)
  state.set("lsp", {
    client = client,
    bufnr = bufnr,
  })
  state.set("mode", mode)
  state.set("direction", direction)
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

  local version = vim.version()

  if version.minor == 10 then
    -- The disables are for me on nightly, to silence the Lua LS diagnostics about calling this
    -- function incorrectly
    ---@diagnostic disable-next-line:param-type-mismatch
    client.request(method, params, function(err, result)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      if result == nil then
        -- Make sure we run the callback with no results
        callback({})
        return
      end
      callback(result)
    end, bufnr) ---@diagnostic disable-line:param-type-mismatch
  else
    client:request(method, params, function(err, result)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      if result == nil then
        -- Make sure we run the callback with no results
        callback({})
        return
      end
      callback(result)
    end, bufnr)
  end
end

--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_prepareCallHierarchy
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param callback fun(result: lsp.CallHierarchyItem[])
local function prepare_call_hierarchy(position, callback)
  make_request("textDocument/prepareCallHierarchy", position, callback)
end

---Run the incoming / outgoing calls LSP call
---It takes two callbacks, as interaction with the LSP is in two parts:
---1) We call prepareCallHierarchy, which returns a list of CallHierarchyItems
---2) Then with each CallHierarchyItem, we can make the incomingCalls or outgoingCalls request
---The `each_cb` callback is run for each return of return of step 2. This is intended to be a processing step, such as adding the results to a table.
---The `final_cb` callback is called after all step 2's have returned. This is intened to hold refernce to the following code to be run once all the requests to the LSP have been fully resolved
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_incomingCalls
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_outgoingCalls
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param each_cb fun(calls: lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]) Callback to be run on every return from incomingCalls / outgoingCalls
---@param final_cb fun() Callback to be run once all requests have resolved
local function get_calls(position, each_cb, final_cb)
  prepare_call_hierarchy(position, function(result)
    if result == nil then
      return
    end
    local results_counter = #result
    if results_counter == 0 then
      final_cb()
    end

    local direction = assert(state.direction())
    ---@cast direction -TypeDirection
    local method = direction:is_incoming() and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
    for _, item in ipairs(result) do
      make_request(method, { item = item }, function(calls)
        each_cb(calls)
        -- Trigger the final callback once all requests are done
        results_counter = results_counter - 1
        if results_counter == 0 then
          final_cb()
        end
      end)
    end
  end)
end

--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_prepareTypeHierarchy
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param callback fun(result: lsp.CallHierarchyItem[])
local function prepare_type_hierarchy(position, callback)
  make_request("textDocument/prepareTypeHierarchy", position, callback)
end

---Run the super / sub types LSP call
---It takes two callbacks as interaction with the LSP is in two parts:
---1) We call prepareTypeHierarchy, which returns a list of TypeHierarchyItems
---2) Then with each TypeHierarchyItem, we can make the supertype or subtype request
---The `each_cb` callback is run for each return of return of step 2. This is intended to be a processing step, such as adding the results to a table.
---The `final_cb` callback is called after all step 2's have returned. This is intened to hold refernce to the following code to be run once all the requests to the LSP have been fully resolved
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#typeHierarchy_supertypes
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#typeHierarchy_subtypes
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param each_cb fun(types: lsp.TypeHierarchyItem[]) Callback to be run on every return from supertypes / subtypes
---@param final_cb fun() Callback to be run once all type requests have resolved
local function get_types(position, each_cb, final_cb)
  prepare_type_hierarchy(position, function(result)
    if result == nil then
      return
    end
    local direction = assert(state.direction())
    ---@cast direction -CallDirection
    local method = direction:is_super() and "typeHierarchy/supertypes" or "typeHierarchy/subtypes"
    local results_counter = #result
    for _, item in ipairs(result) do
      make_request(method, { item = item }, function(calls)
        each_cb(calls)
        -- Trigger the final callback once all requests are done
        results_counter = results_counter - 1
        if results_counter == 0 then
          final_cb()
        end
      end)
    end
  end)
end

---Run the LSP call to find the relevant children, depending on whether we are in call or type mode
---(which is fixed for a given Telescope session) and which direction we are looking in (which can
---vary) within a session
---It takes two callbacks as interaction with the LSP is in two parts:
---1) We call prepareTypeHierarchy, which returns a list of TypeHierarchyItems
---2) Then with each TypeHierarchyItem, we can make the supertype or subtype request
---The `each_cb` callback is run for each return of return of step 2. This is intended to be a processing step, such as adding the results to a table.
---The `final_cb` callback is called after all step 2's have returned. This is intened to hold refernce to the following code to be run once all the requests to the LSP have been fully resolved
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param each_cb fun(types: lsp.TypeHierarchyItem[]) Callback to be run on every return from supertypes / subtypes
---@param final_cb fun() Callback to be run once all type requests have resolved
function lsp.get(position, each_cb, final_cb)
  local mode = assert(state.mode())

  if mode:is_call() then
    get_calls(position, each_cb, final_cb)
  else
    get_types(position, each_cb, final_cb)
  end
end

---Return the current cursor location as formatted for sending to the LSP
---@return lsp.TextDocumentPositionParams | nil params Will be nil if LSP has not been initialised yet
function lsp.make_position_params()
  local client, _ = assert(get_state())
  return vim.lsp.util.make_position_params(0, client.offset_encoding)
end

return lsp
