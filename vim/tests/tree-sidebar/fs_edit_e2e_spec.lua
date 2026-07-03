-- fs-edit end-to-end tests: real tempdir + real buffer + direct action execution.
-- Verifies disk state after operations.
-- Usage: cd vim && nvim --headless -u NONE -l tests/tree-sidebar/fs_edit_e2e_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local fs_edit = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit')
local actions_mod = require('lu5je0.ext.tree-sidebar.sources.files.fs-edit.actions')
local parse_line = actions_mod.parse_line

-- ============================================================================
-- Helpers
-- ============================================================================

local function mkdir(path) vim.fn.mkdir(path, 'p') end
local function writefile(path, content) vim.fn.writefile(content or {''}, path) end
local function exists(path) return vim.uv.fs_stat(path) ~= nil end
local function isdir(path) local s = vim.uv.fs_stat(path); return s and s.type == 'directory' end
local function isfile(path) local s = vim.uv.fs_stat(path); return s and s.type == 'file' end
local function readfile(path) return table.concat(vim.fn.readfile(path), '\n') end

local function make_fixture()
  local tmp = vim.fn.tempname()
  mkdir(tmp)
  mkdir(tmp .. '/src')
  writefile(tmp .. '/src/a.txt', {'aaa'})
  writefile(tmp .. '/src/b.txt', {'bbb'})
  writefile(tmp .. '/top.txt', {'top'})
  return tmp
end

local function gsub(s, pat, rep) return (s:gsub(pat, rep)) end

-- Open fs-edit, return buf and execute helper.
-- The execute helper bypasses confirm UI: computes actions and runs them directly.
local function open_and_helpers(dir_path)
  fs_edit.open_dir(dir_path, { inplace = true })
  local buf = vim.api.nvim_get_current_buf()

  -- Find session by scanning private state
  local sessions = debug.getupvalue and nil
  -- Alternative: use _parse_line + _compute_actions exposed on module
  -- We access session via the BufWriteCmd closure. But simpler: extract from
  -- the module's internal table by iterating buffers. The module stores sessions
  -- keyed by buf in a local `sessions` table. We can poke at it by reading the
  -- upvalue of the BufWriteCmd autocmd callback.
  local session
  do
    local autocmds = vim.api.nvim_get_autocmds({ event = 'BufWriteCmd', buffer = buf })
    if #autocmds > 0 and autocmds[1].callback then
      -- The callback is `function() mutate(session) end` where session is upvalue
      local i = 1
      while true do
        local name, val = debug.getupvalue(autocmds[1].callback, i)
        if not name then break end
        if name == 'session' then session = val; break end
        i = i + 1
      end
    end
  end

  local function do_save()
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local buf_lines = actions_mod.effective_buf_lines(session, all_lines)
    local actions = actions_mod.compute_actions(session, buf_lines)
    actions_mod.add_implicit_creates(actions, session.root_dir)
    actions_mod.execute_actions(actions)
    -- reset session
    session.store = {}
    session.next_id = 1
    session.id_to_path = {}
    session.path_to_id = {}
    session.saved_children = {}
    session.copy_shadow = {}
    session.copy_snapshot = {}
  end

  -- Simulate on_enter (expand/collapse) by calling the CR keymap
  local function do_enter(line_nr)
    vim.api.nvim_win_set_cursor(0, { line_nr, 0 })
    -- The CR keymap calls on_enter(session). Find it via keymap.
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    for _, m in ipairs(maps) do
      if m.lhs == '<CR>' then
        if m.callback then
          m.callback()
        end
        return
      end
    end
  end

  return buf, session, do_save, do_enter
end

local function find_line(buf, pattern, after)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = (after or 1), #lines do
    if lines[i]:find(pattern, 1, true) then return i end
  end
  return nil
end

local function buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

-- ============================================================================
r.group('e2e: rename dir + expand + rename child + save')
-- ============================================================================

r.run('disk reflects both renames', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Rename src/ → dst/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line, 'src/ not found')
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line - 1, src_line, false,
    { gsub(lines[src_line], 'src/', 'dst/') })

  -- Expand dst/
  do_enter(src_line)

  -- Rename a.txt → a2.txt
  local a_line = find_line(buf, 'a.txt', src_line + 1)
  r.assert_truthy(a_line, 'a.txt not found')
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', 'a2.txt') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/dst'), 'dst/ should exist')
  r.assert_truthy(not exists(tmp .. '/src'), 'src/ should not exist')
  r.assert_truthy(isfile(tmp .. '/dst/a2.txt'), 'dst/a2.txt should exist')
  r.assert_truthy(isfile(tmp .. '/dst/b.txt'), 'dst/b.txt should exist')
  r.assert_eq(readfile(tmp .. '/dst/a2.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + rename child + save')
-- ============================================================================

r.run('original preserved, copy has renamed child', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Duplicate src/ line and rename copy to dst/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  local src_text = lines[src_line]
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { src_text })
  local copy_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'src/', 'dst/') })

  -- Expand dst/ (triggers phantom re-id + phantom children)
  do_enter(copy_line)

  -- Rename a.txt → a2.txt inside dst/
  local a_line = find_line(buf, 'a.txt', copy_line + 1)
  r.assert_truthy(a_line, 'a.txt not found')
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', 'a2.txt') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/src'), 'src/ preserved')
  r.assert_truthy(isfile(tmp .. '/src/a.txt'), 'src/a.txt preserved')
  r.assert_truthy(isdir(tmp .. '/dst'), 'dst/ should exist')
  r.assert_truthy(isfile(tmp .. '/dst/a2.txt'), 'dst/a2.txt should exist')
  r.assert_truthy(isfile(tmp .. '/dst/b.txt'), 'dst/b.txt should exist')
  r.assert_eq(readfile(tmp .. '/dst/a2.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + delete all children + save')
-- ============================================================================

r.run('only empty dir created', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { lines[src_line] })
  local copy_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'src/', 'empty/') })

  -- Expand
  do_enter(copy_line)

  -- Delete all children
  lines = buf_lines(buf)
  local _, _, parent_depth = parse_line(lines[copy_line])
  local del_end = copy_line
  for i = copy_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= parent_depth then break end
    del_end = i
  end
  if del_end > copy_line then
    vim.api.nvim_buf_set_lines(buf, copy_line, del_end, false, {})
  end

  do_save()

  r.assert_truthy(isdir(tmp .. '/empty'), 'empty/ should exist')
  local handle = vim.uv.fs_scandir(tmp .. '/empty')
  local first = handle and vim.uv.fs_scandir_next(handle)
  r.assert_eq(first, nil)
  r.assert_truthy(isfile(tmp .. '/src/a.txt'), 'src/a.txt intact')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir unexpanded + save = bulk copy')
-- ============================================================================

r.run('bulk copy works', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { lines[src_line] })
  local copy_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'src/', 'dup/') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/dup'), 'dup/ should exist')
  r.assert_truthy(isfile(tmp .. '/dup/a.txt'))
  r.assert_truthy(isfile(tmp .. '/dup/b.txt'))
  r.assert_eq(readfile(tmp .. '/dup/a.txt'), 'aaa')
  r.assert_truthy(isdir(tmp .. '/src'), 'src/ preserved')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: multi-relocate (yy+p twice, rename both, delete original)')
-- ============================================================================

r.run('two copies created, original gone', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local top_line = find_line(buf, 'top.txt')
  r.assert_truthy(top_line)
  local lines = buf_lines(buf)
  local top_text = lines[top_line]
  -- Paste two copies below
  vim.api.nvim_buf_set_lines(buf, top_line, top_line, false, { top_text, top_text })
  -- Rename copies
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, top_line, top_line + 2, false, {
    gsub(lines[top_line + 1], 'top%.txt', 't1.txt'),
    gsub(lines[top_line + 2], 'top%.txt', 't2.txt'),
  })
  -- Delete original
  vim.api.nvim_buf_set_lines(buf, top_line - 1, top_line, false, {})

  do_save()

  r.assert_truthy(not exists(tmp .. '/top.txt'), 'top.txt gone')
  r.assert_truthy(isfile(tmp .. '/t1.txt'), 't1.txt exists')
  r.assert_truthy(isfile(tmp .. '/t2.txt'), 't2.txt exists')
  r.assert_eq(readfile(tmp .. '/t1.txt'), 'top')
  r.assert_eq(readfile(tmp .. '/t2.txt'), 'top')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: path swap')
-- ============================================================================

r.run('A and B swapped on disk', function()
  local tmp = make_fixture()
  writefile(tmp .. '/x.txt', {'XX'})
  writefile(tmp .. '/y.txt', {'YY'})
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Find x.txt and y.txt by ID
  local lines = buf_lines(buf)
  local x_line, y_line
  for i, l in ipairs(lines) do
    local _, name = parse_line(l)
    if name == 'x.txt' then x_line = i end
    if name == 'y.txt' then y_line = i end
  end
  r.assert_truthy(x_line, 'x.txt not found')
  r.assert_truthy(y_line, 'y.txt not found')

  -- Swap names in buffer
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, x_line - 1, x_line, false,
    { gsub(lines[x_line], 'x%.txt', 'y.txt') })
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, y_line - 1, y_line, false,
    { gsub(lines[y_line], 'y%.txt', 'x.txt') })

  do_save()

  r.assert_eq(readfile(tmp .. '/x.txt'), 'YY')
  r.assert_eq(readfile(tmp .. '/y.txt'), 'XX')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy of copy (chain)')
-- ============================================================================

r.run('chain copy produces correct disk layout', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Copy src/ → dst/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { lines[src_line] })
  local dst_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, dst_line - 1, dst_line, false,
    { gsub(lines[dst_line], 'src/', 'dst/') })

  -- Expand dst/
  do_enter(dst_line)

  -- Inside dst/, duplicate the dst/ dir line (same id as dst/) to get dst/sub/
  -- Actually we need to copy one of the phantom children as a dir... simpler:
  -- Just save dst/ with children as-is, verify bulk works, then trust chain
  -- For true chain: copy dst/ line again below src/
  lines = buf_lines(buf)
  -- Find dst/ line (it's at dst_line still)
  local dst_text = lines[dst_line]
  -- Insert copy after all dst children
  local _, _, dst_depth = parse_line(dst_text)
  local insert_after = dst_line
  for i = dst_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= dst_depth then break end
    insert_after = i
  end
  vim.api.nvim_buf_set_lines(buf, insert_after, insert_after, false, { dst_text })
  local chain_line = insert_after + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, chain_line - 1, chain_line, false,
    { gsub(lines[chain_line], 'dst/', 'chain/') })

  -- Expand chain/ (triggers re-id since dst/ id appears multiple times)
  do_enter(chain_line)

  do_save()

  r.assert_truthy(isdir(tmp .. '/src'), 'src/ preserved')
  r.assert_truthy(isdir(tmp .. '/dst'), 'dst/ exists')
  r.assert_truthy(isfile(tmp .. '/dst/a.txt'))
  r.assert_truthy(isdir(tmp .. '/chain'), 'chain/ exists')
  r.assert_truthy(isfile(tmp .. '/chain/a.txt'))
  r.assert_truthy(isfile(tmp .. '/chain/b.txt'))

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: self-reference paste inside dir')
-- ============================================================================

r.run('expanding self-ref copy does not contain itself', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  do_enter(src_line)

  -- Paste src/ inside itself (insert src/ line as child of src/)
  local lines = buf_lines(buf)
  local src_text = lines[src_line]
  -- Find end of src/ children
  local _, _, src_depth = parse_line(src_text)
  local last_child = src_line
  for i = src_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= src_depth then break end
    last_child = i
  end
  -- Insert self-reference as child (same id, indented)
  local child_indent = string.rep('  ', src_depth + 1)
  local self_ref = src_text:gsub('^%s*', child_indent)
  vim.api.nvim_buf_set_lines(buf, last_child, last_child, false, { self_ref })

  -- Expand the self-reference
  local self_line = last_child + 1
  do_enter(self_line)

  -- Check: the expanded self-reference should NOT contain another src/
  lines = buf_lines(buf)
  local _, _, self_depth = parse_line(lines[self_line])
  local found_recursive = false
  for i = self_line + 1, #lines do
    local _, name, d, is_dir = parse_line(lines[i])
    if d <= self_depth then break end
    if is_dir and name == 'src/' then
      found_recursive = true
      break
    end
  end
  r.assert_truthy(not found_recursive, 'no recursive src/ inside self-reference')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: rename dir + expand + mixed child edits + save')
-- ============================================================================

r.run('rename child + delete another child', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  do_enter(src_line)

  -- Rename a.txt → a2.txt
  local a_line = find_line(buf, 'a.txt', src_line + 1)
  r.assert_truthy(a_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', 'a2.txt') })

  -- Delete b.txt
  local b_line = find_line(buf, 'b.txt', src_line + 1)
  r.assert_truthy(b_line)
  vim.api.nvim_buf_set_lines(buf, b_line - 1, b_line, false, {})

  do_save()

  r.assert_truthy(isdir(tmp .. '/src'), 'src/ exists')
  r.assert_truthy(isfile(tmp .. '/src/a2.txt'), 'a2.txt exists')
  r.assert_truthy(not exists(tmp .. '/src/a.txt'), 'a.txt gone')
  r.assert_truthy(not exists(tmp .. '/src/b.txt'), 'b.txt gone')
  r.assert_eq(readfile(tmp .. '/src/a2.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + collapse (with edits) + save')
-- ============================================================================

r.run('edits inside collapsed copy still apply on save', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Copy src/ → dst/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { lines[src_line] })
  local copy_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'src/', 'dst/') })

  -- Expand dst/
  do_enter(copy_line)

  -- Rename a.txt → renamed.txt
  local a_line = find_line(buf, 'a.txt', copy_line + 1)
  r.assert_truthy(a_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', 'renamed.txt') })

  -- Collapse dst/
  do_enter(copy_line)

  -- Save (collapsed state; edits should be in saved_children)
  do_save()

  r.assert_truthy(isdir(tmp .. '/dst'), 'dst/ exists')
  r.assert_truthy(isfile(tmp .. '/dst/renamed.txt'), 'renamed.txt exists')
  r.assert_truthy(isfile(tmp .. '/dst/b.txt'), 'b.txt exists')
  r.assert_eq(readfile(tmp .. '/dst/renamed.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + no edits + save = bulk copy')
-- ============================================================================

r.run('expanded but unmodified phantom = bulk copy', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { lines[src_line] })
  local copy_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'src/', 'dup2/') })

  -- Expand dup2/ but don't change anything
  do_enter(copy_line)

  do_save()

  r.assert_truthy(isdir(tmp .. '/dup2'), 'dup2/ exists')
  r.assert_truthy(isfile(tmp .. '/dup2/a.txt'))
  r.assert_truthy(isfile(tmp .. '/dup2/b.txt'))
  r.assert_eq(readfile(tmp .. '/dup2/a.txt'), 'aaa')
  r.assert_eq(readfile(tmp .. '/dup2/b.txt'), 'bbb')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: simple rename dir (no expand)')
-- ============================================================================

r.run('dir renamed on disk without expand', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line - 1, src_line, false,
    { gsub(lines[src_line], 'src/', 'renamed_dir/') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/renamed_dir'), 'renamed_dir/ exists')
  r.assert_truthy(not exists(tmp .. '/src'), 'src/ gone')
  r.assert_truthy(isfile(tmp .. '/renamed_dir/a.txt'), 'contents preserved')
  r.assert_truthy(isfile(tmp .. '/renamed_dir/b.txt'))

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: create new file + new dir')
-- ============================================================================

r.run('new file and dir created on disk', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Add new lines at end of buffer
  local lines = buf_lines(buf)
  local count = #lines
  vim.api.nvim_buf_set_lines(buf, count, count, false, { 'newfile.txt', 'newdir/' })

  do_save()

  r.assert_truthy(isfile(tmp .. '/newfile.txt'), 'newfile.txt created')
  r.assert_truthy(isdir(tmp .. '/newdir'), 'newdir/ created')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: move file into dir')
-- ============================================================================

r.run('file moved inside expanded dir on disk', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  do_enter(src_line)

  -- Find top.txt and move it into src/ (indent it as child of src/)
  local top_line = find_line(buf, 'top.txt')
  r.assert_truthy(top_line)
  local lines = buf_lines(buf)
  local top_text = lines[top_line]
  -- Remove from current position
  vim.api.nvim_buf_set_lines(buf, top_line - 1, top_line, false, {})
  -- Insert as child of src/ (after src/ line with one level indent)
  local _, _, src_depth = parse_line(buf_lines(buf)[src_line])
  local child_indent = string.rep('  ', src_depth + 1)
  -- Extract just the id+name part
  local id_part = top_text:match('^%s*(.*)')
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { child_indent .. id_part })

  do_save()

  r.assert_truthy(not exists(tmp .. '/top.txt'), 'top.txt gone from root')
  r.assert_truthy(isfile(tmp .. '/src/top.txt'), 'top.txt inside src/')
  r.assert_eq(readfile(tmp .. '/src/top.txt'), 'top')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + rename child + delete same child from source')
-- ============================================================================

r.run('copy reads before source delete runs', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/ first
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  do_enter(src_line)

  -- Copy src/ → dst/ (insert after src/ and its children)
  local lines = buf_lines(buf)
  local _, _, src_depth = parse_line(lines[src_line])
  local insert_after = src_line
  for i = src_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= src_depth then break end
    insert_after = i
  end
  vim.api.nvim_buf_set_lines(buf, insert_after, insert_after, false, { lines[src_line] })
  local copy_line = insert_after + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'src/', 'dst/') })

  -- Expand dst/
  do_enter(copy_line)

  -- Rename a.txt inside dst/ to a_copy.txt
  local dst_a_line
  lines = buf_lines(buf)
  for i = copy_line + 1, #lines do
    if lines[i]:find('a.txt', 1, true) then
      dst_a_line = i
      break
    end
  end
  r.assert_truthy(dst_a_line)
  vim.api.nvim_buf_set_lines(buf, dst_a_line - 1, dst_a_line, false,
    { gsub(lines[dst_a_line], 'a%.txt', 'a_copy.txt') })

  -- Delete a.txt from src/ (the original)
  local src_a_line = find_line(buf, 'a.txt', src_line + 1)
  r.assert_truthy(src_a_line)
  vim.api.nvim_buf_set_lines(buf, src_a_line - 1, src_a_line, false, {})

  do_save()

  -- src/ should no longer have a.txt
  r.assert_truthy(not exists(tmp .. '/src/a.txt'), 'src/a.txt deleted')
  r.assert_truthy(isfile(tmp .. '/src/b.txt'), 'src/b.txt preserved')
  -- dst/ should have a_copy.txt (copied from a.txt before it was deleted)
  r.assert_truthy(isdir(tmp .. '/dst'), 'dst/ exists')
  r.assert_truthy(isfile(tmp .. '/dst/a_copy.txt'), 'dst/a_copy.txt exists')
  r.assert_eq(readfile(tmp .. '/dst/a_copy.txt'), 'aaa')
  r.assert_truthy(isfile(tmp .. '/dst/b.txt'), 'dst/b.txt exists')

  vim.fn.delete(tmp, 'rf')
end)

r.finish()

