local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local conf = require("telescope.config").values
local strings = require("plenary.strings")
local util = require("telescope.utils")

local theme = require("telescope-hierarchy.theme")
local state = require("telescope-hierarchy.state")
local Path = require("plenary.path")

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
  ---Includes logic to flag
  --- - if the node has not yet been searched (?)
  --- - if the node is currently being searched and we are waiting for the LSP to return ( )
  --- - if the node is recursive, in which case this node will not be expanded further ( )
  --- - if the node has been searched and has no children (none)
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

  ---@param results string[] A list holding the parts of the ultimate display string
  ---@param highlights HighlightEntry[] The highlights list that is being appended to. This list gets mutated in place
  ---@param start integer The current position in the display string
  ---@param text string|integer The text to be added to the display result & the highlight is being applied to
  ---@param hl string The highlight to be applied
  ---@return integer new_pos The new position in the display string
  local function add_part(results, highlights, start, text, hl)
    text = tostring(text) -- convert numbers to strings
    table.insert(results, text)
    local len = text:len()
    local new_pos = start + len
    table.insert(highlights, { { start, new_pos }, hl })
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
  ---@field index integer

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

    local formatted_fname = padded_filename(width, results, Path:new(entry.filename):normalize(vim.uv.cwd()))
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
      ordinal = "", -- We don't actually use this as we either don't filter the tree or if we do it is on display text only
      filename = node.filename,
      lnum = node.lnum,
      col = node.col,
    }
  end

  return output
end

---Function to make a new Sorter for the Picker
---The job of the sorter is to sort and filter the results of the Picker
---In our case we don't want to change the sort order but we do want to filter down to
---matching hierarchy paths that contain the searched for words in the prompt
---@param opts table The opts table for the plugin
---@return Sorter
local function get_sorter(opts)
  -- Both match and highlighter are based on the telescope.sorters.get_substr_matcher.
  -- The main distinction is these only operate on the text provided, not the
  -- ordinal from the entry.

  -- match on substrings of any of the words in the prompt.
  --
  -- TODO: It would be nice to use the fuzzy sorter, but i found it to be
  -- unintuitive as it would often match unrelated parent nodes of the tree
  -- when you are trying to filter by a specific child symbol in a different
  -- branch of the tree.
  --
  -- Additionally, this matches on any word, in any order. So the search behavior of words is basically logical "OR".
  -- Ideally, a word later in the prompt would be refining based on words earlier in the prompt.
  ---@param prompt string The user-entered prompt. Used to filter the results in the picker window
  ---@param line string A line from the picker i.e. a method name and a filename
  ---@return boolean match Did the line match the prompt? true means the line will be shown, false means the line will be filtered out
  local match = function(prompt, line)
    -- Split the prompt into words and check if any are in the line
    local search_terms = util.max_split(prompt, "%s")
    for _, word in pairs(search_terms) do
      if line:lower():find(word:lower(), 1, true) then
        return true
      end
    end
    return false
  end

  ---Highlight substrings of any of the words in the prompt
  ---@param _ Sorter Not used in this implementation. Required because Telescope calls highlighter using the colon sytax
  ---@param prompt string
  ---@param display string
  ---@return table
  local highlighter = function(_, prompt, display)
    local highlights = {}
    local search_terms = util.max_split(prompt, "%s")
    local hl_start, hl_end

    for _, word in pairs(search_terms) do
      hl_start, hl_end = display:lower():find(word:lower(), 1, true)
      if hl_start then
        table.insert(highlights, { start = hl_start, finish = hl_end })
      end
    end

    return highlights
  end

  local FILTERED = -1
  local RETAIN = 1

  ---This filter function filters out any entries that do not match the
  ---prompt, and preserves the original entry ordering otherwise.
  ---The return integer should be -1 to filter and any other number to keep. We use 1.
  ---The filter function also passes back the prompt, which we do not touch
  ---@param _ Sorter Not used in this implementation. Required because Telescope calls filter using the colon sytax
  ---@param prompt string The current user-entered prompt, which will determine what gets filtered
  ---@param entry Entry The entry that _might_ get filtered
  ---@return integer filter_state, string prompt
  local function filter(_, prompt, entry)
    if prompt == "" then
      return RETAIN, prompt
    end

    local node = entry.value

    -- If the prompt matches the node text include it
    if match(prompt, node.text) then
      return RETAIN, prompt
    end

    -- If the prompt matches any of the node's children's text include it as well
    local found = false
    ---Function used to recursively search child nodes for any matches
    ---This allows the tree of parent call dependencies to be retained
    ---If we return true the recursive search will be terminated
    ---@param child Node
    ---@return boolean terminate
    local function find_related_node(child)
      if match(prompt, child.text) then
        found = true
        return true
      end
      return false
    end
    node:walk_children(find_related_node)
    if found then
      return RETAIN, prompt
    end

    -- If the setting to include all children of a matched node is set then
    -- walk the parents to look for matches too
    if opts.filter_include_children then
      found = false
      node:walk_parents(find_related_node)
      if found then
        return RETAIN, prompt
      end
    end

    -- If neither the node, nor any of its children match then filter out
    return FILTERED, prompt
  end

  return sorters.Sorter:new({
    filter_function = filter,
    -- Taken from Telescope.sorters.empty
    scoring_function = function()
      return RETAIN
    end,
    highlighter = highlighter,
  })
end

---Convert the Tree direction, which is part of Global state, into a display title for the Results window
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
---@return Picker | nil
M.show = function(results, opts)
  if #results == 0 then
    return
  end

  opts = theme.apply(opts or {})

  -- Only provide the filter mode sorter if it is opted into
  local sorter = opts.filter_mode and get_sorter(opts) or nil
  -- Don't overwrite the user's input configs if they have provided
  if not opts.initial_mode then
    -- Start in insert mode if filter_mode and filter_start_insert are both true
    -- Otherwise start in normal mode
    opts.initial_mode = (opts.filter_mode and opts.filter_start_insert) and "insert" or "normal"
  end

  local picker = pickers.new(opts, {
    results_title = M.title(),
    prompt_title = "",
    preview_title = "Preview",
    finder = finders.new_table({
      results = results,
      entry_maker = gen_make_entry(opts),
    }),
    sorter = sorter,
    previewer = opts.previewer or conf.qflist_previewer(opts),
    attach_mappings = function(prompt_bufnr, map)
      for _, mode in pairs({ "i", "n" }) do
        for key, action in pairs(opts.mappings[mode] or {}) do
          map(mode, key, action(prompt_bufnr))
        end
      end
      return true -- include defaults as well
    end,
  })

  picker:find()
  return picker
end

---Refresh the picker, for use after the nodes tree has been updated
---@param node Node
---@param picker Picker
---@param keep_selection? boolean Retain the current selection after refresh. If ommitted will assume true
M.refresh = function(node, picker, keep_selection)
  local new_finder = finders.new_table({
    results = node:to_list(),
    -- Lua LS doesn't like entry_maker field of finder
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

return M
