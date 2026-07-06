-- fs-edit end-to-end tests: real tempdir + real buffer + direct action execution.
-- Verifies disk state after operations.
-- Usage: cd vim && nvim --headless -u NONE -l tests/sidebar/fs_edit_e2e_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
local r = h.make_runner()

local fs_edit = require('lu5je0.ext.sidebar.sources.files.fs-edit')
local actions_mod = require('lu5je0.ext.sidebar.sources.files.fs-edit.actions')
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
    local dupes = actions_mod.check_duplicates(session, buf_lines)
    if #dupes > 0 then
      error('do_save: duplicates detected: ' .. table.concat(dupes, ', '), 2)
    end
    local actions = actions_mod.compute_actions(session, buf_lines)
    if #actions == 0 then return end
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

-- ============================================================================
r.group('e2e: simple file rename')
-- ============================================================================

r.run('file renamed on disk', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local top_line = find_line(buf, 'top.txt')
  r.assert_truthy(top_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, top_line - 1, top_line, false,
    { gsub(lines[top_line], 'top%.txt', 'bottom.txt') })

  do_save()

  r.assert_truthy(not exists(tmp .. '/top.txt'), 'top.txt gone')
  r.assert_truthy(isfile(tmp .. '/bottom.txt'), 'bottom.txt exists')
  r.assert_eq(readfile(tmp .. '/bottom.txt'), 'top')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: delete file')
-- ============================================================================

r.run('file removed from disk', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local top_line = find_line(buf, 'top.txt')
  r.assert_truthy(top_line)
  vim.api.nvim_buf_set_lines(buf, top_line - 1, top_line, false, {})

  do_save()

  r.assert_truthy(not exists(tmp .. '/top.txt'), 'top.txt deleted')
  r.assert_truthy(isdir(tmp .. '/src'), 'src/ still there')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy file (yy+p+rename)')
-- ============================================================================

r.run('file duplicated on disk', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local top_line = find_line(buf, 'top.txt')
  r.assert_truthy(top_line)
  local lines = buf_lines(buf)
  -- Duplicate and rename copy
  vim.api.nvim_buf_set_lines(buf, top_line, top_line, false,
    { gsub(lines[top_line], 'top%.txt', 'top_copy.txt') })

  do_save()

  r.assert_truthy(isfile(tmp .. '/top.txt'), 'original preserved')
  r.assert_truthy(isfile(tmp .. '/top_copy.txt'), 'copy created')
  r.assert_eq(readfile(tmp .. '/top_copy.txt'), 'top')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: move file out of dir')
-- ============================================================================

r.run('file moved from subdir to root', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  do_enter(src_line)

  -- Find a.txt inside src/ and move it to root level (remove indent)
  local a_line = find_line(buf, 'a.txt', src_line + 1)
  r.assert_truthy(a_line)
  local lines = buf_lines(buf)
  local a_text = lines[a_line]
  -- Remove from current position
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false, {})
  -- Insert at end of buffer at root depth (no indent, keep id)
  local id_part = a_text:match('^%s*(.*)')
  local total = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, total, total, false, { id_part })

  do_save()

  r.assert_truthy(isfile(tmp .. '/a.txt'), 'a.txt at root')
  r.assert_truthy(not exists(tmp .. '/src/a.txt'), 'a.txt gone from src/')
  r.assert_eq(readfile(tmp .. '/a.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: create nested path')
-- ============================================================================

r.run('intermediate dirs auto-created', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Add a new line with nested path
  local total = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, total, total, false, { 'deep/nested/file.txt' })

  do_save()

  r.assert_truthy(isdir(tmp .. '/deep'), 'deep/ created')
  r.assert_truthy(isdir(tmp .. '/deep/nested'), 'deep/nested/ created')
  r.assert_truthy(isfile(tmp .. '/deep/nested/file.txt'), 'file.txt created')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: rename dir + add new file inside')
-- ============================================================================

r.run('dir renamed and new file created inside', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Rename src/ → lib/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, src_line - 1, src_line, false,
    { gsub(lines[src_line], 'src/', 'lib/') })

  -- Expand lib/
  do_enter(src_line)

  -- Add new file inside lib/
  lines = buf_lines(buf)
  local _, _, src_depth = parse_line(lines[src_line])
  local child_indent = string.rep('  ', src_depth + 1)
  -- Insert after last child
  local insert_pos = src_line
  for i = src_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= src_depth then break end
    insert_pos = i
  end
  vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false,
    { child_indent .. 'new.lua' })

  do_save()

  r.assert_truthy(isdir(tmp .. '/lib'), 'lib/ exists')
  r.assert_truthy(not exists(tmp .. '/src'), 'src/ gone')
  r.assert_truthy(isfile(tmp .. '/lib/a.txt'), 'a.txt preserved')
  r.assert_truthy(isfile(tmp .. '/lib/new.lua'), 'new.lua created')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + add new file inside')
-- ============================================================================

r.run('copy with new file added', function()
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

  -- Add new file inside dst/
  lines = buf_lines(buf)
  local _, _, copy_depth = parse_line(lines[copy_line])
  local child_indent = string.rep('  ', copy_depth + 1)
  local insert_pos = copy_line
  for i = copy_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= copy_depth then break end
    insert_pos = i
  end
  vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false,
    { child_indent .. 'extra.txt' })

  do_save()

  r.assert_truthy(isdir(tmp .. '/dst'), 'dst/ exists')
  r.assert_truthy(isfile(tmp .. '/dst/a.txt'), 'a.txt copied')
  r.assert_truthy(isfile(tmp .. '/dst/b.txt'), 'b.txt copied')
  r.assert_truthy(isfile(tmp .. '/dst/extra.txt'), 'extra.txt created')
  r.assert_truthy(isdir(tmp .. '/src'), 'src/ preserved')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: multiple dirs renamed simultaneously')
-- ============================================================================

r.run('all dirs renamed on disk', function()
  local tmp = vim.fn.tempname()
  mkdir(tmp)
  mkdir(tmp .. '/alpha')
  mkdir(tmp .. '/beta')
  mkdir(tmp .. '/gamma')
  writefile(tmp .. '/alpha/x.txt', {'ax'})
  writefile(tmp .. '/beta/y.txt', {'by'})
  writefile(tmp .. '/gamma/z.txt', {'gz'})

  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Rename all three
  local lines = buf_lines(buf)
  for i, l in ipairs(lines) do
    local _, name = parse_line(l)
    if name == 'alpha/' then
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { gsub(l, 'alpha/', 'aaa/') })
    elseif name == 'beta/' then
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { gsub(l, 'beta/', 'bbb/') })
    elseif name == 'gamma/' then
      vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { gsub(l, 'gamma/', 'ccc/') })
    end
  end

  do_save()

  r.assert_truthy(isdir(tmp .. '/aaa'), 'aaa/ exists')
  r.assert_truthy(isdir(tmp .. '/bbb'), 'bbb/ exists')
  r.assert_truthy(isdir(tmp .. '/ccc'), 'ccc/ exists')
  r.assert_truthy(not exists(tmp .. '/alpha'))
  r.assert_truthy(not exists(tmp .. '/beta'))
  r.assert_truthy(not exists(tmp .. '/gamma'))
  r.assert_eq(readfile(tmp .. '/aaa/x.txt'), 'ax')
  r.assert_eq(readfile(tmp .. '/bbb/y.txt'), 'by')
  r.assert_eq(readfile(tmp .. '/ccc/z.txt'), 'gz')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + rename child + rename parent')
-- ============================================================================

r.run('both parent and child renames applied', function()
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

  -- Rename a.txt → aa.txt inside dst/
  local a_line = find_line(buf, 'a.txt', copy_line + 1)
  r.assert_truthy(a_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', 'aa.txt') })

  -- Now also rename dst/ → final/
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, copy_line - 1, copy_line, false,
    { gsub(lines[copy_line], 'dst/', 'final/') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/final'), 'final/ exists')
  r.assert_truthy(isfile(tmp .. '/final/aa.txt'), 'aa.txt inside final/')
  r.assert_truthy(isfile(tmp .. '/final/b.txt'), 'b.txt inside final/')
  r.assert_eq(readfile(tmp .. '/final/aa.txt'), 'aaa')
  r.assert_truthy(isdir(tmp .. '/src'), 'src/ preserved')
  r.assert_truthy(not exists(tmp .. '/dst'), 'dst/ should not exist')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: rename dir + move child to another dir')
-- ============================================================================

r.run('child moved across directories', function()
  local tmp = vim.fn.tempname()
  mkdir(tmp)
  mkdir(tmp .. '/foo')
  mkdir(tmp .. '/bar')
  writefile(tmp .. '/foo/x.txt', {'xx'})
  writefile(tmp .. '/bar/y.txt', {'yy'})

  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand both foo/ and bar/
  local foo_line = find_line(buf, 'foo/')
  r.assert_truthy(foo_line)
  do_enter(foo_line)

  local bar_line = find_line(buf, 'bar/')
  r.assert_truthy(bar_line)
  do_enter(bar_line)

  -- Move x.txt from foo/ into bar/ (change indent)
  local x_line = find_line(buf, 'x.txt', foo_line + 1)
  r.assert_truthy(x_line)
  local lines = buf_lines(buf)
  local x_text = lines[x_line]
  -- Remove from foo/
  vim.api.nvim_buf_set_lines(buf, x_line - 1, x_line, false, {})
  -- Find bar/'s children end and insert there
  bar_line = find_line(buf, 'bar/')
  r.assert_truthy(bar_line)
  lines = buf_lines(buf)
  local _, _, bar_depth = parse_line(lines[bar_line])
  local bar_end = bar_line
  for i = bar_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= bar_depth then break end
    bar_end = i
  end
  local bar_indent = string.rep('  ', bar_depth + 1)
  local id_part = x_text:match('^%s*(.*)')
  vim.api.nvim_buf_set_lines(buf, bar_end, bar_end, false, { bar_indent .. id_part })

  do_save()

  r.assert_truthy(not exists(tmp .. '/foo/x.txt'), 'x.txt gone from foo/')
  r.assert_truthy(isfile(tmp .. '/bar/x.txt'), 'x.txt in bar/')
  r.assert_eq(readfile(tmp .. '/bar/x.txt'), 'xx')
  r.assert_truthy(isfile(tmp .. '/bar/y.txt'), 'y.txt preserved')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: same source copied twice with different child edits')
-- ============================================================================

r.run('two copies from same source, independently edited', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  local lines = buf_lines(buf)
  local src_text = lines[src_line]

  -- Copy src/ → copy1/
  vim.api.nvim_buf_set_lines(buf, src_line, src_line, false, { src_text })
  local c1_line = src_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, c1_line - 1, c1_line, false,
    { gsub(lines[c1_line], 'src/', 'copy1/') })

  -- Copy src/ → copy2/ (insert after copy1/)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, c1_line, c1_line, false, { lines[src_line] })
  local c2_line = c1_line + 1
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, c2_line - 1, c2_line, false,
    { gsub(lines[c2_line], 'src/', 'copy2/') })

  -- Expand copy1/
  do_enter(c1_line)
  -- Rename a.txt → one.txt in copy1/
  local a1_line = find_line(buf, 'a.txt', c1_line + 1)
  r.assert_truthy(a1_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a1_line - 1, a1_line, false,
    { gsub(lines[a1_line], 'a%.txt', 'one.txt') })

  -- Find copy2/ (line shifted after expand)
  c2_line = find_line(buf, 'copy2/')
  r.assert_truthy(c2_line)
  -- Expand copy2/
  do_enter(c2_line)
  -- Rename a.txt → two.txt in copy2/
  local a2_line
  lines = buf_lines(buf)
  for i = c2_line + 1, #lines do
    if lines[i]:find('a.txt', 1, true) then a2_line = i; break end
  end
  r.assert_truthy(a2_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a2_line - 1, a2_line, false,
    { gsub(lines[a2_line], 'a%.txt', 'two.txt') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/src'), 'src/ preserved')
  r.assert_truthy(isfile(tmp .. '/src/a.txt'), 'src/a.txt intact')
  r.assert_truthy(isdir(tmp .. '/copy1'), 'copy1/ exists')
  r.assert_truthy(isfile(tmp .. '/copy1/one.txt'), 'copy1/one.txt')
  r.assert_truthy(isfile(tmp .. '/copy1/b.txt'), 'copy1/b.txt')
  r.assert_truthy(isdir(tmp .. '/copy2'), 'copy2/ exists')
  r.assert_truthy(isfile(tmp .. '/copy2/two.txt'), 'copy2/two.txt')
  r.assert_truthy(isfile(tmp .. '/copy2/b.txt'), 'copy2/b.txt')
  r.assert_eq(readfile(tmp .. '/copy1/one.txt'), 'aaa')
  r.assert_eq(readfile(tmp .. '/copy2/two.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: deeply nested expand + rename in sub-dir')
-- ============================================================================

r.run('rename file two levels deep', function()
  local tmp = vim.fn.tempname()
  mkdir(tmp)
  mkdir(tmp .. '/a')
  mkdir(tmp .. '/a/b')
  writefile(tmp .. '/a/b/deep.txt', {'deep'})

  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand a/
  local a_line = find_line(buf, 'a/')
  r.assert_truthy(a_line)
  do_enter(a_line)

  -- Expand a/b/
  local b_line = find_line(buf, 'b/', a_line + 1)
  r.assert_truthy(b_line)
  do_enter(b_line)

  -- Rename deep.txt → renamed.txt
  local deep_line = find_line(buf, 'deep.txt', b_line + 1)
  r.assert_truthy(deep_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, deep_line - 1, deep_line, false,
    { gsub(lines[deep_line], 'deep%.txt', 'renamed.txt') })

  do_save()

  r.assert_truthy(isfile(tmp .. '/a/b/renamed.txt'), 'renamed.txt exists')
  r.assert_truthy(not exists(tmp .. '/a/b/deep.txt'), 'deep.txt gone')
  r.assert_eq(readfile(tmp .. '/a/b/renamed.txt'), 'deep')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: rename dir + create + delete + rename child simultaneously')
-- ============================================================================

r.run('all mixed operations in one dir', function()
  local tmp = vim.fn.tempname()
  mkdir(tmp)
  mkdir(tmp .. '/work')
  writefile(tmp .. '/work/keep.txt', {'keep'})
  writefile(tmp .. '/work/remove.txt', {'rm'})
  writefile(tmp .. '/work/rename_me.txt', {'ren'})

  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Rename work/ → proj/
  local work_line = find_line(buf, 'work/')
  r.assert_truthy(work_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, work_line - 1, work_line, false,
    { gsub(lines[work_line], 'work/', 'proj/') })

  -- Expand proj/
  do_enter(work_line)

  -- Delete remove.txt
  local rm_line = find_line(buf, 'remove.txt', work_line + 1)
  r.assert_truthy(rm_line)
  vim.api.nvim_buf_set_lines(buf, rm_line - 1, rm_line, false, {})

  -- Rename rename_me.txt → done.txt
  local ren_line = find_line(buf, 'rename_me.txt', work_line + 1)
  r.assert_truthy(ren_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, ren_line - 1, ren_line, false,
    { gsub(lines[ren_line], 'rename_me%.txt', 'done.txt') })

  -- Add new file
  lines = buf_lines(buf)
  local _, _, wd = parse_line(lines[work_line])
  local child_indent = string.rep('  ', wd + 1)
  local insert_pos = work_line
  for i = work_line + 1, #lines do
    local _, _, d = parse_line(lines[i])
    if d <= wd then break end
    insert_pos = i
  end
  vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false,
    { child_indent .. 'added.txt' })

  do_save()

  r.assert_truthy(isdir(tmp .. '/proj'), 'proj/ exists')
  r.assert_truthy(not exists(tmp .. '/work'), 'work/ gone')
  r.assert_truthy(isfile(tmp .. '/proj/keep.txt'), 'keep.txt preserved')
  r.assert_truthy(not exists(tmp .. '/proj/remove.txt'), 'remove.txt gone')
  r.assert_truthy(not exists(tmp .. '/proj/rename_me.txt'), 'rename_me.txt gone')
  r.assert_truthy(isfile(tmp .. '/proj/done.txt'), 'done.txt exists')
  r.assert_truthy(isfile(tmp .. '/proj/added.txt'), 'added.txt created')
  r.assert_eq(readfile(tmp .. '/proj/keep.txt'), 'keep')
  r.assert_eq(readfile(tmp .. '/proj/done.txt'), 'ren')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: copy dir + expand + collapse + re-expand')
-- ============================================================================

r.run('children survive collapse/re-expand cycle', function()
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

  -- Expand → collapse → re-expand
  do_enter(copy_line)
  local a_line = find_line(buf, 'a.txt', copy_line + 1)
  r.assert_truthy(a_line, 'a.txt visible after first expand')

  do_enter(copy_line) -- collapse

  local a_after_collapse = find_line(buf, 'a.txt', copy_line + 1)
  -- After collapse, children not visible in immediate subsequent lines of same depth
  -- (they belong to saved_children now)

  do_enter(copy_line) -- re-expand

  local a_after_reexpand = find_line(buf, 'a.txt', copy_line + 1)
  r.assert_truthy(a_after_reexpand, 'a.txt visible after re-expand')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: delete entire dir (unexpanded)')
-- ============================================================================

r.run('dir and all contents removed from disk', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Delete src/ line
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  vim.api.nvim_buf_set_lines(buf, src_line - 1, src_line, false, {})

  do_save()

  r.assert_truthy(not exists(tmp .. '/src'), 'src/ gone')
  r.assert_truthy(not exists(tmp .. '/src/a.txt'), 'src/a.txt gone')
  r.assert_truthy(isfile(tmp .. '/top.txt'), 'top.txt preserved')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: rename file with path separator creates subdir')
-- ============================================================================

r.run('rename top.txt to sub/top.txt creates sub/', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/ so we have an expanded dir context
  local src_line = find_line(buf, 'src/')
  do_enter(src_line)

  -- Find a.txt in src/ and "rename" it to nested/a.txt (writes path separator)
  local a_line = find_line(buf, 'a.txt', src_line + 1)
  r.assert_truthy(a_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', 'nested/a.txt') })

  do_save()

  r.assert_truthy(isdir(tmp .. '/src/nested'), 'src/nested/ created')
  r.assert_truthy(isfile(tmp .. '/src/nested/a.txt'), 'a.txt moved into nested/')
  r.assert_truthy(not exists(tmp .. '/src/a.txt'), 'old a.txt gone')
  r.assert_eq(readfile(tmp .. '/src/nested/a.txt'), 'aaa')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: duplicate detection blocks save')
-- ============================================================================

r.run('copy dir + expand + rename child to same name = duplicate error', function()
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

  -- Rename b.txt → a.txt (creates duplicate with existing a.txt)
  local b_line = find_line(buf, 'b.txt', copy_line + 1)
  r.assert_truthy(b_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, b_line - 1, b_line, false,
    { gsub(lines[b_line], 'b%.txt', 'a.txt') })

  -- do_save should error due to duplicate
  local ok, err = pcall(do_save)
  r.assert_truthy(not ok, 'should fail on duplicate')
  r.assert_truthy(err:find('duplicates detected'), 'error mentions duplicates')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: swap two file names in same dir')
-- ============================================================================

r.run('two files swapped within expanded dir', function()
  local tmp = vim.fn.tempname()
  mkdir(tmp)
  mkdir(tmp .. '/d')
  writefile(tmp .. '/d/A.txt', {'AAA'})
  writefile(tmp .. '/d/B.txt', {'BBB'})

  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand d/
  local d_line = find_line(buf, 'd/')
  r.assert_truthy(d_line)
  do_enter(d_line)

  -- Find A.txt and B.txt
  local lines = buf_lines(buf)
  local a_line, b_line
  for i = d_line + 1, #lines do
    local _, name = parse_line(lines[i])
    if name == 'A.txt' then a_line = i end
    if name == 'B.txt' then b_line = i end
  end
  r.assert_truthy(a_line)
  r.assert_truthy(b_line)

  -- Swap names
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'A%.txt', 'B.txt') })
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, b_line - 1, b_line, false,
    { gsub(lines[b_line], 'B%.txt', 'A.txt') })

  do_save()

  r.assert_eq(readfile(tmp .. '/d/A.txt'), 'BBB')
  r.assert_eq(readfile(tmp .. '/d/B.txt'), 'AAA')

  vim.fn.delete(tmp, 'rf')
end)

-- ============================================================================
r.group('e2e: rename children + collapse parent + re-expand + save')
-- ============================================================================

r.run('renames become MOVE (not COPY) after collapse/re-expand cycle', function()
  local tmp = make_fixture()
  local buf, session, do_save, do_enter = open_and_helpers(tmp)

  -- Expand src/
  local src_line = find_line(buf, 'src/')
  r.assert_truthy(src_line)
  do_enter(src_line)

  -- Rename a.txt -> 1.txt
  local a_line = find_line(buf, 'a.txt', src_line + 1)
  r.assert_truthy(a_line)
  local lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, a_line - 1, a_line, false,
    { gsub(lines[a_line], 'a%.txt', '1.txt') })

  -- Rename b.txt -> 2.txt
  local b_line = find_line(buf, 'b.txt', src_line + 1)
  r.assert_truthy(b_line)
  lines = buf_lines(buf)
  vim.api.nvim_buf_set_lines(buf, b_line - 1, b_line, false,
    { gsub(lines[b_line], 'b%.txt', '2.txt') })

  -- Collapse src/
  do_enter(src_line)
  -- Re-expand src/
  do_enter(src_line)

  do_save()

  r.assert_truthy(isfile(tmp .. '/src/1.txt'), 'src/1.txt exists')
  r.assert_truthy(isfile(tmp .. '/src/2.txt'), 'src/2.txt exists')
  r.assert_truthy(not exists(tmp .. '/src/a.txt'), 'src/a.txt gone (MOVE, not COPY)')
  r.assert_truthy(not exists(tmp .. '/src/b.txt'), 'src/b.txt gone (MOVE, not COPY)')
  r.assert_eq(readfile(tmp .. '/src/1.txt'), 'aaa')
  r.assert_eq(readfile(tmp .. '/src/2.txt'), 'bbb')

  vim.fn.delete(tmp, 'rf')
end)

r.finish()

