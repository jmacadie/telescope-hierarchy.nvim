local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local strings = require("plenary.strings")

local theme = require("telescope-hierarchy.theme")
local state = require("telescope-hierarchy.state")

local M = {}

---A higher-ordered function, a function that returns a function
---This follows the pattern set out in "Telescope.make_entry" in that we contain all the
---logic for rendering a single row into a function.
---The higher-ordered function pattern is useful to 'cache' computation that applies to
---all rows and only needs to be done once per render cycle.
---Looking through the code, I'm not actually sure that this is so applicable to the code
---I have written: oops! It works better with "telescope.pickers.entry_display.create()"
---which sets up the fixed info for the layout of columns and their highlighting once at
---the start of the render cycle. We can't take advantage of that here as the variable
---size of the tree we need to render at the start of the row means we do not want to use
---a fixed column layout
---@param opts table
---@return fun(entry: NodeLevel) table
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
  local function make_suffix(node)
    if node.cache.searched == "No" then
      return "? "
    end

    if node.cache.searched == "Pending" then
      return " "
    end

    if node.recursive then
      return "  "
    end

    assert(node.cache.searched == "Yes")
    local ref = assert(node.cache.searched_node)
    local count = #ref.children
    if count == 0 then
      return "(none) "
    end

    if not node.expanded then
      return "(" .. count .. ") "
    end

    return ""
  end

  ---@alias HighlightEntry [[integer, integer], string]

  ---@param results string[] A table holding the parts of the ultimate display string
  ---@param highlights HighlightEntry[] The highlights table that is being appended to
  ---@param start integer The current position in the display string
  ---@param text string|integer The text to be added to the display result & the highlight is being applied to
  ---@param hl string The highlight to be applied
  ---@return integer new_pos The new position in the display string
  local function add_part(results, highlights, start, text, hl)
    text = tostring(text) -- convert numbers to strings
    table.insert(results, text)
    local len = text:len()
    local new_pos = start + len
    ---@type HighlightEntry
    local highlight = { { start, new_pos }, hl }
    table.insert(highlights, highlight)
    return new_pos
  end

  ---Calculate the available width of the results window
  ---@param picker Picker
  ---@return integer
  local function results_width(picker)
    -- LSP doesn't like the call to selection_caret, which is in the metatable
    ---@diagnostic disable-next-line:undefined-field
    return vim.api.nvim_win_get_width(picker.results_win) - #picker.selection_caret
  end

  ---Compute a filemame that is padded and trimmed such that it is rendered right-justified
  ---in the results window. The trimming will occur if the filename (which includes the full path)
  ---would overflow the available space in the results window. If that is the case, we left trim
  ---on the basis that the right hand end of the filepath is the most interesting to users
  ---@param width integer The avialable width of the results window
  ---@param results string[] The text of the LHS of the result for this row, which will take precedence over any filename that is shown
  ---@param filename string The filename and path that is being trimmed and justified
  ---@return string
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

  ---@class Entry
  ---@field value Node
  ---@field tree_state boolean[]
  ---@field ordinal string
  ---@field filename string
  ---@field lnum integer
  ---@field col integer

  ---Main UI rendering function that is used by the picker to render each row in the finder window
  ---It is the equivalant of the functions in "telescope.make_entry". I had to roll my own as the
  ---Telescope built in functions are focussed on displaying things in columns but the varying
  ---length of the tree rendered on the left hand side of the row means that this is not a good
  ---pattern for this add-in
  ---@param entry Entry
  ---@param picker Picker
  ---@return string final_str The text to be show in the results window for the row
  ---@return HighlightEntry[] highlights A table of highlights
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
    position = add_part(results, highlights, position, make_suffix(node), "TelescopeResultsComment")
    position = add_part(results, highlights, position, "     ", "")

    local formatted_fname = padded_filename(width, results, entry.filename)
    position = add_part(results, highlights, position, formatted_fname, "TelescopeResultsLineNr")
    position = add_part(results, highlights, position, ":", "TelescopeResultsMethod")
    _ = add_part(results, highlights, position, entry.lnum, "TelescopeResultsLineNr")

    local final_str = table.concat(results, "")
    return final_str, highlights
  end

  ---@param entry NodeLevel
  ---@return table
  local function output(entry)
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

  return output
end

---Convert the Tree direction into a display title for the Results window
---@return string
M.title = function()
  local direction = assert(state.direction())
  return direction:is_incoming() and "Incoming Calls" or "Outgoing Calls"
end

---Show the Telescope UI based on the current tree.
---The tree is processed in `Node:to_list()` to convert the nested tree structure
---into a list format that Telescope can consume
---@param results NodeList
---@param opts table
M.show = function(results, opts)
  if #results == 0 then
    return
  end

  opts = theme.apply(opts or {})

  pickers
    .new(opts, {
      results_title = M.title(),
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
