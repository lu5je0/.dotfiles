local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')
local source_base = require('lu5je0.ext.sidebar.source_base')
local model = require('lu5je0.ext.sidebar.sources.history.model')
local selection = require('lu5je0.ext.git.common.commit-selection')
local git_style = require('lu5je0.ext.sidebar.git_style')
local parser = require('lu5je0.ext.sidebar.sources.git_changes.parser')
local M = { preview_kind = 'diff' }
local spec = { id = 'history' }
M._spec = spec

local function visible(ts, tabpage)
  return vim.api.nvim_get_current_tabpage() == tabpage and ts.active_tab_idx == config.tab_idx('history') and ts.win and vim.api.nvim_win_is_valid(ts.win)
end
local function current_item()
  if not state:is_open() then
    return
  end
  return state.history.display_items[vim.api.nvim_win_get_cursor(state.win)[1]]
end
local function item_key(item)
  return item and item.node and item.node.commit.hash
end

local function is_merge(commit)
  return (commit.parents or ''):find('%S+%s+%S+') ~= nil
end

function spec.build(h)
  local roots = {}
  for index, commit in ipairs(h.commits) do
    local function file_tree(owner, group)
      local files, by_path = {}, {}
      for file_index, file in ipairs(owner.files) do
        local xy = file.status == '??' and '??' or (file.status:sub(1, 1) .. ' ')
        files[#files + 1] = { path = file.path, old_path = file.old_path, xy = xy, x = xy:sub(1, 1), y = xy:sub(2, 2) }
        by_path[file.path] = file_index
      end
      local nodes = parser.files_to_tree_nodes(files, owner.expanded_dirs, 'history', h.repo_root)
      local function annotate(children)
        for _, node in ipairs(children) do
          node.commit, node.commit_idx = commit, index
          node.parent_group = group
          node.file_idx = by_path[node.rel_path]
          if node.children then
            annotate(node.children)
          end
        end
      end
      annotate(nodes)
      return nodes
    end
    local children = {}
    if commit.expanded then
      local groups = model.parent_diffs(commit)
      if #groups == 0 then
        children = file_tree(commit)
      else
        for _, group in ipairs(groups) do
          local nodes = group.expanded and file_tree(group, group) or {}
          if group.expanded and #nodes == 0 then
            local message = group.error or (group.loaded and 'No changes' or 'Loading changes…')
            nodes = { { name = message:gsub('[\r\n]+', ' '), type = 'message', commit = commit, commit_idx = index, parent_group = group } }
          end
          children[#children + 1] = {
            name = string.format('Parent %d · %s', group.index, group.hash:sub(1, 7)),
            type = 'directory',
            _is_section = true,
            _is_parent = true,
            expanded = group.expanded,
            children = nodes,
            commit = commit,
            commit_idx = index,
            parent_group = group,
          }
        end
      end
    end
    roots[#roots + 1] = {
      name = commit.short_hash .. ' ' .. commit.message,
      type = 'directory',
      _is_section = true,
      expanded = commit.expanded,
      children = children,
      commit = commit,
      commit_idx = index,
      graph = h.graph_enabled and h.graph_rows and h.graph_rows[index] or nil,
    }
  end
  return roots
end

function spec.render_opts()
  local opts = git_style.tree_options()
  local get_dir_icon = opts.get_dir_icon
  opts.get_dir_icon = function(node)
    if node.graph then
      return node.graph.text
    end
    return get_dir_icon(node)
  end
  local info = vim.fn.getwininfo(state.win)[1]
  opts.name_width = info and (info.width - info.textoff) or 48
  opts.dir_suffix = function(node)
    if node._is_section and not node._is_parent and not node.expanded then
      return node.commit.date:sub(6, 10), is_merge(node.commit) and 'SidebarHistoryMerge' or 'SidebarHistoryDate'
    end
  end
  opts.item_data = function(node)
    return { type = node._is_parent and 'parent' or (node._is_section and 'commit' or (node.type == 'directory' and 'dir' or node.type)), commit_idx = node.commit_idx, file_idx = node.file_idx }
  end
  opts.node_hl = function(node)
    if node._is_parent then
      return 'SidebarHistoryParent'
    end
    if node.type == 'message' then
      return 'Comment'
    end
    if node._is_section then
      return 'SidebarHistoryCommit'
    end
    if node.xy then
      return git_style.file_name_hl(node.xy)
    end
  end
  return opts
end

function spec.decorate(h, lines, items, highlights)
  if #lines > 0 then
    local commits = {}
    for _, item in ipairs(items) do
      if item.type == 'commit' then
        commits[item.line_idx] = item
      end
    end
    -- Split the renderer's spans instead of stacking equal-priority colors.
    -- Overlapping icon/name highlights otherwise win inconsistently by row.
    local extra = {}
    for _, hl in ipairs(highlights) do
      local item = commits[hl.line]
      if item and hl.hl == 'SidebarHistoryCommit' then
        local graph = item.node.graph
        if hl.col_start == 0 then
          if graph then
            for _, span in ipairs(graph.spans) do
              extra[#extra + 1] = {
                line = hl.line,
                col_start = hl.col_start + span.first,
                col_end = hl.col_start + span.last,
                hl = span.color == -1 and 'SidebarHistoryGraphCommit' or ('SidebarHistoryGraph' .. span.color),
              }
            end
            hl.col_end = hl.col_start
          else
            hl.hl = 'SidebarHistoryArrow'
          end
        else
          local last = math.min(hl.col_end, hl.col_start + #item.node.commit.short_hash)
          local merge = is_merge(item.node.commit)
          extra[#extra + 1] = { line = hl.line, hl = merge and 'SidebarHistoryMerge' or 'SidebarHistoryHash', col_start = hl.col_start, col_end = last }
          if merge then
            hl.hl = 'SidebarHistoryMerge'
          end
          hl.col_start = last
        end
      end
    end
    vim.list_extend(highlights, extra)
    return
  end
  local message = h.loading and 'Loading history…' or h.error or (h.repo_root and 'No commits' or 'Not in a Git repository')
  return { '  ' .. message:gsub('[\r\n]+', ' ') }, {}, { { line = 0, hl = 'Comment', col_start = 0, col_end = -1 } }, {}
end

function spec.post_flush(h)
  if h.refresh_selection then
    h.refresh_selection()
  end
end

local function redraw(ts, tabpage)
  if not visible(ts, tabpage) then
    return
  end
  source_base.render(spec)
  local h = ts.history
  if h.pending_jump_sha then
    for line, item in ipairs(h.display_items) do
      local commit = item.node.commit
      if commit.hash:sub(1, #h.pending_jump_sha) == h.pending_jump_sha then
        if not h.pending_jump_file or (item.node.rel_path == h.pending_jump_file or item.node.old_path == h.pending_jump_file) then
          vim.api.nvim_win_set_cursor(ts.win, { line, 0 })
          h.pending_jump_sha, h.pending_jump_file = nil, nil
          break
        end
      end
    end
    if h.pending_jump_sha and not h.loading and not next(h.merge_jobs) then
      vim.notify('Commit or file not found in loaded history', vim.log.levels.WARN)
      h.pending_jump_sha, h.pending_jump_file = nil, nil
    end
  end
end

local function load_merge(ts, tabpage, commit)
  model.load_merge(ts.history, commit, function()
    if not visible(ts, tabpage) then
      return
    end
    local h = ts.history
    local old = h.display_items[vim.api.nvim_win_get_cursor(ts.win)[1]]
    local jumping = h.pending_jump_sha
    redraw(ts, tabpage)
    if old and not jumping then
      local node = old.node
      for line, item in ipairs(h.display_items) do
        local candidate = item.node
        if item.type == old.type and candidate.commit == node.commit and candidate.parent_group == node.parent_group and candidate.abs_path == node.abs_path then
          vim.api.nvim_win_set_cursor(ts.win, { line, 0 })
          break
        end
      end
    end
  end)
end

local function load(opts)
  local ts, tabpage = state.tab(), vim.api.nvim_get_current_tabpage()
  local h = ts.history
  if not h.repo_root then
    return
  end
  require('lu5je0.ext.sidebar.actions.preview').stop()
  model.load(h, h.repo_root, opts, function()
    if h.pending_jump_sha and h.pending_jump_file then
      for _, commit in ipairs(h.commits) do
        if commit.hash:sub(1, #h.pending_jump_sha) == h.pending_jump_sha then
          commit.expanded = true
          load_merge(ts, tabpage, commit)
        end
      end
    end
    redraw(ts, tabpage)
  end)
  redraw(ts, tabpage)
end

local function setup_selection()
  local ts, tabpage = state.tab(), vim.api.nvim_get_current_tabpage()
  local h = ts.history
  h.log_buf, h.log_win = ts.buf, ts.win
  h.is_visible = function()
    return visible(ts, tabpage)
  end
  -- Selection actions are installed by the source keymap dispatcher.
  selection.setup(h, item_key, function() end, { manual_refresh = true, map = function() end })
end

function M.render()
  local h = state.history
  setup_selection()
  h.repo_root = h.repo_root or vim.fs.root(vim.fn.getcwd(), '.git')
  if h.repo_root and not h.loaded and not h.loading then
    load()
  else
    redraw(state.tab(), vim.api.nvim_get_current_tabpage())
  end
end

function M.on_enter()
  M.render()
  local ts, tabpage = state.tab(), vim.api.nvim_get_current_tabpage()
  for _, commit in ipairs(ts.history.commits) do
    if commit.expanded then
      load_merge(ts, tabpage, commit)
    end
  end
end
M.on_resize = M.render

function M.status()
  local h = state.history
  if h.loading then
    return 'History · loading'
  end
  local count = selection.count(h)
  return string.format('History · %d commits%s', #h.commits, count > 0 and (' · ' .. count .. ' selected') or '')
end

function M.open(opts)
  opts = opts or {}
  local path = vim.fn.expand('%:p')
  local root = vim.fs.root(path ~= '' and path or vim.fn.getcwd(), '.git')
  if not root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end
  local h = state.history
  if root ~= h.repo_root then
    model.cancel(h)
    h.loaded = false
  end
  h.repo_root = root
  require('lu5je0.ext.sidebar').open_tab(config.tab_idx('history'), { no_toggle = true })
  setup_selection()
  if opts.jump_to_sha then
    h.pending_jump_sha = opts.jump_to_sha
    h.pending_jump_file = opts.jump_to_file and opts.jump_to_file:gsub('^' .. vim.pesc(root .. '/'), '')
    load(opts)
  else
    M.on_enter()
  end
end

function M.on_leave(ts)
  model.cancel(ts.history)
  if ts.buf and vim.api.nvim_buf_is_valid(ts.buf) then
    vim.api.nvim_buf_clear_namespace(ts.buf, vim.api.nvim_create_namespace('git_commit_selection'), 0, -1)
  end
end

function M.on_directory_changed(ts, cwd)
  local root = vim.fs.root(cwd, '.git')
  local h = ts.history
  if h.repo_root == root then
    return
  end
  model.cancel(h)
  h.repo_root, h.loaded, h.error = root, false, nil
  h.commits, h.selected_commits = {}, {}
  h.graph_rows = nil
  if ts.active_tab_idx == config.tab_idx('history') and ts.win then
    M.render()
  end
end

local function set_expanded(item, expanded)
  local node = expanded and (item.display_node or item.node) or item.node
  if node._is_parent then
    node.parent_group.expanded = expanded
  elseif node._is_section then
    node.commit.expanded = expanded
  else
    local owner = node.parent_group or node.commit
    owner.expanded_dirs = owner.expanded_dirs or {}
    owner.expanded_dirs[node.abs_path] = expanded
    if expanded then
      while node.children and #node.children == 1 and node.children[1].type == 'directory' do
        node = node.children[1]
        owner.expanded_dirs[node.abs_path] = true
      end
    else
      local tail = item.display_node or node
      while node ~= tail do
        node = node.children[1]
        owner.expanded_dirs[node.abs_path] = false
      end
    end
  end
end
local function open_file(item)
  local path = item and item.node.abs_path
  if path and vim.uv.fs_stat(path) then
    require('lu5je0.ext.sidebar.window').open_file(path)
  end
end
spec.open = {
  keep_cursor = function(item)
    return item.type == 'commit' or item.type == 'parent'
  end,
  is_expandable = function(item)
    return item.node.type == 'directory'
  end,
  is_expanded = function(item)
    return (item.display_node or item.node).expanded
  end,
  expand = function(item)
    set_expanded(item, true)
    load_merge(state.tab(), vim.api.nvim_get_current_tabpage(), item.node.commit)
  end,
  on_already_expanded = function(_, line)
    vim.api.nvim_win_set_cursor(state.win, { math.min(line + 1, #state.history.display_items), 0 })
  end,
  on_file = open_file,
}
spec.close = {
  is_closeable = function(item)
    local node = item.display_node or item.node
    local current = current_item()
    current = current and (current.display_node or current.node)
    if not current or node.type ~= 'directory' or not node.expanded or node.commit ~= current.commit then
      return false
    end
    if node._is_section and not node._is_parent then
      return true
    end
    if node.parent_group ~= current.parent_group then
      return false
    end
    return node == current or node._is_parent or (current.abs_path and node.abs_path and vim.startswith(current.abs_path, node.abs_path .. '/'))
  end,
  is_boundary = function(item)
    local current = current_item()
    return current and item.node.commit ~= current.node.commit
  end,
  close = function(item)
    set_expanded(item, false)
  end,
}
function M.open_node()
  source_base.open_node(spec, M.render)
end
function M.close_node()
  source_base.close_node(spec, M.render)
end

function M.toggle_graph()
  local h = state.history
  h.graph_enabled = not h.graph_enabled
  if h.graph_enabled then
    model.prepare_graph(h)
  end
  M.render()
end

function M.preview_item()
  local item = current_item()
  if item and item.type == 'commit' then
    local commit = item.node.commit
    local lines = { 'commit ' .. commit.hash, 'Author: ' .. commit.author, 'Date:   ' .. commit.date }
    if commit.parents and commit.parents ~= '' then
      lines[#lines + 1] = 'Parents: ' .. commit.parents
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = commit.message
    lines[#lines + 1] = ''
    local groups = model.parent_diffs(commit)
    local owners = #groups > 0 and groups or { commit }
    for _, owner in ipairs(owners) do
      if owner.hash ~= commit.hash then
        lines[#lines + 1] = string.format('Parent %d · %s', owner.index, owner.hash:sub(1, 7))
      end
      lines[#lines + 1] = #groups > 0 and (owner.error or (owner.loaded and string.format('Files changed (%d)', #owner.files) or 'Expand merge to load changes'))
        or string.format('Files changed (%d)', #owner.files)
      for _, file in ipairs(owner.files) do
        local path = file.old_path and (file.old_path .. ' → ' .. file.path) or file.path
        lines[#lines + 1] = '  ' .. file.status .. '  ' .. path
      end
    end
    return { preview_kind = 'text', title = 'Commit ' .. commit.short_hash, lines = lines }
  end
  if not item or item.type ~= 'file' then
    return
  end
  local node, commit = item.node, item.node.commit
  local file = (node.parent_group or commit).files[item.file_idx]
  local parent = node.parent_group and node.parent_group.hash or (commit.parents and commit.parents:match('%x+'))
  local status = file.status:sub(1, 1)
  local targets = {
    left = parent and status ~= 'A' and { kind = 'git_show', spec = parent .. ':' .. (file.old_path or file.path) } or { kind = 'empty' },
    right = status ~= 'D' and { kind = 'git_show', spec = commit.hash .. ':' .. file.path } or { kind = 'empty' },
    left_title = parent and (' ' .. parent:sub(1, 7) .. ' ') or ' (none) ',
    right_title = ' ' .. commit.short_hash .. ' ',
  }
  return { node = node, diff_targets = targets, repo_root = state.history.repo_root }
end

local function mark(visual)
  local h = state.history
  local first, last
  if visual then
    first, last = selection.visual_range(h)
  else
    first = vim.api.nvim_win_get_cursor(state.win)[1]
    last = first
  end
  local keys = selection.keys(h, item_key, first, last)
  local selected = false
  for _, key in ipairs(keys) do
    selected = selected or not h.selected_commits[key]
  end
  for _, key in ipairs(keys) do
    h.selected_commits[key] = selected or nil
  end
  if h.refresh_selection then
    h.refresh_selection()
  end
end
local function show_selected(visual)
  local h = state.history
  local first, last
  if visual then
    first, last = selection.visual_range(h)
  end
  local keys = selection.keys(h, item_key, first, last)
  if #keys == 0 then
    return false
  end
  local by_key, commits = {}, {}
  for _, commit in ipairs(h.commits) do
    by_key[commit.hash] = commit
  end
  for _, key in ipairs(keys) do
    commits[#commits + 1] = vim.deepcopy(by_key[key])
  end
  local opts = require('lu5je0.ext.git.common.net-diff').project(commits, h.repo_root)
  local keeper = require('lu5je0.misc.env-keeper')
  opts.mode = require('lu5je0.ext.sidebar.actions.diff_preview').get_mode()
  opts.changes_only = keeper.get('sidebar_diff_changes_only', false)
  require('lu5je0.ext.git.common.selected-diff').open(opts)
  return true
end

function M.keymaps()
  local preview = require('lu5je0.ext.sidebar.actions.preview')
  local diff_preview = require('lu5je0.ext.sidebar.actions.diff_preview')
  return {
    { 'l', M.open_node, desc = 'Open node' },
    { 'zo', M.open_node, desc = 'Open node' },
    {
      '<cr>',
      function()
        if not show_selected(false) then
          M.open_node()
        end
      end,
      desc = 'Open / view selected commits',
    },
    { 'h', M.close_node, desc = 'Close node' },
    { 'zc', M.close_node, desc = 'Close node' },
    { '<space>', preview.toggle, desc = 'Preview' },
    { '<space><space>', preview.enter, desc = 'Enter preview' },
    { 'gG', M.toggle_graph, desc = 'Toggle Tig commit graph' },
    {
      'd',
      function()
        diff_preview.toggle_mode()
        preview.refresh()
      end,
      desc = 'Toggle diff mode',
    },
    {
      'c',
      function()
        diff_preview.toggle_changes_only()
        preview.refresh()
      end,
      desc = 'Toggle changes-only',
    },
    {
      'm',
      function()
        mark(false)
      end,
      desc = 'Mark commit',
    },
    {
      'm',
      function()
        mark(true)
      end,
      mode = 'x',
      desc = 'Mark commits',
    },
    {
      'U',
      function()
        state.history.selected_commits = {}
        M.render()
      end,
      desc = 'Clear selection',
    },
    {
      '<cr>',
      function()
        show_selected(true)
      end,
      mode = 'x',
      desc = 'View selected commits',
    },
    {
      'r',
      function()
        load()
      end,
      desc = 'Refresh',
    },
    {
      'ga',
      function()
        load { all = true }
      end,
      desc = 'Load all commits',
    },
    {
      'K',
      function()
        local item = current_item()
        if item then
          local c = item.node.commit
          require('lu5je0.ext.git.common.help').show_help('Commit', { c.hash, c.date .. '  ' .. c.author, '', c.message })
        end
      end,
      desc = 'Commit details',
    },
  }
end
return M
