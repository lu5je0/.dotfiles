local common_ui = require('lu5je0.ext.git.common.ui')
local statusline = require('lu5je0.ext.git.common.statusline')

local M = {}

local ns_id = vim.api.nvim_create_namespace('git_project_log')

vim.api.nvim_set_hl(0, 'GitProjectLogGraph', { link = 'Special', default = true })

vim.api.nvim_set_hl(0, 'GitGraphRed', { fg = '#e06c75', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphYellow', { fg = '#e5c07b', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphBlue', { fg = '#61afef', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphPurple', { fg = '#c678dd', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphCyan', { fg = '#56b6c2', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphBoldRed', { fg = '#e06c75', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphBoldYellow', { fg = '#e5c07b', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphBoldBlue', { fg = '#61afef', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphBoldPurple', { fg = '#c678dd', bold = true, default = true })
vim.api.nvim_set_hl(0, 'GitGraphBoldCyan', { fg = '#56b6c2', bold = true, default = true })

M.set_buffer_lines = common_ui.set_buffer_lines
M.build_file_tree_entries = common_ui.build_file_tree_entries
M.highlight_tree_entry = common_ui.highlight_tree_entry

local function format_commit_line(commit, graph_text)
  if commit.local_change then
    return string.format('%s %s %s', commit.short_hash, commit.date, commit.message)
  end
  local graph_str = graph_text or ''
  if graph_str ~= '' then
    graph_str = graph_str .. ' '
  end
  return string.format('%s %s%s %s %s', commit.short_hash, graph_str, commit.date, commit.author, commit.message)
end

local function format_connector_line(graph_text, pad_len)
  return string.rep(' ', pad_len) .. graph_text
end

local function apply_graph_hl(buf, line_idx, hl, offset)
  for _, h in ipairs(hl) do
    vim.api.nvim_buf_add_highlight(buf, ns_id, h[3], line_idx, offset + h[1], offset + h[2])
  end
end

local function highlight_commit_line(buf, line_idx, line, commit, graph_text, graph_hl)
  local short_hash = commit and commit.short_hash or ''
  local hash_end = #short_hash
  vim.api.nvim_buf_add_highlight(buf, ns_id, 'Number', line_idx, 0, hash_end)

  local graph_end = hash_end + 1
  if graph_text and graph_text ~= '' then
    apply_graph_hl(buf, line_idx, graph_hl, hash_end + 1)
    graph_end = hash_end + 1 + #graph_text + 1
  end

  local date_end = graph_end + 19
  if #line >= date_end then
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'Comment', line_idx, graph_end, date_end)
  end
end

function M.render_log(state)
  if not state.log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end

  local lines = {}
  local items = {}
  local graph_rows = state.graph_rows

  if graph_rows and #graph_rows > 0 then
    local hash_len = 8
    for _, c in ipairs(state.commits) do
      if not c.local_change then
        hash_len = #c.short_hash
        break
      end
    end
    local pad_len = hash_len + 1

    local first_commit = state.commits[1]
    if first_commit and first_commit.local_change then
      lines[#lines + 1] = format_commit_line(first_commit, nil)
      items[#items + 1] = { type = 'commit', commit_idx = 1 }
      if first_commit.expanded then
        common_ui.append_tree_entries(lines, items, first_commit, 1, {
          tree_opts = { status_hl_fn = function() return 'Type' end },
        })
      end
    end

    for _, grow in ipairs(graph_rows) do
      if grow.commit_idx then
        local commit = state.commits[grow.commit_idx]
        lines[#lines + 1] = format_commit_line(commit, grow.text)
        items[#items + 1] = { type = 'commit', commit_idx = grow.commit_idx, graph_text = grow.text, graph_hl = grow.hl }
        if commit.expanded then
          common_ui.append_tree_entries(lines, items, commit, grow.commit_idx, {
            tree_opts = { status_hl_fn = function() return 'Type' end },
          })
        end
      else
        lines[#lines + 1] = format_connector_line(grow.text, pad_len)
        items[#items + 1] = { type = 'connector', graph_hl = grow.hl, pad_len = pad_len }
      end
    end
  else
    for commit_idx, commit in ipairs(state.commits) do
      lines[#lines + 1] = format_commit_line(commit, nil)
      items[#items + 1] = { type = 'commit', commit_idx = commit_idx }
      if commit.expanded then
        common_ui.append_tree_entries(lines, items, commit, commit_idx, {
          tree_opts = { status_hl_fn = function() return 'Type' end },
        })
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
      local commit = state.commits[item.commit_idx]
      if commit and commit.local_change then
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Special', idx - 1, 0, -1)
      else
        highlight_commit_line(state.log_buf, idx - 1, lines[idx], commit, item.graph_text, item.graph_hl or {})
      end
    elseif item.type == 'connector' then
      apply_graph_hl(state.log_buf, idx - 1, item.graph_hl, item.pad_len)
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
  if loading then
    vim.wo[state.log_win].statusline = statusline.log_count('Project Log', 0, 'commits', { loading = true })
  else
    local commit_count = 0
    for _, commit in ipairs(state.commits) do
      if not commit.local_change then
        commit_count = commit_count + 1
      end
    end
    vim.wo[state.log_win].statusline = statusline.log_count('Project Log', commit_count, 'commits', {
      limited = state.limited,
    })
  end
end

return M
