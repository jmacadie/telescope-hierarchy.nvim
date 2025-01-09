---@class LSP
---@field client vim.lsp.Client
---@field bufnr integer
---@field mode Mode Either "Call" or "Type"
local LSP = {}
LSP.__index = LSP

---Create a new LSP instance, which will cache all the info to make repeated
---requests to the LSP client
---@param client vim.lsp.Client
---@param bufnr integer
---@param mode Mode Either "Call" or "Type"
---@return LSP
function LSP.new(client, bufnr, mode)
  local self = {
    client = client,
    bufnr = bufnr,
    mode = mode, -- The hierarchy type will remain fixed for the current Telescope session
  }
  setmetatable(self, LSP)
  return self
end

---@private
---@param method string: The method being called
---@param params table
---@param callback function: The function to be called _after_ the LSP request has returned
function LSP:make_request(method, params, callback)
  local version = vim.version()

  if version.minor == 10 then
    -- The disables are for me on nightly, to silence the Lua LS diagnostics about calling this
    -- function incorrectly
    ---@diagnostic disable-next-line param-type-mismatch
    self.client.request(method, params, function(err, result)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      if result == nil then
        return
      end
      callback(result)
    end, self.bufnr) ---@diagnostic disable-line param-type-mismatch
  else
    self.client:request(method, params, function(err, result)
      if err then
        vim.notify(err.message, vim.log.levels.ERROR)
        return
      end
      if result == nil then
        return
      end
      callback(result)
    end, self.bufnr)
  end
end

--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_prepareCallHierarchy
---@private
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param callback fun(result: lsp.CallHierarchyItem[])
function LSP:prepare_call_hierarchy(position, callback)
  -- We should not proceed with call hierarchy when if the LSP is in type hierarchy mode
  if not self.mode:is_call() then
    return
  end
  self:make_request("textDocument/prepareCallHierarchy", position, callback)
end

---Run the incoming / outgoing calls LSP call
---It takes two callbacks, as interaction with the LSP is in two parts:
---1) We call prepareCallHierarchy, which returns a list of CallHierarchyItems
---2) Then with each CallHierarchyItem, we can make the incomingCalls or outgoingCalls call
---The `each_cb` callback is run for each return of return of step 2. This is intended to be a processing step, such as adding the results to a table.
---The `final_cb` callback is called after all step 2's have returned. This is intened to hold refernce to the following code to be run once all the requests to the LSP have been fully resolved
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_incomingCalls
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#callHierarchy_outgoingCalls
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param direction Direction Are we dealing with incoming or outgoing calls?
---@param each_cb fun(calls: lsp.CallHierarchyIncomingCall[] | lsp.CallHierarchyOutgoingCall[]) Callback to be run on every return from incomingCalls / outgoingCalls
---@param final_cb fun() Callback to be run once all requests have resolved
function LSP:get_calls(position, direction, each_cb, final_cb)
  self:prepare_call_hierarchy(position, function(result)
    if result == nil then
      return
    end
    local method = direction:is_incoming() and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
    local results_counter = #result
    for _, item in ipairs(result) do
      self:make_request(method, { item = item }, function(calls)
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

return LSP
