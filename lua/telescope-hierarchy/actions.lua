local finders = require("telescope.finders")
local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local transform_mod = require("telescope.actions.mt").transform_mod
local Path = require("plenary.path")

local ui = require("telescope-hierarchy.ui")

local M = {}

---General code to refresh the picker after the nodes tree has been updated
---@param node Node
---@param picker Picker
---@param keep_selection? boolean Retain the current selection after refresh. If ommitted will assume true
local function refresh_picker(node, picker, keep_selection)
  local new_finder = finders.new_table({
    results = node:to_list(),
    -- LSP doesn't like entry_maker field of finder
    ---@diagnostic disable-next-line:undefined-field
    entry_maker = picker.finder.entry_maker,
  })

  if keep_selection or keep_selection == nil then
    local selection = picker:get_selection_row()
    local callbacks = { unpack(picker._completion_callbacks) } -- shallow copy
    picker:register_completion_callback(function(self)
      self:set_selection(selection)
      self._completion_callbacks = callbacks
    end)
  end
  picker:refresh(new_finder, {})
end

---Recursively expand the current node
---Since this could be quite expensive, it takes a depth parameter
---and will only expand to that many layers deep
---@param node Node
---@param depth integer
---@param refresh_cb fun(node: Node)
local function expand_all_to(node, depth, refresh_cb)
  ---Recursive heart of this function
  ---@param level integer
  ---@param frontier Node[]
  local function process_level(level, frontier, cb)
    ---@type Node[]
    local next = {}
    local remaining = #frontier

    for _, to_be_expanded in ipairs(frontier) do
      to_be_expanded:expand(function(expanded, pending)
        if pending then
          cb(node)
          return
        end

        for _, child in ipairs(expanded.children) do
          table.insert(next, child)
        end

        remaining = remaining - 1
        if remaining == 0 then
          if level > 1 and #next > 0 then
            process_level(level - 1, next, cb)
          else
            cb(node)
          end
        end
      end, true)
    end
  end

  process_level(depth, { node }, refresh_cb)
end

M.expand = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:expand(function(tree)
      refresh_picker(tree, picker)
    end)
  end
  return f
end

M.expand_5 = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    expand_all_to(node, 5, function(tree)
      refresh_picker(tree, picker)
    end)
  end
  return f
end

M.collapse = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:collapse(function(tree)
      refresh_picker(tree, picker)
    end)
  end
  return f
end

M.toggle = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:toggle(function(tree)
      refresh_picker(tree, picker)
    end)
  end
  return f
end

M.switch = function(prompt_bufnr)
  local function f()
    local picker = actions_state.get_current_picker(prompt_bufnr)
    ---@type Node
    local node = actions_state.get_selected_entry().value

    node:switch_direction(function(tree)
      picker.results_border:change_title(ui.title())
      refresh_picker(tree, picker, false)
    end)
  end
  return f
end

M.goto_definition = function(prompt_bufnr)
  local function f()
    -- Shamelessly stolen from Telescope
    -- I had to copy paste as I needed to very slightly modify the inner workings
    -- of this one rather long function, so I was unable to import and call Telescope code
    local entry = actions_state.get_selected_entry()
    ---@type Node
    local node = entry.value
    local loc = node.cache.location
    local filename = vim.uri_to_fname(loc.textDocument.uri)
    local row = loc.position.line + 1
    local col = loc.position.character

    local picker = actions_state.get_current_picker(prompt_bufnr)
    require("telescope.pickers").on_close_prompt(prompt_bufnr)
    pcall(function()
      vim.api.nvim_set_current_win(picker.original_win_id)
    end)
    local win_id = picker.get_selection_window(picker, entry)

    if picker.push_cursor_on_edit then
      vim.cmd("normal! m'")
    end

    if picker.push_tagstack_on_edit then
      local from = { vim.fn.bufnr("%"), vim.fn.line("."), vim.fn.col("."), 0 }
      local items = { { tagname = vim.fn.expand("<cword>"), from = from } }
      vim.fn.settagstack(vim.fn.win_getid(), { items = items }, "t")
    end

    if win_id ~= 0 and vim.nvim_get_current_win() ~= win_id then
      vim.api.nvim_set_current_win(win_id)
    end

    -- check if we didn't pick a different buffer
    -- prevents restarting lsp server
    if vim.api.nvim_buf_get_name(0) ~= filename then
      filename = Path:new(filename):normalize(vim.uv.cwd())
      pcall(function()
        vim.cmd(string.format("edit %s", vim.fn.fnameescape(filename)))
      end)
    end

    -- HACK: fixes folding: https://github.com/nvim-telescope/telescope.nvim/issues/699
    if vim.wo.foldmethod == "expr" then
      vim.schedule(function()
        vim.opt.foldmethod = "expr"
      end)
    end

    if vim.api.nvim_buf_get_name(0) == filename then
      vim.cmd([[normal! m']])
    end
    pcall(function()
      vim.api.nvim_win_set_cursor(0, { row, col })
    end)
  end
  return f
end

M.quit = function(prompt_bufnr)
  local function f()
    actions.close(prompt_bufnr)
  end
  return f
end

return transform_mod(M)
