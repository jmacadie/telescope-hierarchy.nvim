local lsp = require("telescope-hierarchy.lsp")
local node = require("telescope-hierarchy.tree.node")

local M = {}

--- Creates the root node
---@param lsp_ref LSP
---@return Node
local function create_root(lsp_ref)
  -- TODO: check we are on a function declaration
  -- Maybe move location if we are on a function declaration line, or even in the body?
  local current_position = vim.lsp.util.make_position_params(0, lsp_ref.client.offset_encoding)
  local uri = current_position.textDocument.uri
  local text = vim.fn.expand("<cword>")
  local lnum = current_position.position.line + 1
  local col = current_position.position.character + 1
  return node.new(uri, text, lnum, col, current_position, lsp_ref)
end

---@param clients vim.lsp.Client[]
---@param callback fun(client: vim.lsp.Client) The next async function to be called with the chosen LSP client
local function pick_client(clients, callback)
  if #clients == 0 then
    vim.notify("No LSPs attached that will generate a call hierarchy", vim.log.levels.WARN)
    return
  end
  if #clients == 1 then
    callback(clients[1])
  else
    -- More than one LSP, gonna have to pick a fav
    vim.ui.select(clients, {
      prompt = "More than one possible LSP. Please choose which to use",
      format_item = function(client)
        return client.name
      end,
    }, callback)
  end
end

--- Create a new tree from the current position. Since these LSP calls are async, we can
--- only create this new tree async as well, so will need to hand it to a callback handler
--- when we're finally done
---@param callback fun(root: Node)
M.new = function(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ method = "textDocument/prepareCallHierarchy", bufnr = bufnr })
  pick_client(clients, function(client)
    local lsp_ref = lsp.new(client, bufnr)
    local root = create_root(lsp_ref)
    root:search(true, function()
      callback(root)
    end)
  end)
end

return M
