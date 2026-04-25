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

local function render_log(state)
  state.render(state)
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
      render_log(state)
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
    render_log(state)
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
      render_log(state)
      set_cursor_line(state, line)
      return true
    end
    return false
  end

  local entry = item.tree_entry
  if item.type == 'dir' and entry and commit.expanded_dirs[entry.dir_path] then
    commit.expanded_dirs[entry.dir_path] = nil
    render_log(state)
    focus_dir(state, item.commit_idx, entry.dir_path)
    return true
  end

  local parent_dir = entry and entry.parent_dir
  if parent_dir and parent_dir ~= '.' and commit.expanded_dirs[parent_dir] then
    commit.expanded_dirs[parent_dir] = nil
    render_log(state)
    focus_dir(state, item.commit_idx, parent_dir)
    return true
  end

  if commit.expanded then
    commit.expanded = false
    render_log(state)
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
    render_log(state)
  end
  focus_commit(state, item.commit_idx)
  return true
end

return M
