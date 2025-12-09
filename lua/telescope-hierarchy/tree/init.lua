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
---@param fallback_clients vim.lsp.Client[]
---@param using_fallback boolean
---@param callback fun(client: vim.lsp.Client, using_fallback: boolean) The next async function to be called with the chosen LSP client
local function pick_client(clients, fallback_clients, using_fallback, callback)
  if #clients == 0 then
    if using_fallback and #fallback_clients > 0 then
      -- Use reference fallback
      vim.notify("Call hierarchy not supported by LSP. Using reference-based fallback.", vim.log.levels.INFO)
      if #fallback_clients == 1 then
        callback(fallback_clients[1], true)
      else
        vim.ui.select(fallback_clients, {
          prompt = "More than one possible LSP for references. Please choose which to use",
          format_item = function(client)
            return client.name
          end,
        }, function(client)
          callback(client, true)
        end)
      end
      return
    end
    vim.notify("No LSPs attached that will generate a call hierarchy", vim.log.levels.WARN)
    return
  end
  if #clients == 1 then
    callback(clients[1], false)
  else
    -- More than one LSP, gonna have to pick a fav
    vim.ui.select(clients, {
      prompt = "More than one possible LSP. Please choose which to use",
      format_item = function(client)
        return client.name
      end,
    }, function(client)
      callback(client, false)
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
  local clients = vim.lsp.get_clients({ method = "textDocument/prepareCallHierarchy", bufnr = bufnr })
  
  -- Check if we should use reference fallback
  local state = require("telescope-hierarchy.state")
  local enable_fallback = state.get("enable_reference_fallback")
  local using_fallback = enable_fallback and direction:is_incoming() -- Only for incoming calls
  
  local fallback_clients = {}
  if using_fallback and #clients == 0 then
    fallback_clients = vim.lsp.get_clients({ method = "textDocument/references", bufnr = bufnr })
  end
  
  pick_client(clients, fallback_clients, using_fallback, function(client, is_using_fallback)
    lsp.init(client, bufnr, mode, direction, is_using_fallback)
    local root = create_root()
    root:search(function(expanded_root)
      callback(expanded_root)
    end)
  end)
end

return Tree
