local state = require("telescope-hierarchy.state")
local Path = require("plenary.path")

local lsp = {}
lsp.__index = lsp

---Create a new LSP instance, which will cache all the info to make repeated
---requests to the LSP client
---@param client vim.lsp.Client
---@param bufnr integer
---@param mode Mode
---@param direction Direction
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
function lsp.get_calls(position, each_cb, final_cb)
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

---Return the current cursor location as formatted for sending to the LSP
---@return lsp.TextDocumentPositionParams | nil params Will be nil if LSP has not been initialised yet
function lsp.make_position_params()
  local client, _ = assert(get_state())
  return vim.lsp.util.make_position_params(0, client.offset_encoding)
end

return lsp
