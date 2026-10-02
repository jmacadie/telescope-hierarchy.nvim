local test = require("mini.test")
local eq = test.expect.equality
local lsp = require("telescope-hierarchy.lsp")
local state = require("telescope-hierarchy.state")
local direction = require("telescope-hierarchy.enums.direction")
local mode = require("telescope-hierarchy.enums.mode")

local saved_state, original_notify, requests, notifications
local position = { textDocument = { uri = "file:///example.lua" }, position = { line = 0, character = 0 } }
local T = test.new_set({
  hooks = {
    pre_case = function()
      saved_state = THGlobalState
      THGlobalState = {}
      requests, notifications = {}, {}
      original_notify = vim.notify
      vim.notify = function(message)
        table.insert(notifications, message)
      end
      local client = { offset_encoding = "utf-16" }
      local function request(method, params, callback, bufnr)
        table.insert(requests, { method = method, params = params, callback = callback, bufnr = bufnr })
        return true, #requests
      end
      if vim.version().minor == 10 then
        client.request = request
      else
        client.request = function(_, ...)
          return request(...)
        end
      end
      lsp.init(client, 17, mode.CALL, direction.INCOMING)
    end,
    post_case = function()
      vim.notify = original_notify
      THGlobalState = saved_state
    end,
  },
})

for _, tree_direction in ipairs({ direction.INCOMING, direction.OUTGOING }) do
  T["waits for every " .. tree_direction.val .. " response before completing"] = function()
    state.set("direction", tree_direction)
    local batches, finished = {}, 0
    lsp.get_calls(position, function(calls)
      table.insert(batches, calls)
    end, function()
      finished = finished + 1
    end)
    eq(requests[1].method, "textDocument/prepareCallHierarchy")
    eq(requests[1].params, position)
    eq(requests[1].bufnr, 17)
    requests[1].callback(nil, { { name = "one" }, { name = "two" } })
    eq(#requests, 3)
    local method = tree_direction:is_incoming() and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
    eq(requests[2].method, method)
    eq(requests[2].params, { item = { name = "one" } })
    requests[3].callback(nil, { "second" })
    eq(finished, 0)
    requests[2].callback(nil, { "first" })
    eq(batches, { { "second" }, { "first" } })
    eq(finished, 1)
  end
end

T["completes once when preparation returns nil"] = function()
  local finished = 0
  lsp.get_calls(position, function()
    error("No call batch expected")
  end, function()
    finished = finished + 1
  end)
  requests[1].callback(nil, nil)
  eq(finished, 1)
  eq(#requests, 1)
end

T["reports preparation errors and still completes"] = function()
  local finished = 0
  lsp.get_calls(position, function() end, function()
    finished = finished + 1
  end)
  requests[1].callback({ code = -32603, message = "failed" }, nil)
  eq(notifications, { "failed" })
  eq(finished, 1)
end

T["reports a call error without preventing the other responses from completing"] = function()
  local batches, finished = 0, 0
  lsp.get_calls(position, function()
    batches = batches + 1
  end, function()
    finished = finished + 1
  end)
  requests[1].callback(nil, { {}, {} })
  requests[2].callback({ message = "failed" }, nil)
  eq(finished, 0)
  requests[3].callback(nil, nil)
  eq(batches, 1)
  eq(finished, 1)
  eq(notifications, { "failed" })
end

return T
