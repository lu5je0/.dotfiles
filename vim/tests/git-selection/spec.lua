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
  local chan = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-n', '-i', 'NONE', '-u', 'NONE', '--cmd', 'set rtp+=' .. root .. '/vim' }, { rpc = true })
  assert(chan > 0)
  children[#children + 1] = chan
  local c = {}
  function c.q(code, args)
    return vim.rpcrequest(chan, 'nvim_exec_lua', code, args or {})
  end
  function c.feed(keys)
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
    _G.saved_diff_prefs = { line_log_diff_mode = mode, line_log_diff_changes_only = false }
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
    c.feed('<Space>')
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
      c.feed('<CR>')
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
      c.wait(([[
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
      ]]):format(expected[2], tostring(expected[3]), tostring(expected[2] == 'dual'), tostring(expected[3]), expected[2] == 'dual' and 2 or 1))
    end
    c.stop()
  end)
end

run('continuous selection: one net patch per path, original marks survive tree expansion', function()
  local index_before = git { 'hash-object', '.git/index' }
  local c = child('project')
  for _, name in ipairs { 'picked-root', 'skipped-middle', 'picked-change' } do
    c.go(name)
    c.feed('<Space>')
  end
  c.selected(3)
  c.feed('l')
  c.q([[
    assert(#vim.api.nvim_buf_get_extmarks(log_buf,vim.api.nvim_create_namespace('git_commit_selection'),0,-1,{})==3)
  ]])
  c.feed('<Space>')
  c.selected(2)
  c.feed('<Space>')
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
  c.feed(top .. 'GV' .. bottom .. 'G<Space>')
  c.selected(3)
  c.feed('<Space>')
  c.q([[assert(not vim.wo[log_win].statusline:find('selected',1,true))]])
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

run('root, rename, deletion and untracked changes retain their net semantics', function()
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
  c.feed('U')
  pick_commits(c, { 'local change' })
  contains(c.tree_text(), 'untracked.txt')
  contains(c.preview(), '+local new file')
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
    local commits=require('lu5je0.ext.git.project-log.core').parse_log(stdout)
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
    assert(vim.api.nvim_get_current_win()==log_win)
    assert(vim.api.nvim_exec2('messages',{output=true}).output=='')
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
