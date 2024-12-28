local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local state = require("telescope.state")
local strings = require("plenary.strings")

local theme = require("telescope-hierarchy.theme")

local M = {}

local function gen_make_entry(opts)
  opts = opts or {}

  local disable_devicons = opts.disable_devicons

  ---Create the tree string for jut one entry (row) in the list
  ---@param tree_state boolean[] Series of flags showing for each level in whether the parent node is the last of the children
  ---@return string
  local function make_tree(tree_state)
    local tree = ""
    for idx, level_last in ipairs(tree_state) do
      if idx == #tree_state then
        if level_last then
          tree = tree .. "└╴"
        else
          tree = tree .. "├╴"
        end
      else
        if level_last then
          tree = tree .. "  "
        else
          tree = tree .. "┆ "
        end
      end
    end
    return tree
  end

  ---Create the child count suffix
  ---@param node Node
  ---@return string
  local function make_child_count(node)
    local child_count = ""
    if node.searched then
      if #node.children == 0 then
        child_count = "(none) "
      else
        if not node.expanded then
          child_count = "(" .. #node.children .. ") "
        end
      end
    else
      child_count = "? "
    end
    return child_count
  end

  ---@param results table A table holding the parts of the ultimate display string
  ---@param highlights table The highlights table that is being appended to
  ---@param start integer The current position in the display string
  ---@param text string The text the highlight is being applied to
  ---@param hl string The highlight to be applied
  ---@return integer new_pos The new position in the display string
  local function add_part(results, highlights, start, text, hl)
    text = tostring(text) -- convert numbers to strings
    table.insert(results, text)
    local len = text:len()
    local new_pos = start + len
    local highlight = { { start, new_pos }, hl }
    table.insert(highlights, highlight)
    return new_pos
  end

  local function results_width(picker)
    return vim.api.nvim_win_get_width(picker.results_win) - #picker.selection_caret
  end

  local function padded_filename(width, results, filename)
    local prefix_len = 0
    for _, str in ipairs(results) do
      prefix_len = prefix_len + strings.strdisplaywidth(str)
    end

    local suffix_len = 5 -- a ":", and space for 4 digits for lnum
    local available = width - prefix_len - suffix_len

    local truncated = strings.truncate(filename, available, "…", -1)
    return strings.align_str(truncated, available, true)
  end

  local make_display = function(entry, picker)
    local node = entry.value
    local width = results_width(picker)

    local results = {}
    local highlights = {}
    local position = 0
    local separator = " "

    position = add_part(results, highlights, position, make_tree(entry.tree_state), "TelescopeResultsMethod")
    position = add_part(results, highlights, position, separator, "")
    if not disable_devicons then
      position = add_part(results, highlights, position, "󰡱", "TelescopeResultsFunction")
      position = add_part(results, highlights, position, separator, "")
    end
    position = add_part(results, highlights, position, node.text, "TelescopeResultsFunction")
    position = add_part(results, highlights, position, separator, "")
    position = add_part(results, highlights, position, make_child_count(node), "TelescopeResultsComment")
    position = add_part(results, highlights, position, "     ", "")

    local formatted_fname = padded_filename(width, results, entry.filename)
    position = add_part(results, highlights, position, formatted_fname, "TelescopeResultsLineNr")
    position = add_part(results, highlights, position, ":", "TelescopeResultsMethod")
    _ = add_part(results, highlights, position, entry.lnum, "TelescopeResultsLineNr")

    local final_str = table.concat(results, "")
    return final_str, highlights
  end

  ---@param entry NodeLevel
  return function(entry)
    local node = entry.node

    return {
      value = node,
      tree_state = entry.tree_state,
      display = make_display,
      ordinal = "", -- No need for this as we're not filtering the treeview
      filename = node.filename,
      lnum = node.lnum,
      col = node.col,
    }
  end
end

M.show_hierarchy = function(results, opts)
  opts = theme.apply(opts or {})

  pickers
    .new(opts, {
      results_title = "Incoming Calls",
      prompt_title = "",
      preview_title = "Preview",
      finder = finders.new_table({
        results = results,
        entry_maker = gen_make_entry(opts),
      }),
      -- No need for a sorter as the tree-view shouldn't be filtered
      -- sorter = conf.generic_sorter(opts),
      previewer = conf.qflist_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        for _, mode in pairs({ "i", "n" }) do
          for key, action in pairs(opts.mappings[mode] or {}) do
            map(mode, key, action(prompt_bufnr))
          end
        end
        return true -- include defaults as well
      end,
    })
    :find()
end

return M
