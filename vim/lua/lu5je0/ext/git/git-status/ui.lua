local common_ui = require('lu5je0.ext.git.common.ui')

local M = {}

local ns_id = vim.api.nvim_create_namespace('git_status')

local section_icons = {
  untracked = { icon = '◌ ', hl = 'Comment' },
  unstaged = { icon = ' ', hl = 'Structure' },
  staged = { icon = ' ', hl = 'Green' },
  stash = { icon = ' ', hl = 'Comment' },
}

M.section_labels = {
  untracked = 'Untracked',
  unstaged = 'Unstaged',
  staged = 'Staged',
}

M.section_order = { 'untracked', 'unstaged', 'staged' }

-- Fugitive-style per-section status highlights:
--   Untracked -> StorageClass, Unstaged -> Structure, Staged -> Typedef, Stash -> Type
local section_status_hl = {
  untracked = 'StorageClass',
  unstaged = 'Structure',
  staged = 'Typedef',
  stash = 'Type',
}

local function make_status_hl_fn(section)
  local hl = section_status_hl[section] or 'Type'
  return function()
    return hl
  end
end

function M.make_tree_opts(section)
  return { status_hl_fn = make_status_hl_fn(section) }
end

function M.render(state)
  if not state.log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end

  local lines = {}
  local items = {}

  -- header
  lines[#lines + 1] = 'Head:   ' .. (state.head or '')
  items[#items + 1] = { type = 'header' }
  lines[#lines + 1] = 'Merge:  ' .. (state.merge or '')
  items[#items + 1] = { type = 'header' }
  lines[#lines + 1] = ''
  items[#items + 1] = { type = 'header' }
  state.header_count = #lines

  -- separate normal sections and stash sections
  local normal_commits = {}
  local stash_commits = {}
  for commit_idx, commit in ipairs(state.commits) do
    if commit.section == 'stash' then
      stash_commits[#stash_commits + 1] = { commit_idx = commit_idx, commit = commit }
    else
      normal_commits[#normal_commits + 1] = { commit_idx = commit_idx, commit = commit }
    end
  end

  -- render normal sections
  for _, entry in ipairs(normal_commits) do
    local commit_idx = entry.commit_idx
    local commit = entry.commit
    local label = M.section_labels[commit.section] or commit.section
    local si = section_icons[commit.section]
    local icon = si and si.icon or ''
    lines[#lines + 1] = string.format('%s%s (%d)', icon, label, #commit.files)
    items[#items + 1] = { type = 'commit', commit_idx = commit_idx, section = commit.section }

    if commit.expanded then
      common_ui.append_tree_entries(lines, items, commit, commit_idx, {
        tree_opts = { status_hl_fn = make_status_hl_fn(commit.section) },
      })
    end

    lines[#lines + 1] = ''
    items[#items + 1] = { type = 'blank' }
  end

  -- render stash section
  local stash_si = section_icons.stash
  local stash_icon = stash_si and stash_si.icon or ''
  if #stash_commits > 0 then
    lines[#lines + 1] = string.format('%sStashes (%d)', stash_icon, #stash_commits)
    items[#items + 1] = { type = 'stash_header' }

    for si, entry in ipairs(stash_commits) do
      local commit_idx = entry.commit_idx
      local commit = entry.commit
      local is_last = si == #stash_commits
      local branch = is_last and '└ ' or '│ '
      local child_prefix = is_last and '  ' or '│ '

      commit.child_prefix = child_prefix

      lines[#lines + 1] = string.format('%s%s%s (%d)', branch, stash_icon, commit.stash_label, #commit.files)
      items[#items + 1] = { type = 'commit', commit_idx = commit_idx, stash = true }

      if commit.expanded then
        common_ui.append_tree_entries(lines, items, commit, commit_idx, {
          prefix = child_prefix,
          tree_opts = { status_hl_fn = make_status_hl_fn('stash') },
        })
      end
    end
  end

  -- remove trailing blank
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
    table.remove(items)
  end

  common_ui.set_buffer_lines(state.log_buf, lines)

  -- highlights
  local stash_icon_hl = stash_si and stash_si.hl or 'Special'
  vim.api.nvim_buf_clear_namespace(state.log_buf, ns_id, 0, -1)
  for idx, item in ipairs(items) do
    local li = idx - 1
    if item.type == 'header' then
      local line = lines[idx]
      local colon = line:find(':', 1, true)
      if colon then
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, 0, colon - 1)
        local value_start = line:find('%S', colon + 1)
        if value_start then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Function', li, value_start - 1, -1)
        end
      end
    elseif item.type == 'stash_header' then
      local cline = lines[idx]
      local icon_len = #stash_icon
      vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, stash_icon_hl, li, 0, icon_len)
      local paren_start = cline:find('%(')
      if paren_start then
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, icon_len, paren_start - 2)
        local num_end = cline:find('%)', paren_start)
        if num_end then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Number', li, paren_start, num_end - 1)
        end
      else
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, icon_len, -1)
      end
    elseif item.type == 'commit' then
      local cline = lines[idx]
      local paren_start = cline:find('%(')
      if item.stash then
        -- stash entry: highlight branch chars as tree line, icon, and count
        local icon_start = cline:find(stash_icon, 1, true)
        if icon_start then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'GitTreeLine', li, 0, icon_start - 1)
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, stash_icon_hl, li, icon_start - 1, icon_start - 1 + #stash_icon)
        end
        if paren_start then
          local num_end = cline:find('%)', paren_start)
          if num_end then
            vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Number', li, paren_start, num_end - 1)
          end
        end
      else
        local sec_si = section_icons[item.section]
        local icon_len = sec_si and #sec_si.icon or 0
        local icon_hl = sec_si and sec_si.hl or 'Label'
        if icon_len > 0 then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, icon_hl, li, 0, icon_len)
        end
        if paren_start then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, icon_len, paren_start - 2)
          local num_end = cline:find('%)', paren_start)
          if num_end then
            vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Number', li, paren_start, num_end - 1)
          end
        else
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, icon_len, -1)
        end
      end
    elseif item.tree_entry then
      common_ui.highlight_tree_entry(state.log_buf, li, item.tree_entry, item.indent)
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
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Git Status%%* [%%#Special#loading%%*] %%#Comment#%s%%*', mode)
  else
    local total = 0
    for _, c in ipairs(state.commits) do
      if c.section ~= 'stash' then
        total = total + #c.files
      end
    end
    vim.wo[state.log_win].statusline = string.format(' %%#Function#Git Status%%* %%#Number#%d changes%%* %%#Comment#%s%%*', total, mode)
  end
end

return M
