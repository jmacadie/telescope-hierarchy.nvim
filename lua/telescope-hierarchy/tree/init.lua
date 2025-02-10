local lsp = require("telescope-hierarchy.lsp")
local ts = require("telescope-hierarchy.treesitter")
local node = require("telescope-hierarchy.tree.node")
local cache = require("telescope-hierarchy.cache.entry")

local Tree = {}

--- Creates the root node
---@return Node
local function create_root()
  ts.find_function()
  -- This will always be non-nil as it gets called by `new()` _after_ `lsp.init()` and this is its only incoming call
  local current_position = assert(lsp.make_position_params())
  local uri = current_position.textDocument.uri
  local text = vim.fn.expand("<cword>")
  --- LSP is zero based, lua-land is one based
  local lnum = current_position.position.line + 1
  local col = current_position.position.character + 1
  local cache_root = cache.add_root(text, current_position)
  return node.new(uri, text, lnum, col, cache_root)
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
    }, callback)
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
  local clients = vim.lsp.get_clients({ method = "textDocument/prepareCallHierarchy", bufnr = bufnr })
  pick_client(clients, function(client)
    lsp.init(client, bufnr, mode, direction)
    local root = create_root()
    root:search(function(expanded_root)
      callback(expanded_root)
    end)
  end)
end

return Tree
