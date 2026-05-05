local common_ui = require('lu5je0.ext.git.common.ui')

local M = {}

local ns_id = vim.api.nvim_create_namespace('git_status')

local fold_icon_hl = 'Number'

local function fold_icon(expanded)
  return expanded and ' ' or ' '
end

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
    local icon = fold_icon(commit.expanded)
    lines[#lines + 1] = string.format('%s%s (%d)', icon, label, #commit.files)
    items[#items + 1] = { type = 'commit', commit_idx = commit_idx, section = commit.section, fold_icon = icon }

    if commit.expanded then
      common_ui.append_tree_entries(lines, items, commit, commit_idx, {
        tree_opts = { status_hl_fn = make_status_hl_fn(commit.section) },
      })
    end

    lines[#lines + 1] = ''
    items[#items + 1] = { type = 'blank' }
  end

  -- render stash section
  if #stash_commits > 0 then
    local stash_header_icon = fold_icon(state.stash_expanded ~= false)
    lines[#lines + 1] = string.format('%sStashes (%d)', stash_header_icon, #stash_commits)
    items[#items + 1] = { type = 'stash_header', fold_icon = stash_header_icon }

    if state.stash_expanded ~= false then
      for si, entry in ipairs(stash_commits) do
        local commit_idx = entry.commit_idx
        local commit = entry.commit
        local is_last = si == #stash_commits
        local branch = is_last and '└ ' or '│ '
        local child_prefix = is_last and '  ' or '│ '
        local icon = fold_icon(commit.expanded)

        commit.child_prefix = child_prefix

        local count_str = commit.files_loaded and string.format(' (%d)', #commit.files) or ''
        lines[#lines + 1] = string.format('%s%s%s%s', branch, icon, commit.stash_label, count_str)
        items[#items + 1] = {
          type = 'commit',
          commit_idx = commit_idx,
          stash = true,
          branch = branch,
          fold_icon = icon,
        }

        if commit.expanded then
          common_ui.append_tree_entries(lines, items, commit, commit_idx, {
            prefix = child_prefix,
            tree_opts = { status_hl_fn = make_status_hl_fn('stash') },
          })
        end
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
      local icon_len = #(item.fold_icon or '')
      vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, fold_icon_hl, li, 0, icon_len)
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
        local icon = item.fold_icon or ''
        local icon_start = icon ~= '' and cline:find(icon, 1, true) or nil
        if icon_start then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'GitTreeLine', li, 0, icon_start - 1)
          vim.api.nvim_buf_add_highlight(
            state.log_buf,
            ns_id,
            fold_icon_hl,
            li,
            icon_start - 1,
            icon_start - 1 + #icon
          )
        end
        if paren_start then
          local num_end = cline:find('%)', paren_start)
          if num_end then
            vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Number', li, paren_start, num_end - 1)
          end
        end
      else
        local icon_len = #(item.fold_icon or '')
        if icon_len > 0 then
          vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, fold_icon_hl, li, 0, icon_len)
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

function M.refresh_commit_line(state, line)
  if not state.log_buf or not vim.api.nvim_buf_is_valid(state.log_buf) then
    return
  end
  local item = state.display_items and state.display_items[line]
  if not item or item.type ~= 'commit' then
    return
  end
  local commit = state.commits[item.commit_idx]
  if not commit then
    return
  end

  local icon = fold_icon(commit.expanded)
  item.fold_icon = icon

  local text
  if item.stash then
    local count_str = commit.files_loaded and string.format(' (%d)', #commit.files) or ''
    text = string.format('%s%s%s%s', item.branch or '', icon, commit.stash_label, count_str)
  else
    local label = M.section_labels[commit.section] or commit.section
    text = string.format('%s%s (%d)', icon, label, #commit.files)
  end

  vim.bo[state.log_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.log_buf, line - 1, line, false, { text })
  vim.bo[state.log_buf].modifiable = false

  local li = line - 1
  local paren_start = text:find('%(')
  vim.api.nvim_buf_clear_namespace(state.log_buf, ns_id, li, line)
  if item.stash then
    local icon_start = text:find(icon, 1, true)
    if icon_start then
      vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'GitTreeLine', li, 0, icon_start - 1)
      vim.api.nvim_buf_add_highlight(
        state.log_buf,
        ns_id,
        fold_icon_hl,
        li,
        icon_start - 1,
        icon_start - 1 + #icon
      )
    end
    if paren_start then
      local num_end = text:find('%)', paren_start)
      if num_end then
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Number', li, paren_start, num_end - 1)
      end
    end
  else
    vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, fold_icon_hl, li, 0, #icon)
    if paren_start then
      vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, #icon, paren_start - 2)
      local num_end = text:find('%)', paren_start)
      if num_end then
        vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Number', li, paren_start, num_end - 1)
      end
    else
      vim.api.nvim_buf_add_highlight(state.log_buf, ns_id, 'Label', li, #icon, -1)
    end
  end
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
