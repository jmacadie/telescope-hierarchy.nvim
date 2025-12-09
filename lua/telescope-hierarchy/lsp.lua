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

--- Get references from LSP for use as a fallback when call hierarchy is not supported
--- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_references
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param callback fun(locations: lsp.Location[])
local function get_references(position, callback)
  local params = {
    textDocument = position.textDocument,
    position = position.position,
    context = {
      includeDeclaration = false, -- Exclude the definition itself
    },
  }
  
  ---@param result lsp.Location[] | nil
  ---@param err? lsp.ResponseError
  local process_result = function(result, err)
    if err then
      vim.notify(err.message, vim.log.levels.ERROR)
      callback({})
      return
    end
    if result == nil then
      callback({})
      return
    end
    callback(result)
  end
  
  make_request("textDocument/references", params, process_result)
end

---Helper to find the containing function at a given location using LSP documentSymbol
---@param uri string
---@param line integer (0-based)
---@param col integer (0-based)
---@param callback fun(name: string|nil, selection_range: table|nil)
local function find_containing_function(uri, line, col, callback)
  local params = {
    textDocument = { uri = uri }
  }
  
  ---Recursively search through document symbols to find which one contains the position
  ---@param symbols table[]
  ---@return table|nil The symbol that contains the position
  local function find_containing_symbol(symbols)
    if not symbols then return nil end
    
    for _, symbol in ipairs(symbols) do
      local range = symbol.range or symbol.location and symbol.location.range
      if range then
        local start_line = range.start.line
        local end_line = range["end"].line
        
        -- Check if this symbol contains our position
        if start_line <= line and line <= end_line then
          -- If it's a function/method, this might be our containing function
          local kind = symbol.kind
          if kind == vim.lsp.protocol.SymbolKind.Function or 
             kind == vim.lsp.protocol.SymbolKind.Method then
            return symbol
          end
          
          -- Otherwise, check children first (more specific)
          if symbol.children then
            local child_result = find_containing_symbol(symbol.children)
            if child_result then
              return child_result
            end
          end
          
          -- If no children matched and this is a function, return it
          if kind == vim.lsp.protocol.SymbolKind.Function or 
             kind == vim.lsp.protocol.SymbolKind.Method then
            return symbol
          end
        end
      end
    end
    return nil
  end
  
  make_request("textDocument/documentSymbol", params, function(result, err)
    if err or not result or #result == 0 then
      callback(nil, nil)
      return
    end
    
    local containing = find_containing_symbol(result)
    if containing then
      callback(containing.name, containing.selectionRange or containing.range)
    else
      callback(nil, nil)
    end
  end)
end

---Convert LSP references to a call hierarchy-like structure
---This is used as a fallback when the LSP doesn't support call hierarchy
---@async
---@param position lsp.TextDocumentPositionParams: The location in the code to search from
---@param each_cb fun(call: table) Callback to be run on every reference
---@param final_cb fun() Callback to be run once all references have been processed
function lsp.get_calls_from_references(position, each_cb, final_cb)
  local client, bufnr = assert(get_state())
  
  get_references(position, function(locations)
    if #locations == 0 then
      final_cb()
      return
    end
    
    local remaining = #locations
    -- Group references by their containing function
    -- Key: uri#line#col (of the containing function's selectionRange)
    -- Value: { name, uri, selection_range, fromRanges[] }
    local grouped = {}
    
    -- Convert each reference location to a call hierarchy-like structure
    for _, location in ipairs(locations) do
      -- Try to find the containing function at this reference location
      find_containing_function(
        location.uri,
        location.range.start.line,
        location.range.start.character,
        function(func_name, selection_range)
          -- If we couldn't find a containing function, use the line text as a fallback
          local name = func_name or "reference"
          if not func_name then
            local ref_filename = vim.uri_to_fname(location.uri)
            local ref_bufnr = vim.fn.bufnr(ref_filename)
            if ref_bufnr ~= -1 and vim.api.nvim_buf_is_loaded(ref_bufnr) then
              local line = location.range.start.line
              local lines = vim.api.nvim_buf_get_lines(ref_bufnr, line, line + 1, false)
              if #lines > 0 then
                name = lines[1]:match("^%s*(.-)%s*$") or "reference"
              end
            end
          end
          
          -- Use the function selection range if we found it, otherwise use reference location
          local final_selection_range = selection_range or location.range
          
          -- Create a unique key for this containing function
          local key = string.format("%s#%d#%d", 
            location.uri, 
            final_selection_range.start.line, 
            final_selection_range.start.character)
          
          -- Group references by containing function
          if not grouped[key] then
            grouped[key] = {
              name = name,
              uri = location.uri,
              selection_range = final_selection_range,
              fromRanges = {}
            }
          end
          table.insert(grouped[key].fromRanges, location.range)
          
          -- Decrement counter and call callbacks when all are done
          remaining = remaining - 1
          if remaining == 0 then
            -- Now emit the grouped calls
            for _, group in pairs(grouped) do
              local pseudo_call = {
                from = {
                  name = group.name,
                  uri = group.uri,
                  kind = vim.lsp.protocol.SymbolKind.Function,
                  range = group.fromRanges[1], -- Use first reference range as the main range
                  selectionRange = group.selection_range,
                },
                fromRanges = group.fromRanges,
              }
              each_cb(pseudo_call)
            end
            final_cb()
          end
        end
      )
    end
  end)
end

return lsp
