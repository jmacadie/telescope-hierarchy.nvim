local lsp = require("telescope-hierarchy.lsp")
local ts = require("telescope-hierarchy.treesitter")
local node = require("telescope-hierarchy.tree.node")
local cache = require("telescope-hierarchy.cache.entry")

local Tree = {}

---Create the root at the containing function's name, or the original cursor position.
---@param bufnr integer
---@param cursor [integer, integer] One-based row and zero-based byte column
---@param text string The word at the original cursor, used if no named function is found
---@return Node
local function create_root(bufnr, cursor, text)
  local row, byte_col = cursor[1] - 1, cursor[2]
  local target = ts.containing_function(bufnr, row, byte_col)
  if target then
    text = target.name
    row, byte_col = target.selection_range[1], target.selection_range[2]
  end

  local position = lsp.make_position_params(bufnr, row, byte_col)
  local cache_root = cache.add_root(text, position)
  -- Node locations use one-based byte columns; only LSP positions use its encoding.
  return node.new(position.textDocument.uri, text, row + 1, byte_col + 1, cache_root)
end

---@async
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
    }, function(client)
      if client then
        callback(client)
      end
    end)
  end
end

--- Create a new tree from the current position. Since these LSP calls are async, we can
--- only create this new tree async as well, so will need to hand it to a callback handler
--- when we're finally done
---@async
---@param mode Mode Either "Call" or "Type"
---@param direction Direction The direction this tree is running in on startup. It cam be changed later with a switch action
---@param callback fun(root: Node) The code to be run once the tree is instantiated
function Tree.new(mode, direction, callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local expand_ok, fallback_word = pcall(vim.fn.expand, "<cword>", false, false)
  local fallback_text = (expand_ok and fallback_word or "") --[[@as string]]

  local clients = vim.lsp.get_clients({ method = "textDocument/prepareCallHierarchy", bufnr = bufnr })

  -- Check if we should use reference fallback
  local state = require("telescope-hierarchy.state")
  local enable_fallback = state.get("enable_reference_fallback")
  local using_fallback = enable_fallback and direction:is_incoming() and #clients == 0 or false

  if using_fallback then
    clients = vim.lsp.get_clients({ method = "textDocument/references", bufnr = bufnr })
  end

  ---@async
  ---@param client vim.lsp.Client
  local function init_with_client(client)
    lsp.init(client, bufnr, mode, direction, using_fallback)
    local root = create_root(bufnr, cursor, fallback_text)
    root:search(callback)
  end

  pick_client(clients, init_with_client)
end

return Tree
