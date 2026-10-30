-- Real-key regressions for both lazy Git log entry points and picked patches.
-- Usage: cd vim && nvim --headless -u NONE -l tests/git-selection/spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
local repo = vim.fn.tempname() .. '-git-selection'
vim.fn.mkdir(repo, 'p')
local children = {}
local passed, failed = 0, 0
local function git(args)
  local cmd = { 'git', '-C', repo }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return (result.stdout or ''):gsub('%s+$', '')
end
local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(repo .. '/' .. path, ':h'), 'p')
  vim.fn.writefile(lines, repo .. '/' .. path)
end
local function commit(message)
  git { 'add', '-A' }
  git { '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', message }
  return git { 'rev-parse', '--short', 'HEAD' }
end
git { 'init', '-q' }
write('demo.txt', { 'alpha', 'unselected source line' })
local first = commit('picked-root')
write('demo.txt', { 'beta', 'unselected source line' })
local middle = commit('skipped-middle')
write('demo.txt', { 'gamma', 'unselected source line' })
write('extra.txt', { 'extra' })
write('中文 name.txt', { 'unicode filename' })
write('nested/dir/one.txt', { 'nested one' })
write('nested/dir/two.txt', { 'nested two' })
local latest = commit('picked-change')
git { 'mv', 'demo.txt', 'renamed.txt' }
local renamed = commit('picked-rename')
git { 'rm', 'extra.txt' }
local deleted = commit('picked-delete')

local function child(kind, mode)
  local chan = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-n', '-i', 'NONE', '-u', 'NONE', '--cmd', 'set rtp+=' .. root .. '/vim' }, {
    rpc = true,
    env = { NVIM_LOG_FILE = vim.fn.tempname() },
  })
  assert(chan > 0)
  children[#children + 1] = chan
  local c = {}
  function c.q(code, args)
    return vim.rpcrequest(chan, 'nvim_exec_lua', code, args or {})
  end
  function c.feed(keys)
    keys = keys:gsub('<Mark>', kind == 'project' and 'm' or '<Space>')
    vim.rpcrequest(chan, 'nvim_input', keys)
    vim.wait(70, function()
      return false
    end)
  end
  function c.wait(code)
    assert(
      vim.wait(10000, function()
        return c.q(code)
      end, 20),
      'timed out: ' .. code .. '\n' .. c.q([[return vim.api.nvim_exec2('messages',{output=true}).output]])
    )
  end
  c.q(
    [[
    local repo, mode = ...
    vim.g.mapleader = ','
    vim.o.columns, vim.o.lines = 140, 36
    _G.saved_diff_prefs = { line_log_diff_mode = mode, line_log_diff_changes_only = false, sidebar_diff_mode = mode, sidebar_diff_changes_only = false }
    package.loaded['lu5je0.misc.env-keeper'] = {
      get = function(key, default)
        if saved_diff_prefs[key] ~= nil then return saved_diff_prefs[key] end
        return default
      end,
      set = function(key, value) saved_diff_prefs[key] = value end,
    }
    vim.cmd.edit(repo .. '/renamed.txt')
    require('lu5je0.ext.loader').ext_load({
      name = 'git', config = function() require('lu5je0.ext.git').setup() end,
      keys = { { '<leader>gl', mode = { 'n', 'x' } } },
    })
  ]],
    { repo, mode or 'single' }
  )
  c.feed(kind == 'line' and 'ggV,gl' or ',gl')
  c.wait(
    kind == 'line' and [[return vim.api.nvim_buf_line_count(0) == 3 and vim.wo.statusline:find('L%%#Number#1%%') ~= nil]]
      or [[return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\n'):find('picked-root',1,true) ~= nil]]
  )
  c.q([[
    _G.log_win = vim.api.nvim_get_current_win(); _G.log_buf = vim.api.nvim_get_current_buf()
    function preview_wins()
      local wins={}
      for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.w[w].git_selected_diff then wins[#wins+1]=w end
      end
      return wins
    end
    function preview_status()
      local statuses={}
      for _,w in ipairs(preview_wins()) do statuses[#statuses+1]=vim.wo[w].statusline end
      return table.concat(statuses,' | ')
    end
    function tree_win()
      for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.w[w].git_selected_diff_tree then return w end
      end
    end
  ]])
  function c.row(text)
    return c.q(
      [[
      local text = ...
      for i,line in ipairs(vim.api.nvim_buf_get_lines(log_buf,0,-1,false)) do
        if line:find(text,1,true) then return i end
      end
      error('missing log row: '..text)
    ]],
      { text }
    )
  end
  function c.go(text)
    c.feed(c.row(text) .. 'G')
  end
  function c.selected(count)
    if kind == 'project' then
      c.wait(('return vim.tbl_count(require("lu5je0.ext.sidebar.state").history.selected_commits)==%d'):format(count))
      return
    end
    c.wait(([[return vim.wo[log_win].statusline:find(%q,1,true) ~= nil]]):format(count .. ' selected'))
  end
  function c.preview()
    c.wait([=[local wins=preview_wins(); return #wins==1 and not vim.wo[wins[1]].diff and preview_status():find('Selected Diff',1,true)~=nil and not preview_status():find('loading',1,true)]=])
    return c.q([[return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(preview_wins()[1]),0,-1,false),'\n')]])
  end
  function c.tree_text()
    c.wait([[return tree_win()~=nil and vim.wo[tree_win()].statusline:find('commits',1,true)~=nil]])
    return c.q([[return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(tree_win()),0,-1,false),'\n')]])
  end
  function c.pick(filename, confirm)
    local row = c.q(
      [[
      local filename=...
      for i,line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(tree_win()),0,-1,false)) do
        if line:find(filename,1,true) then return i end
      end
      error('missing file in tree: '..filename)
    ]],
      { filename }
    )
    c.q([[vim.api.nvim_set_current_win(tree_win())]])
    c.feed(row .. 'G' .. (confirm == false and '' or '<CR>'))
  end
  function c.dual_ready()
    c.wait([=[local wins=preview_wins(); return #wins==2 and vim.wo[wins[1]].diff and vim.wo[wins[2]].diff and not preview_status():find('loading',1,true)]=])
  end
  function c.stop()
    pcall(vim.fn.jobstop, chan)
  end
  return c
end

local function contains(text, part)
  assert(text:find(part, 1, true), 'missing: ' .. part .. '\n' .. text)
end
local function excludes(text, part)
  assert(not text:find(part, 1, true), 'unexpected: ' .. part .. '\n' .. text)
end
local function run(name, fn)
  if vim.env.NVIM_TEST_FILTER and not name:find(vim.env.NVIM_TEST_FILTER, 1, true) then
    return
  end
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS ' .. name)
  else
    failed = failed + 1
    print('FAIL ' .. name .. '\n' .. tostring(err))
  end
  for _, chan in ipairs(children) do
    pcall(vim.fn.jobstop, chan)
  end
  children = {}
end

local function pick_commits(c, names)
  for _, name in ipairs(names) do
    c.go(name)
    c.feed('<Mark>')
  end
  c.selected(#names)
  c.feed('<CR>')
end

local function merge_error(c)
  c.wait([[return tree_win()~=nil and table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(tree_win()),0,-1,false),'\n'):find('Cannot merge selected commits',1,true)~=nil]])
  c.q([[assert(#preview_wins()==0, 'failed merge must not show a partial diff')]])
  return c.tree_text()
end

for _, kind in ipairs { 'project', 'line' } do
  run(kind .. ' log: c and d independently toggle context and layout after lazy entry', function()
    local c = child(kind)
    c.go('picked-change')
    if kind == 'project' then
      c.feed('l')
      c.go('demo.txt')
      c.feed('<Space>')
    end
    c.q([[
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(log_buf, 'n')) do
        assert(map.lhs ~= 'D', 'D must not have a buffer mapping')
      end
    ]])
    for _, expected in ipairs {
      { 'c', 'single', true },
      { 'd', 'dual', true },
      { 'c', 'dual', false },
      { 'd', 'single', false },
      { 'd', 'dual', false },
      { 'c', 'dual', true },
      { 'd', 'single', true },
      { 'c', 'single', false },
    } do
      c.feed(expected[1])
      local check = ([[
        if saved_diff_prefs.line_log_diff_mode ~= %q or saved_diff_prefs.line_log_diff_changes_only ~= %s then return false end
        local count = 0
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.w[win].git_line_log_diff or vim.w[win].git_project_log_diff then
            count = count + 1
            if vim.wo[win].diff ~= %s then return false end
            if vim.wo[win].diff and vim.wo[win].foldenable ~= %s then return false end
          end
        end
        return count == %d
      ]]):format(expected[2], tostring(expected[3]), tostring(expected[2] == 'dual'), tostring(expected[3]), expected[2] == 'dual' and 2 or 1)
      if kind == 'project' then
        check = check:gsub('line_log_diff_', 'sidebar_diff_'):gsub(
          'if vim.w%[win%].git_line_log_diff or vim.w%[win%].git_project_log_diff then',
          'local d=require("lu5je0.ext.sidebar.state").diff_preview; if win==d.win_single or win==d.win_left or win==d.win_right then'
        )
      end
      c.wait(check)
    end
    c.stop()
  end)
end

run('continuous selection: one net patch per path, original marks survive tree expansion', function()
  local index_before = git { 'hash-object', '.git/index' }
  local c = child('project')
  for _, name in ipairs { 'picked-root', 'skipped-middle', 'picked-change' } do
    c.go(name)
    c.feed('<Mark>')
  end
  c.selected(3)
  c.feed('l')
  c.q([[
    assert(#vim.api.nvim_buf_get_extmarks(log_buf,vim.api.nvim_create_namespace('git_commit_selection'),0,-1,{})==3)
  ]])
  c.feed('<Mark>')
  c.selected(2)
  c.feed('<Mark>')
  c.selected(3)
  c.feed('<CR>')
  local tree_text = c.tree_text()
  contains(tree_text, 'Selected 3 commits')
  local _, count = tree_text:gsub('demo%.txt', '')
  assert(count == 1, 'same file must only appear once')
  local text = c.preview()
  contains(text, '+gamma')
  excludes(text, '+alpha')
  excludes(text, '+beta')
  local _, patches = text:gsub('\n@@ ', '')
  assert(patches == 1, 'selected commits should produce one net patch')
  c.feed('d')
  c.dual_ready()
  c.q([[
    local texts={}
    for _,w in ipairs(preview_wins()) do texts[#texts+1]=table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w),0,-1,false),'\n') end
    assert(vim.tbl_contains(texts,''))
    assert(vim.tbl_contains(texts,'gamma\nunselected source line'))
  ]])
  c.feed(']f')
  c.wait([[return preview_status():find('extra.txt',1,true)~=nil]])
  c.feed('[fd')
  c.preview()
  c.pick('中文 name.txt')
  contains(c.preview(), '+unicode filename')
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  c.selected(3)
  c.feed('U')
  c.q([[assert(not vim.wo[log_win].statusline:find('selected',1,true))]])
  assert(index_before == git { 'hash-object', '.git/index' }, 'real index changed')
  c.stop()
end)

run('dependent nonadjacent commits report a conflict without altering the index or worktree', function()
  local index_before = git { 'hash-object', '.git/index' }
  local before = table.concat(vim.fn.readfile(repo .. '/renamed.txt'), '\n')
  local c = child('project')
  pick_commits(c, { 'picked-root', 'picked-change' })
  contains(merge_error(c), 'conflict')
  assert(index_before == git { 'hash-object', '.git/index' }, 'real index changed on conflict')
  assert(before == table.concat(vim.fn.readfile(repo .. '/renamed.txt'), '\n'), 'worktree changed on conflict')
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  c.stop()
end)

run('nested merged tree folds, expands and automatically previews files', function()
  local c = child('project')
  pick_commits(c, { 'picked-change' })
  contains(c.tree_text(), 'nested/dir')
  c.pick('one.txt')
  contains(c.preview(), '+nested one')
  c.feed('h')
  excludes(c.tree_text(), 'one.txt')
  excludes(c.tree_text(), 'two.txt')
  c.feed('l')
  contains(c.tree_text(), 'two.txt')
  c.pick('two.txt', false)
  contains(c.preview(), '+nested two')
  c.feed('H')
  excludes(c.tree_text(), 'demo.txt')
  c.feed('<CR>')
  contains(c.tree_text(), 'demo.txt')
  c.pick('extra.txt', false)
  contains(c.preview(), '+extra')
  c.feed('d')
  c.dual_ready()
  c.q([[vim.api.nvim_set_current_win(preview_wins()[2])]])
  c.feed('d')
  c.preview()
  contains(c.tree_text(), 'nested/dir')
  c.stop()
end)

run('Visual Enter computes net changes for line, character and block selections', function()
  local c = child('project')
  local top, bottom = c.row('picked-change'), c.row('picked-root')
  for _, mode in ipairs { 'V', 'v', '<C-v>' } do
    c.feed(bottom .. 'G' .. mode .. top .. 'G<CR>')
    contains(c.tree_text(), 'Selected 3 commits')
    local text = c.preview()
    contains(text, '+gamma')
    excludes(text, '+beta')
    excludes(text, '+alpha')
    c.feed('q')
    c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  end
  c.feed(top .. 'GV' .. bottom .. 'G<Mark>')
  c.selected(3)
  c.feed('<Mark>')
  c.q([[assert(not vim.wo[log_win].statusline:find('selected',1,true))]])
  c.stop()
end)

run('History merge groups preview each parent and include manual merge edits', function()
  write('merge-shared.txt', { 'base' })
  write('merge-old.txt', { 'unique rename contents' })
  write('merge-deleted.txt', { 'delete me' })
  commit('merge-fixture-base')
  local main = git { 'branch', '--show-current' }
  git { 'checkout', '-qb', 'history-side' }
  write('merge-shared.txt', { 'side' })
  write('merge-side.txt', { 'side addition' })
  git { 'mv', 'merge-old.txt', '合并 renamed.txt' }
  git { 'rm', 'merge-deleted.txt' }
  local side = commit('history-side-change')
  git { 'checkout', '-q', main }
  write('merge-shared.txt', { 'main' })
  write('merge-main.txt', { 'main addition' })
  local first_parent = commit('history-main-change')
  local merged = vim.system({ 'git', '-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'merge', '--no-commit', '--no-ff', 'history-side' }, { text = true }):wait()
  assert(merged.code == 1, merged.stderr)
  write('merge-shared.txt', { 'manual merge result' })
  local sha = commit('history-merge-result')
  local c = child('project')
  c.go('history-merge-result')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    for _,commit in ipairs(s.history.commits) do
      assert(not commit.parent_diffs or #commit.parent_diffs==0, 'merge must load only on expansion')
    end
  ]])
  c.feed('l')
  c.wait([[
    local h=require('lu5je0.ext.sidebar.state').history
    return h.commits[1].parent_diffs and #h.commits[1].parent_diffs==2
      and h.commits[1].parent_diffs[2].loaded
  ]])
  c.q([[
    local first,second=...
    local s=require('lu5je0.ext.sidebar.state')
    local groups=s.history.commits[1].parent_diffs
    assert(groups[1].hash:find(first,1,true)==1, vim.inspect({groups,first,second}))
    assert(groups[2].hash:find(second,1,true)==1)
    function merge_file_row(index,path)
      for row,item in ipairs(s.history.display_items) do
        if item.type=='file' and item.node.parent_group==groups[index] and item.node.rel_path==path then return row end
      end
      error('missing merge file '..index..' '..path)
    end
    function check_merge_target(index,path,old_path,kind)
      local row=merge_file_row(index,path)
      vim.api.nvim_win_set_cursor(s.win,{row,0})
      local targets=require('lu5je0.ext.sidebar.sources.history').preview_item().diff_targets
      assert(targets.left.kind==(kind=='A' and 'empty' or 'git_show'))
      assert(targets.right.kind==(kind=='D' and 'empty' or 'git_show'))
      if kind~='A' then assert(targets.left.spec==groups[index].hash..':'..(old_path or path)) end
      if kind~='D' then assert(targets.right.spec==s.history.commits[1].hash..':'..path) end
      return row
    end
    check_merge_target(1,'合并 renamed.txt','merge-old.txt','R')
    check_merge_target(1,'merge-deleted.txt',nil,'D')
    check_merge_target(1,'merge-side.txt',nil,'A')
    check_merge_target(2,'merge-main.txt',nil,'A')
    check_merge_target(1,'merge-shared.txt')
    check_merge_target(2,'merge-shared.txt')
  ]], { first_parent, side })
  c.feed('<Space>')
  c.wait([[
    local s=require('lu5je0.ext.sidebar.state'); local dp=s.diff_preview
    if not dp.win_single or not vim.api.nvim_win_is_valid(dp.win_single) then return false end
    local text=table.concat(vim.api.nvim_buf_get_lines(dp.buf_single,0,-1,false),'\n')
    return text:find('-side',1,true) and text:find('+manual merge result',1,true)
  ]])
  c.q([[require('lu5je0.ext.sidebar.actions.preview').stop()]])
  c.feed('h')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    local line=vim.api.nvim_win_get_cursor(s.win)[1]
    local item=s.history.display_items[line]
    assert(item.type=='parent' and item.node.parent_group.index==2, vim.inspect(item))
    assert(not item.node.parent_group.expanded, 'parent must close')
    assert(s.history.commits[1].parent_diffs[1].expanded)
  ]])
  c.feed('l')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    assert(s.history.commits[1].parent_diffs[2].expanded)
  ]])
  c.q([[
    local sha,repo=...
    for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win~=require('lu5je0.ext.sidebar.state').win and vim.api.nvim_win_get_config(win).relative=='' then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
    vim.cmd.edit(repo..'/renamed.txt')
    require('lu5je0.ext.sidebar.sources.history').open({jump_to_sha=sha,jump_to_file='合并 renamed.txt'})
  ]], { sha, repo })
  c.wait([[
    local s=require('lu5je0.ext.sidebar.state')
    local line=vim.api.nvim_win_get_cursor(s.win)[1]
    local item=s.history.display_items[line]
    return not s.history.pending_jump_sha and item and item.node.rel_path=='合并 renamed.txt'
  ]])
  c.stop()
end)

run('History merge loading cancels on page leave and resumes all parents with empty groups', function()
  local parents = git { 'rev-parse', 'HEAD', 'HEAD^', 'HEAD^^' }
  local hashes = vim.split(parents, '\n', { trimempty = true })
  local sha = git { '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit-tree', 'HEAD^{tree}', '-p', hashes[1], '-p', hashes[2], '-p', hashes[3], '-m', 'three-parent-fixture' }
  local c = child('project')
  c.q([[
    local sha,parents=...
    local s=require('lu5je0.ext.sidebar.state')
    _G.merge_fixture={hash=sha,short_hash=sha:sub(1,7),parents=parents,message='three-parent-fixture',author='Test',date='2026-01-01',files={},expanded_dirs={}}
    table.insert(s.history.commits,1,merge_fixture)
    require('lu5je0.ext.sidebar.sources.history').render()
    _G.original_system=vim.system
    _G.merge_killed=false
    vim.system=function(args,opts,callback)
      assert(args[3]=='diff',vim.inspect(args))
      _G.late_merge_callback=callback
      return {kill=function() merge_killed=true end}
    end
  ]], { sha, table.concat(hashes, ' ') })
  c.go('three-parent-fixture')
  c.feed('l')
  c.q([[
    local tabs=require('lu5je0.ext.sidebar.tabs')
    tabs.switch_to(require('lu5je0.ext.sidebar.config').tab_idx('files'))
    assert(merge_killed)
    vim.system=original_system
    late_merge_callback({code=0,stdout='M\0stale.txt\0'})
  ]])
  c.q([[
    assert(not merge_fixture.parent_diffs[1].loaded, 'canceled callback must not publish changes')
    assert(#merge_fixture.parent_diffs[1].files==0)
    require('lu5je0.ext.sidebar.tabs').switch_to(require('lu5je0.ext.sidebar.config').tab_idx('history'))
  ]])
  c.wait([[return merge_fixture.parent_diffs[3].loaded]])
  c.q([[
    local source=require('lu5je0.ext.sidebar.sources.history')
    local s=require('lu5je0.ext.sidebar.state')
    assert(#merge_fixture.parent_diffs==3)
    assert(#merge_fixture.parent_diffs[1].files==0)
    local roots=source._spec.build(s.history)
    assert(roots[1].children[1].children[1].name=='No changes')
    assert(not next(s.history.merge_jobs))
    local parent_hl=false
    for _,node in ipairs(roots[1].children) do
      assert(source._spec.render_opts().node_hl(node)=='SidebarHistoryParent')
      parent_hl=true
    end
    assert(parent_hl)
    vim.system=function() error('cached merge must not query Git again') end
  ]])
  c.go('three-parent-fixture')
  c.feed('hl')
  c.q([[vim.system=original_system]])
  c.stop()
end)

run('merge selection compares its first parent', function()
  local main = git { 'branch', '--show-current' }
  git { 'checkout', '-qb', 'selection-side' }
  write('side.txt', { 'from side' })
  commit('side-change')
  git { 'checkout', '-q', main }
  write('main.txt', { 'already on first parent' })
  commit('main-change')
  git { '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'merge', '-q', '--no-ff', 'selection-side', '-m', 'picked-merge' }
  local c = child('project')
  pick_commits(c, { 'picked-merge' })
  contains(c.tree_text(), 'side.txt')
  excludes(c.tree_text(), 'main.txt')
  contains(c.preview(), '+from side')
  c.stop()
end)

run('independent nonadjacent patches merge without including skipped edits', function()
  local lines = {}
  for i = 1, 16 do
    lines[i] = 'base-' .. i
  end
  write('gap.txt', lines)
  commit('gap-base')
  lines[1] = 'selected-first'
  write('gap.txt', lines)
  commit('gap-picked-a')
  lines[16] = 'skipped-last'
  write('gap.txt', lines)
  write('skipped.txt', { 'must not leak' })
  commit('gap-skipped')
  lines[8] = 'selected-middle'
  write('gap.txt', lines)
  commit('gap-picked-c')
  local index_before = git { 'hash-object', '.git/index' }
  local c = child('project')
  pick_commits(c, { 'gap-picked-a', 'gap-picked-c' })
  local tree_text = c.tree_text()
  contains(tree_text, 'gap.txt')
  excludes(tree_text, 'skipped.txt')
  local text = c.preview()
  contains(text, '+selected-first')
  contains(text, '+selected-middle')
  excludes(text, 'skipped-last')
  contains(text, 'base-16')
  c.feed('d')
  c.dual_ready()
  c.q([[
    for _,w in ipairs(preview_wins()) do
      assert(not table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w),0,-1,false),'\n'):find('skipped-last',1,true))
    end
  ]])
  c.feed('c')
  c.dual_ready()
  c.q([[
    for _, win in ipairs(preview_wins()) do assert(vim.wo[win].foldenable) end
  ]])
  c.feed('d')
  local compact = c.preview()
  contains(compact, '+selected-first')
  contains(compact, '+selected-middle')
  excludes(compact, 'base-16')
  c.feed('c')
  contains(c.preview(), 'base-16')
  c.feed('d')
  c.dual_ready()
  c.q([[
    for _, win in ipairs(preview_wins()) do assert(not vim.wo[win].foldenable) end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(win), 'n')) do
        assert(map.lhs ~= 'D', 'D must not have a buffer mapping')
      end
    end
  ]])
  assert(index_before == git { 'hash-object', '.git/index' }, 'real index changed after clean merge')
  c.stop()
end)

run('reverted content and add-then-delete disappear from the net tree', function()
  write('cancel.txt', { 'original' })
  commit('cancel-base')
  write('cancel.txt', { 'temporary' })
  write('ephemeral.txt', { 'temporary' })
  commit('cancel-picked-a')
  write('cancel.txt', { 'original' })
  git { 'rm', 'ephemeral.txt' }
  write('retained.txt', { 'retained' })
  commit('cancel-picked-b')
  local c = child('project')
  pick_commits(c, { 'cancel-picked-a', 'cancel-picked-b' })
  local text = c.tree_text()
  excludes(text, 'cancel.txt')
  excludes(text, 'ephemeral.txt')
  contains(text, 'retained.txt')
  contains(c.preview(), '+retained')
  c.stop()
end)

run('all-cancelled selections show no net changes and no partial preview', function()
  write('cancel.txt', { 'again' })
  commit('empty-picked-a')
  write('cancel.txt', { 'original' })
  commit('empty-picked-b')
  local c = child('project')
  pick_commits(c, { 'empty-picked-a', 'empty-picked-b' })
  contains(c.tree_text(), 'No net changes')
  c.q([[assert(#preview_wins()==0)]])
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  c.stop()
end)

run('History excludes local changes while Changes previews untracked files', function()
  write('untracked.txt', { 'local new file' })
  local c = child('project')
  -- Each file changes once across these selections, so all patches apply cleanly.
  pick_commits(c, { 'picked-rename', 'picked-delete' })
  contains(c.tree_text(), 'renamed.txt')
  excludes(c.tree_text(), 'local new file')
  c.pick('renamed.txt')
  contains(c.preview(), 'rename from demo.txt')
  c.pick('extra.txt')
  contains(c.preview(), '-extra')
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  c.q([[
    for _,entry in ipairs(require('lu5je0.ext.sidebar.state').history.commits) do
      assert(not entry.local_change and entry.hash~='local-change')
    end
    assert(not table.concat(vim.api.nvim_buf_get_lines(log_buf,0,-1,false),'\n'):find('Local changes',1,true))
  ]])
  c.q([[vim.cmd.cd(...)]], { repo })
  c.feed(',gs')
  c.wait([[return table.concat(vim.api.nvim_buf_get_lines(log_buf,0,-1,false),'\n'):find('untracked.txt',1,true)~=nil]])
  c.go('untracked.txt')
  c.feed('<Space>')
  c.wait([[local d=require('lu5je0.ext.sidebar.state').diff_preview; return d.win_single~=nil]])
  c.q([[
    local d=require('lu5je0.ext.sidebar.state').diff_preview
    assert(table.concat(vim.api.nvim_buf_get_lines(d.buf_single,0,-1,false),'\n'):find('+local new file',1,true))
  ]])
  c.stop()
  vim.fn.delete(repo .. '/untracked.txt')
end)

run('line history merges selected blocks, filters cancellation and reports skipped dependencies', function()
  local c = child('line')
  pick_commits(c, { 'picked-root', 'skipped-middle', 'picked-change' })
  local text = c.preview()
  contains(text, '+gamma')
  excludes(text, '+beta')
  excludes(text, 'unselected source line')
  c.feed('d')
  c.dual_ready()
  c.q([[
    local texts={}
    for _,w in ipairs(preview_wins()) do texts[#texts+1]=table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w),0,-1,false),'\n') end
    assert(vim.tbl_contains(texts,'gamma'))
  ]])
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  c.feed('U')
  pick_commits(c, { 'picked-root', 'picked-change' })
  contains(merge_error(c), 'conflict')
  c.stop()
end)

run('tracked blocks three-way merge independent gaps and filter complete cancellation', function()
  local c = child('line')
  c.q([[
    local Block=require('lu5je0.ext.git.line-log.block')
    local base={}
    for i=1,16 do base[i]='base-'..i end
    local a=vim.deepcopy(base);a[1]='selected-first'
    local b=vim.deepcopy(a);b[16]='skipped-last'
    local last=vim.deepcopy(b);last[8]='selected-middle'
    local options=require('lu5je0.ext.git.common.net-diff').blocks({
      {hash='a',old_path='block.txt',path='block.txt',old_block=Block.new(base,1,16),new_block=Block.new(a,1,16)},
      {hash='c',old_path='block.txt',path='block.txt',old_block=Block.new(b,1,16),new_block=Block.new(last,1,16)},
    })
    require('lu5je0.ext.git.common.selected-diff').open(options)
  ]])
  local text = c.preview()
  contains(text, '+selected-first')
  contains(text, '+selected-middle')
  excludes(text, 'skipped-last')
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  c.q([[
    local Block=require('lu5je0.ext.git.line-log.block')
    local a=Block.new({'original'},1,1)
    local b=Block.new({'temporary'},1,1)
    require('lu5je0.ext.git.common.selected-diff').open(require('lu5je0.ext.git.common.net-diff').blocks({
      {hash='a',old_path='block.txt',path='block.txt',old_block=a,new_block=b},
      {hash='b',old_path='block.txt',path='block.txt',old_block=b,new_block=a},
    }))
  ]])
  contains(c.tree_text(), 'No net changes')
  c.q([[assert(#preview_wins()==0)]])
  c.stop()
end)

run('the four OnePlus 6 commits have no net gnome.nix changes', function()
  local original_index = vim.system({ 'git', '-C', root, 'hash-object', '.git/index' }, { text = true }):wait().stdout
  local result = vim.system({ 'git', '-C', root, 'log', '--reverse', '--pretty=format:%x1e%H%x00%h%x00%ad%x00%an%x00%s%x00%P', 'a02efde2^..472a1485' }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  local c = child('project')
  c.q(
    [[
    local root,stdout=...
    local commits=require('lu5je0.ext.sidebar.sources.history.core').parse_log(stdout)
    assert(#commits==4)
    local opts=require('lu5je0.ext.git.common.net-diff').project(commits,root)
    opts.mode='dual'
    require('lu5je0.ext.git.common.selected-diff').open(opts)
  ]],
    { root, result.stdout }
  )
  local text = c.tree_text()
  contains(text, 'Selected 4 commits')
  contains(text, 'phone.nix')
  excludes(text, 'gnome.nix')
  c.dual_ready()
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  assert(original_index == vim.system({ 'git', '-C', root, 'hash-object', '.git/index' }, { text = true }):wait().stdout, 'original repository index changed')
  c.stop()
end)

run('History hosts the project tree, isolates page mappings and restores selection', function()
  local c = child('project')
  c.q([[
    local s = require('lu5je0.ext.sidebar.state')
    assert(s.win == log_win and s.buf == log_buf)
    assert(s.active_tab_idx == require('lu5je0.ext.sidebar.config').tab_idx('history'))
    assert(vim.bo[log_buf].filetype == 'Sidebar')
    assert(vim.api.nvim_win_get_height(log_win) == vim.api.nvim_win_get_height(1000))
    assert(vim.api.nvim_win_get_width(log_win) == 50)
    assert(vim.fn.maparg('dd', 'n') == '')
  ]])
  c.go('picked-rename')
  c.feed('<Mark>l')
  c.go('renamed.txt')
  c.feed('<Space>')
  c.wait([[local d=require('lu5je0.ext.sidebar.state').diff_preview; return d.win_single ~= nil and vim.api.nvim_win_is_valid(d.win_single)]])
  c.q([[
    local s = require('lu5je0.ext.sidebar.state')
    local h = s.history
    assert(vim.api.nvim_win_get_width(s.win) == 50)
    assert(vim.wo[s.win].winfixbuf)
    assert(vim.api.nvim_win_get_config(s.diff_preview.win_single).relative == 'editor')
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(1000)):find('renamed.txt',1,true))
    require('lu5je0.ext.sidebar.actions.diff_preview').toggle_mode()
    require('lu5je0.ext.sidebar.actions.preview').refresh()
    require('lu5je0.ext.sidebar.tabs').switch_to(require('lu5je0.ext.sidebar.config').tab_idx('buffers'))
    assert(s.diff_preview.win_single == nil and s.diff_preview.win_left == nil)
    assert(vim.fn.maparg('d','n') == '')
    _G.buffers_text = vim.api.nvim_buf_get_lines(s.buf,0,-1,false)
  ]])
  vim.wait(200, function()
    return false
  end)
  c.q([[
    local s = require('lu5je0.ext.sidebar.state')
    assert(vim.deep_equal(buffers_text,vim.api.nvim_buf_get_lines(s.buf,0,-1,false)))
    assert(#vim.api.nvim_buf_get_extmarks(s.buf,vim.api.nvim_create_namespace('git_commit_selection'),0,-1,{})==0)
    require('lu5je0.ext.sidebar.tabs').switch_to(require('lu5je0.ext.sidebar.config').tab_idx('history'))
    assert(vim.tbl_count(s.history.selected_commits)==1)
    assert(#vim.api.nvim_buf_get_extmarks(s.buf,vim.api.nvim_create_namespace('git_commit_selection'),0,-1,{})==1)
  ]])
  c.feed('q')
  c.q([[assert(not require('lu5je0.ext.sidebar.state'):is_open())]])
  c.feed(',gl')
  c.wait([[return require('lu5je0.ext.sidebar.state'):is_open()]])
  c.q([[assert(vim.tbl_count(require('lu5je0.ext.sidebar.state').history.selected_commits)==1)]])
  c.stop()
end)

run('History graph toggle preserves cursor selection and uses disjoint highlight spans', function()
  local c = child('project')
  c.go('picked-change')
  c.feed('m')
  c.q([[
    local state=require('lu5je0.ext.sidebar.state')
    _G.graph_cursor=vim.api.nvim_win_get_cursor(state.win)
    _G.initial_lines=vim.api.nvim_buf_get_lines(state.buf,0,-1,false)
    function check_history_highlights()
      local source=require('lu5je0.ext.sidebar.sources.history')
      local spec=source._spec
      local lines,items,hls,vt=require('lu5je0.ext.sidebar.render').render_tree(spec.build(state.history),spec.render_opts())
      spec.decorate(state.history,lines,items,hls,vt)
      local groups={}
      for _,hl in ipairs(hls) do
        if hl.col_start<hl.col_end then
          local ranges=groups[hl.line] or {}; groups[hl.line]=ranges
          for _,previous in ipairs(ranges) do
            assert(hl.col_end<=previous.col_start or hl.col_start>=previous.col_end, 'overlapping colors: '..hl.hl..' / '..previous.hl)
          end
          ranges[#ranges+1]=hl
        end
      end
    end
    check_history_highlights()
  ]])
  c.feed('gG')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    assert(s.history.graph_enabled and #s.history.graph_rows==#s.history.commits)
    assert(vim.deep_equal(graph_cursor,vim.api.nvim_win_get_cursor(s.win)))
    assert(vim.tbl_count(s.history.selected_commits)==1)
    local lines=vim.api.nvim_buf_get_lines(s.buf,0,-1,false)
    for i,row in ipairs(s.history.graph_rows) do
      if row.width==1 then
        local hash=s.history.commits[i].short_hash
        local before=initial_lines[i]:find(hash,1,true)
        local after=lines[i]:find(hash,1,true)
        assert(vim.fn.strdisplaywidth(initial_lines[i]:sub(1,before-1))==vim.fn.strdisplaywidth(lines[i]:sub(1,after-1)), 'gG must not shift the single-lane hash column')
      end
    end
    _G.cached_graph=s.history.graph_rows
    check_history_highlights()
  ]])
  c.feed('gG')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    assert(not s.history.graph_enabled)
    assert(vim.deep_equal(initial_lines,vim.api.nvim_buf_get_lines(s.buf,0,-1,false)))
    check_history_highlights()
  ]])
  c.feed('gG')
  c.q([[assert(require('lu5je0.ext.sidebar.state').history.graph_rows==cached_graph)]])
  c.feed('U')
  c.feed('l')
  c.go('demo.txt')
  c.feed('<Space>')
  c.wait([[return require('lu5je0.ext.sidebar.state').diff_preview.win_single~=nil]])
  c.feed('<Esc>q,gl')
  c.q([[assert(require('lu5je0.ext.sidebar.state').history.graph_enabled)]])
  c.stop()
end)

run('History commits and Changes sections keep cursor on l while directories enter children', function()
  write('cursor-dir/child.txt', { 'untracked' })
  local c = child('project')
  c.go('picked-change')
  c.q([=[_G.saved_row=vim.api.nvim_win_get_cursor(log_win)[1]]=])
  c.feed('l')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    assert(vim.api.nvim_win_get_cursor(s.win)[1]==saved_row)
    assert(s.history.display_items[saved_row].node.commit.expanded)
  ]=])
  c.feed('l')
  c.q([=[assert(vim.api.nvim_win_get_cursor(log_win)[1]==saved_row, 'l on an expanded commit must stay put')]=])
  c.go('nested/dir')
  c.feed('h')
  c.feed('l')
  c.q([=[assert(vim.api.nvim_get_current_line():find('one.txt',1,true), 'directory l must still enter its first child')]=])
  c.q([=[vim.cmd.cd(...)]=], { repo })
  c.feed(',gs')
  c.wait([=[return table.concat(vim.api.nvim_buf_get_lines(log_buf,0,-1,false),'\n'):find('cursor-dir',1,true)~=nil]=])
  c.feed('ggh')
  c.feed('l')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    assert(vim.api.nvim_win_get_cursor(s.win)[1]==1)
    assert(s.git_changes.display_items[1]._is_section and s.git_changes.display_items[1].node.expanded)
  ]=])
  c.feed('l')
  c.q([=[assert(vim.api.nvim_win_get_cursor(log_win)[1]==1)]=])
  c.go('cursor-dir')
  c.feed('hl')
  c.q([=[assert(vim.api.nvim_get_current_line():find('child.txt',1,true), 'Changes directory l must still enter its first child')]=])
  c.stop()
  vim.fn.delete(repo .. '/cursor-dir', 'rf')
end)

run('History navigation respects typed key order and closes the actual parent', function()
  local c = child('project')
  c.feed('ggjl')
  c.q([[
    local h=require('lu5je0.ext.sidebar.state').history
    assert(not h.commits[1].expanded, 'j/l must not expand the previous commit')
    assert(h.commits[2].expanded, 'j/l must expand the second commit')
  ]])
  c.go('picked-change')
  c.feed('l')
  c.go('demo.txt')
  c.feed('h')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    local line=vim.api.nvim_win_get_cursor(s.win)[1]
    local item=s.history.display_items[line]
    assert(item.type=='commit' and item.node.commit.message=='picked-change')
    assert(not item.node.commit.expanded, 'h must close the owning commit, not an unrelated directory')
  ]])
  c.feed('h')
  c.q([[
    local h=require('lu5je0.ext.sidebar.state').history
    assert(h.commits[2].expanded, 'h on a folded commit must not close a preceding commit')
  ]])
  c.stop()
end)

run('History preserves child folds when reopening parents and reveals jump targets', function()
  write('fold-parent/child/one.txt', { 'one' })
  write('fold-parent/sibling.txt', { 'sibling' })
  local fold_commit = commit('fold-state')
  local c = child('project')
  c.go('fold-state')
  c.feed('l')
  c.go('one.txt')
  -- Fold the leaf directory and then its parent, retaining both fold flags.
  c.feed('hh')
  c.feed('l')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(item.node.name=='child' and not item.node.expanded, 'reopening a parent must preserve its folded child')
    for _,child in ipairs(s.history.display_items) do
      assert(child.node.name~='one.txt', 'files under the folded child must remain hidden')
    end
  ]=])
  c.feed('hh')
  c.feed('<CR>')
  c.go('fold-parent')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(not item.node.expanded, 'reopening a commit must preserve its folded directories')
  ]=])
  c.feed('l')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(item.node.name=='child' and not item.node.expanded, 'nested fold state must survive closing the commit')
  ]=])
  c.feed('l')
  c.go('one.txt')
  c.q([=[require('lu5je0.ext.sidebar.sources.history').open({jump_to_sha=...,jump_to_file='fold-parent/child/one.txt'})]=], { fold_commit })
  c.wait([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    return item and item.node.rel_path=='fold-parent/child/one.txt'
  ]=])
  c.stop()
end)

run('History opens and closes a whole single-directory chain and stops at branches', function()
  write('chain/a/b/leaf/one.txt', { 'one' })
  write('chain/a/b/peer.txt', { 'peer' })
  commit('single-directory-chain')
  local c = child('project')
  c.go('single-directory-chain')
  c.feed('l')
  c.go('one.txt')
  c.feed('hh')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(item.node.name=='chain' and not item.node.expanded, 'h must collapse the whole displayed parent chain')
  ]=])
  c.feed('l')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(item.node.name=='leaf' and not item.node.expanded, 'auto expansion must stop at b with two children')
    local text=table.concat(vim.api.nvim_buf_get_lines(s.buf,0,-1,false),'\n')
    assert(text:find('chain/a/b',1,true), 'the directory chain must be expanded and compressed in one action')
    assert(not text:find('one.txt',1,true), 'folded descendants beyond the branch must stay folded')
  ]=])
  c.go('peer.txt')
  c.feed('h')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(item.node.name=='chain' and not item.node.expanded, 'h from a direct file must collapse the whole chain')
  ]=])
  c.feed('l')
  c.go('chain/a/b')
  c.feed('zc')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local item=s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]]
    assert(item.node.name=='chain' and not item.node.expanded, 'zc on the compressed row must collapse the whole chain')
  ]=])
  c.stop()
end)

run('History commit Space previews details and follows Sidebar lifecycle', function()
  local c = child('project')
  c.go('picked-rename')
  c.feed('<Space>')
  c.q([=[
    local s=require('lu5je0.ext.sidebar.state')
    local p=s.preview
    assert(p.type=='text' and p.active and vim.api.nvim_win_is_valid(p.text_win))
    assert(vim.api.nvim_get_current_win()==s.win, 'first Space must keep focus in Sidebar')
    local text=table.concat(vim.api.nvim_buf_get_lines(p.text_buf,0,-1,false),'\n')
    for _,expected in ipairs {'commit ', 'Author: Test', 'Date:', 'picked-rename', 'demo.txt → renamed.txt'} do
      assert(text:find(expected,1,true), 'missing commit detail: '..expected)
    end
    assert(vim.tbl_count(s.history.selected_commits)==0)
    assert(not s.history.display_items[vim.api.nvim_win_get_cursor(s.win)[1]].node.commit.expanded)
  ]=])
  c.feed('<Space>')
  c.q([[local s=require('lu5je0.ext.sidebar.state'); assert(vim.api.nvim_get_current_win()==s.preview.text_win)]])
  c.feed('q')
  c.q([[local s=require('lu5je0.ext.sidebar.state'); assert(s.preview.text_win==nil and s.preview.text_buf==nil); assert(vim.api.nvim_get_current_win()==s.win)]])
  c.feed('<Space>j')
  c.q([[assert(require('lu5je0.ext.sidebar.state').preview.text_win==nil, 'moving off commit must close details')]])
  c.feed('<Space><Space>')
  c.q([[local s=require('lu5je0.ext.sidebar.state'); assert(vim.api.nvim_get_current_win()==s.preview.text_win)]])
  c.feed('<Esc>')
  c.feed('<Space>')
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    _G.details_buf=s.preview.text_buf
    require('lu5je0.ext.sidebar.tabs').switch_to(require('lu5je0.ext.sidebar.config').tab_idx('files'))
    assert(s.preview.text_win==nil and not vim.api.nvim_buf_is_valid(details_buf), 'switching page must release details')
  ]])
  c.feed(',gl<Space>q')
  c.q([[local s=require('lu5je0.ext.sidebar.state'); assert(not s:is_open() and s.preview.text_win==nil)]])
  c.stop()
end)

run('History Space preview uses Changes controls and m marks commits', function()
  local c = child('project')
  c.q([[vim.keymap.set('n', '<Space><Space>', function() error('global double-Space mapping must not run in History') end)]])
  c.go('picked-change')
  c.feed('l')
  c.go('demo.txt')
  c.feed('<Space>')
  c.wait([[local d=require('lu5je0.ext.sidebar.state').diff_preview; return d.win_single~=nil]])
  c.q([[
    local s=require('lu5je0.ext.sidebar.state')
    assert(vim.tbl_count(s.history.selected_commits)==0)
    assert(vim.api.nvim_get_current_win()==s.win)
    assert(table.concat(vim.api.nvim_buf_get_lines(s.diff_preview.buf_single,0,-1,false),'\n'):find('+gamma',1,true))
  ]])
  c.feed('<Space>d')
  c.wait([[local d=require('lu5je0.ext.sidebar.state').diff_preview; return d.win_left~=nil and vim.api.nvim_get_current_win()==d.win_left]])
  c.feed('cq')
  c.wait([[local s=require('lu5je0.ext.sidebar.state'); return s.diff_preview.win_left==nil and vim.api.nvim_get_current_win()==s.win]])
  c.feed('<Space><Space>')
  c.wait([[local s=require('lu5je0.ext.sidebar.state'); local d=s.diff_preview; return d.win_left~=nil and vim.api.nvim_get_current_win()==d.win_left]])
  c.feed('q')
  c.wait([[return vim.api.nvim_get_current_win()==log_win]])
  c.feed('m')
  c.selected(1)
  c.feed('U')
  c.selected(0)
  c.go('picked-rename')
  c.feed('lj<CR>')
  c.q([[assert(vim.api.nvim_get_current_win()~=log_win); assert(vim.api.nvim_buf_get_name(0):find('renamed.txt',1,true))]])
  c.stop()
end)

run('Files Symbols Changes are default tabs while History and Buffers are transient', function()
  local c = child('project')
  c.q([[
    local cfg=require('lu5je0.ext.sidebar.config')
    local tabs=require('lu5je0.ext.sidebar.tabs')
    assert(vim.deep_equal(vim.list_slice(tabs.visible_indices(),1,3),{cfg.tab_idx('files'),cfg.tab_idx('symbols'),cfg.tab_idx('git_changes')}))
    assert(not vim.tbl_contains(tabs.visible_indices(),cfg.tab_idx('buffers')))
    tabs.next_tab()
    assert(require('lu5je0.ext.sidebar.state').active_tab_idx==cfg.tab_idx('files'))
    tabs.prev_tab()
    assert(require('lu5je0.ext.sidebar.state').active_tab_idx==cfg.tab_idx('history'))
  ]])
  c.feed(',gs')
  c.q([[
    local cfg=require('lu5je0.ext.sidebar.config')
    assert(require('lu5je0.ext.sidebar.state').active_tab_idx==cfg.tab_idx('git_changes'))
    assert(vim.tbl_contains(require('lu5je0.ext.sidebar.tabs').visible_indices(),cfg.tab_idx('git_changes')))
  ]])
  c.feed('q,fb')
  c.q([[
    local cfg=require('lu5je0.ext.sidebar.config')
    local tabs=require('lu5je0.ext.sidebar.tabs')
    assert(require('lu5je0.ext.sidebar.state').active_tab_idx==cfg.tab_idx('buffers'))
    assert(vim.tbl_contains(tabs.visible_indices(),cfg.tab_idx('buffers')))
    assert(vim.deep_equal(vim.list_slice(tabs.visible_indices(),1,3),{cfg.tab_idx('files'),cfg.tab_idx('symbols'),cfg.tab_idx('git_changes')}))
  ]])
  c.feed('q')
  c.q([[
    local cfg=require('lu5je0.ext.sidebar.config')
    assert(vim.deep_equal(require('lu5je0.ext.sidebar.tabs').visible_indices(),{cfg.tab_idx('files'),cfg.tab_idx('symbols'),cfg.tab_idx('git_changes')}))
  ]])
  c.feed(',gl')
  c.q([[
    local cfg=require('lu5je0.ext.sidebar.config')
    local indices=require('lu5je0.ext.sidebar.tabs').visible_indices()
    assert(not vim.tbl_contains(indices,cfg.tab_idx('buffers')))
    assert(vim.tbl_contains(indices,cfg.tab_idx('git_changes')))
  ]])
  c.stop()
end)

run('History sessions belong to their tabpage and release resources on close', function()
  local c = child('project')
  c.go('picked-rename')
  c.feed('<Mark>')
  c.q(
    [[
    _G.first_history = require('lu5je0.ext.sidebar.state').history
    _G.first_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd.tabnew()
    vim.cmd.edit(...)
    require('lu5je0.ext.sidebar.sources.history').open()
    _G.second_history = require('lu5je0.ext.sidebar.state').history
    assert(second_history ~= first_history)
  ]],
    { repo .. '/renamed.txt' }
  )
  c.wait([[return #second_history.commits > 0 and not second_history.loading]])
  c.q([[
    assert(vim.tbl_count(second_history.selected_commits)==0)
    vim.cmd.tabclose()
  ]])
  c.wait([[return second_history.job == nil and not second_history.loading]])
  c.q([[
    assert(vim.api.nvim_get_current_tabpage()==first_tab)
    assert(require('lu5je0.ext.sidebar.state').history == first_history)
    assert(vim.tbl_count(first_history.selected_commits)==1)
  ]])
  c.stop()
end)

run('closing a pending merge invokes cleanup and suppresses late callbacks', function()
  local c = child('project')
  c.q([[
    _G.cleaned=false
    require('lu5je0.ext.git.common.selected-diff').open({
      cleanup=function() _G.cleaned=true end,
      prepare=function(run,done)
        run({'sh','-c','sleep 0.3'},nil,function() done({}) end)
      end,
    })
  ]])
  c.feed('q')
  c.wait([[return #vim.api.nvim_list_tabpages()==1]])
  vim.wait(400, function()
    return false
  end)
  c.q([[
    assert(_G.cleaned)
    assert(#vim.api.nvim_list_tabpages()==1)
    assert(vim.api.nvim_get_current_win()==log_win, vim.inspect({current=vim.api.nvim_get_current_win(), expected=log_win, messages=vim.api.nvim_exec2('messages',{output=true}).output}))
    assert(vim.api.nvim_exec2('messages',{output=true}).output=='', vim.api.nvim_exec2('messages',{output=true}).output)
  ]])
  c.stop()
end)

for _, chan in ipairs(children) do
  pcall(vim.fn.jobstop, chan)
end
vim.fn.delete(repo, 'rf')
print(string.format('%d passed, %d failed', passed, failed))
if failed > 0 then
  os.exit(1)
end
