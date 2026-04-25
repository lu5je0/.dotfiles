local common_ui = require('lu5je0.ext.git.common.ui')

local M = {}

local ns_id = vim.api.nvim_create_namespace('git_project_log')

vim.api.nvim_set_hl(0, 'GitProjectLogGraph', { link = 'Special', default = true })

-- re-export common helpers used by other project-log modules
M.set_buffer_lines = common_ui.set_buffer_lines
M.build_file_tree_entries = common_ui.build_file_tree_entries
M.highlight_tree_entry = common_ui.highlight_tree_entry

local function format_commit_line(commit)
  if commit.local_change then
    return string.format('%s %s %s', commit.short_hash, commit.date, commit.message)
  end
  local graph = commit.graph and commit.graph ~= '' and (commit.graph .. ' ') or ''
  return string.format('%s %s%s %s %s', commit.short_hash, graph, commit.date, commit.author, commit.message)
end

local function highlight_commit_line(buf, line_idx, line, commit)
  local graph = commit and commit.graph or ''
  local short_hash = commit and commit.short_hash or ''
  local hash_end = #short_hash
  vim.api.nvim_buf_add_highlight(buf, ns_id, 'Number', line_idx, 0, hash_end)
  local graph_start = hash_end + 1
  if graph ~= '' then
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'GitProjectLogGraph', line_idx, graph_start, graph_start + #graph)
    graph_start = graph_start + #graph + 1
  end
  local date_end = graph_start + 19
  if #line >= date_end then
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'Comment', line_idx, graph_start, date_end)
  end
end

function M.render_log(state)
  if not state.log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end

  local lines = {}
  local items = {}
  for commit_idx, commit in ipairs(state.commits) do
    lines[#lines + 1] = format_commit_line(commit)
    items[#items + 1] = { type = 'commit', commit_idx = commit_idx }
    if commit.expanded then
      for _, entry in ipairs(common_ui.build_file_tree_entries(commit)) do
        lines[#lines + 1] = entry.line
        if entry.type == 'file' then
          items[#items + 1] = { type = 'file', commit_idx = commit_idx, file_idx = entry.file_idx, tree_entry = entry }
        else
          items[#items + 1] = { type = 'dir', commit_idx = commit_idx, dir_path = entry.dir_path, tree_entry = entry }
        end
      end
    end
  end

  if #lines == 0 then
    lines = { '-- No commits found --' }
  end

  common_ui.set_buffer_lines(state.log_buf, lines)
  vim.api.nvim_buf_clear_namespace(state.log_buf, ns_id, 0, -1)
  for idx, item in ipairs(items) do
    if item.type == 'commit' then
      if state.commits[item.commit_idx] and state.commits[item.commit_idx].local_change then
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Special', idx - 1, 0, -1)
      else
        highlight_commit_line(state.log_buf, idx - 1, lines[idx], state.commits[item.commit_idx])
      end
    elseif item.tree_entry then
      common_ui.highlight_tree_entry(state.log_buf, idx - 1, item.tree_entry)
    end
  end
  state.display_items = items
end

function M.update_statusline(state, loading)
  if not state.log_win or not vim.api.nvim_win_is_valid(state.log_win) then
    return
  end
  local mode = string.format('%s%s', state.diff_mode, state.diff_changes_only and ' changes-only' or '')
  if loading then
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Project Log%%* [%%#Special#loading%%*] %%#Comment#%s%%*', mode)
  elseif state.limited then
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Project Log%%* %%#Number#%d commits%%* %%#WarningMsg#(limited)%%* %%#Comment#%s%%*', #state.commits, mode)
  else
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Project Log%%* %%#Number#%d commits%%* %%#Comment#%s%%*', #state.commits, mode)
  end
end

return M
