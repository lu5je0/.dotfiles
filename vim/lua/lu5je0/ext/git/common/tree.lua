local common_ui = require('lu5je0.ext.git.common.ui')

local M = {}

function M.item_under_cursor(state)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
    return nil
  end
  return state.display_items[vim.api.nvim_win_get_cursor(state.log_win)[1]]
end

local function current_line(state)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
    return 1
  end
  return vim.api.nvim_win_get_cursor(state.log_win)[1]
end

local function set_cursor_line(state, line)
  if state.log_win and vim.api.nvim_win_is_valid(state.log_win) then
    vim.api.nvim_win_set_cursor(state.log_win, { math.min(line, vim.api.nvim_buf_line_count(state.log_buf)), 0 })
  end
end

local function find_item_line(state, predicate)
  for line, item in ipairs(state.display_items) do
    if predicate(item) then
      return line
    end
  end
  return nil
end

local function focus_commit(state, commit_idx)
  local line = find_item_line(state, function(item)
    return item.type == 'commit' and item.commit_idx == commit_idx
  end)
  if line then
    set_cursor_line(state, line)
  end
end

local function focus_dir(state, commit_idx, dir_path)
  local line = find_item_line(state, function(item)
    return item.type == 'dir' and item.commit_idx == commit_idx and item.dir_path == dir_path
  end)
  if line then
    set_cursor_line(state, line)
  else
    focus_commit(state, commit_idx)
  end
end

local function focus_first_child(state, commit_idx)
  local commit_line = find_item_line(state, function(item)
    return item.type == 'commit' and item.commit_idx == commit_idx
  end)
  local child = commit_line and state.display_items[commit_line + 1] or nil
  if child and child.commit_idx == commit_idx and child.type ~= 'commit' then
    set_cursor_line(state, commit_line + 1)
  else
    focus_commit(state, commit_idx)
  end
end

local function expand_all_dirs(commit)
  commit.expanded_dirs = {}
  for _, file in ipairs(commit.files or {}) do
    local parts = vim.split(file.path or '', '/', { plain = true, trimempty = true })
    local dir_parts = {}
    for i = 1, #parts - 1 do
      dir_parts[#dir_parts + 1] = parts[i]
      commit.expanded_dirs[table.concat(dir_parts, '/')] = true
    end
  end
end

M.expand_all_dirs = expand_all_dirs

-- Find commit line by scanning backwards from a given position (1-based)
local function find_commit_line_from(state, from_line)
  for i = from_line, 1, -1 do
    local item = state.display_items[i]
    if item and item.type == 'commit' then
      return i
    end
  end
  return nil
end

-- Count tree items (file/dir) belonging to a commit after its commit line
local function count_tree_items(state, commit_line)
  local commit_idx = state.display_items[commit_line].commit_idx
  local count = 0
  for i = commit_line + 1, #state.display_items do
    local item = state.display_items[i]
    if item.commit_idx ~= commit_idx or item.type == 'commit' then
      break
    end
    count = count + 1
  end
  return count
end

-- Incrementally replace tree entries for a single commit.
-- Only regenerates the affected commit's file tree instead of the entire buffer.
local function refresh_commit_tree(state, commit_line)
  if not state.log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end

  local commit_item = state.display_items[commit_line]
  local commit_idx = commit_item.commit_idx
  local commit = state.commits[commit_idx]

  local old_count = count_tree_items(state, commit_line)

  local new_lines = {}
  local new_items = {}
  if commit.expanded then
    local prefix = commit.child_prefix or ''
    local tree_opts = commit.tree_opts or state.tree_opts
    common_ui.append_tree_entries(new_lines, new_items, commit, commit_idx, {
      prefix = prefix,
      tree_opts = tree_opts,
    })
  end

  -- Replace buffer lines: tree occupies 0-based [commit_line, commit_line + old_count)
  vim.bo[state.log_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.log_buf, commit_line, commit_line + old_count, false, new_lines)
  vim.bo[state.log_buf].modifiable = false

  -- Splice display_items: replace items (commit_line+1)..(commit_line+old_count) with new_items
  local old = state.display_items
  local result = {}
  for i = 1, commit_line do
    result[#result + 1] = old[i]
  end
  for i = 1, #new_items do
    result[#result + 1] = new_items[i]
  end
  for i = commit_line + old_count + 1, #old do
    result[#result + 1] = old[i]
  end
  state.display_items = result

  -- Highlight only the new tree lines
  for i = 1, #new_items do
    if new_items[i].tree_entry then
      common_ui.highlight_tree_entry(state.log_buf, commit_line + i - 1, new_items[i].tree_entry, new_items[i].indent)
    end
  end
end

function M.open_node(state)
  local item = M.item_under_cursor(state)
  if not item then
    return false
  end

  local line = current_line(state)
  if item.type == 'commit' then
    local commit = state.commits[item.commit_idx]
    if not commit then
      return false
    end
    if not commit.expanded then
      commit.expanded = true
      expand_all_dirs(commit)
      refresh_commit_tree(state, line)
    end
    focus_first_child(state, item.commit_idx)
    return true
  elseif item.type == 'dir' then
    local commit = state.commits[item.commit_idx]
    local entry = item.tree_entry
    if not commit or not entry or not entry.has_children then
      return false
    end
    commit.expanded_dirs[entry.dir_path] = true
    local commit_line = find_commit_line_from(state, line)
    refresh_commit_tree(state, commit_line)
    set_cursor_line(state, line + 1)
    return true
  end

  return false
end

function M.close_parent_node(state)
  local item = M.item_under_cursor(state)
  if not item then
    return false
  end

  local line = current_line(state)
  local commit = state.commits[item.commit_idx]
  if not commit then
    return false
  end

  if item.type == 'commit' then
    if commit.expanded then
      commit.expanded = false
      refresh_commit_tree(state, line)
      set_cursor_line(state, line)
      return true
    end
    return false
  end

  local commit_line = find_commit_line_from(state, line)
  if not commit_line then
    return false
  end

  local entry = item.tree_entry
  if item.type == 'dir' and entry and commit.expanded_dirs[entry.dir_path] then
    commit.expanded_dirs[entry.dir_path] = nil
    refresh_commit_tree(state, commit_line)
    focus_dir(state, item.commit_idx, entry.dir_path)
    return true
  end

  local parent_dir = entry and entry.parent_dir
  if parent_dir and parent_dir ~= '.' and commit.expanded_dirs[parent_dir] then
    commit.expanded_dirs[parent_dir] = nil
    refresh_commit_tree(state, commit_line)
    focus_dir(state, item.commit_idx, parent_dir)
    return true
  end

  if commit.expanded then
    commit.expanded = false
    refresh_commit_tree(state, commit_line)
    focus_commit(state, item.commit_idx)
    return true
  end

  return false
end

function M.close_commit_node(state)
  local item = M.item_under_cursor(state)
  if not item then
    return false
  end

  local commit = state.commits[item.commit_idx]
  if not commit then
    return false
  end

  if commit.expanded then
    commit.expanded = false
    local commit_line = find_commit_line_from(state, current_line(state))
    if commit_line then
      refresh_commit_tree(state, commit_line)
    end
  end
  focus_commit(state, item.commit_idx)
  return true
end

return M
