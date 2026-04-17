-- Line-log block tracking tests
-- Usage: cd vim && nvim --headless -u NONE -l tests/line-log_spec.lua
--
-- Each test case pins a specific commit + file + line range,
-- and verifies the block tracking algorithm produces the expected commit list.

local Block = require('lu5je0.ext.git.line-log.block')
local blob_store = require('lu5je0.ext.git.line-log.blob-store')

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local store = blob_store.for_repo(repo_root)

local function git(args)
  local cmd = { 'git' }
  for _, a in ipairs(args) do
    cmd[#cmd + 1] = a
  end
  local result = vim.system(cmd, { text = true, cwd = repo_root }):wait()
  if result.code ~= 0 then
    return nil
  end
  return result.stdout
end

local function parse_revisions_with_status(stdout, default_path)
  local result = {}
  local current_full, current_short
  for line in stdout:gmatch('[^\n]*') do
    local full, short = line:match('^(%x+) (%x+)$')
    if full then
      -- New commit hash line; flush previous if it had no status line (merge commit)
      if current_full then
        table.insert(result, { current_full, current_short, 'M\t' .. default_path })
      end
      current_full = full
      current_short = short
    elseif current_full and line ~= '' then
      table.insert(result, { current_full, current_short, line })
      current_full = nil
      current_short = nil
    end
  end
  if current_full then
    table.insert(result, { current_full, current_short, 'M\t' .. default_path })
  end
  return result
end

local function collect_revisions_idea(commit, rel_file)
  local visited = {}
  local result = {}
  local queue = { { commit = commit, path = rel_file } }

  while #queue > 0 do
    local item = table.remove(queue, 1)
    local log_out = git {
      'log', item.commit,
      '--format=%H %h',
      '--name-status',
      '--full-history', '--simplify-merges',
      '--', item.path,
    }
    if log_out then
      local last_add_commit = nil
      local entries = parse_revisions_with_status(log_out, item.path)
      for _, entry in ipairs(entries) do
        local full, short, status_line = entry[1], entry[2], entry[3]
        if not visited[full] then
          visited[full] = true
          local status = status_line:sub(1, 1)
          local file_name = status_line:match('\t(.+)$') or item.path
          table.insert(result, { full = full, short = short, file = file_name })
          if status == 'A' then
            last_add_commit = full
            break
          end
        end
      end
      if last_add_commit then
        local show_out = git {
          'show', '-M', '--follow', '--name-status',
          '--format=%H %h', last_add_commit, '--', item.path,
        }
        if show_out then
          for line in show_out:gmatch('[^\n]+') do
            if line:match('^R') and line:find('\t') then
              local parts = vim.split(line, '\t', { plain = true })
              if #parts >= 3 then
                table.insert(queue, { commit = last_add_commit, path = parts[2] })
              end
              break
            end
          end
        end
      end
    end
  end

  return result
end

--- Run block tracking and return the list of shown commit hashes (8-char).
--- @param commit string starting commit
--- @param rel_file string file path relative to repo root
--- @param start_line number 1-based start line
--- @param end_line number 1-based end line
--- @return string[] commit hashes
local function track_commits(commit, rel_file, start_line, end_line)
  local revisions = collect_revisions_idea(commit, rel_file)
  local specs = {
    { rev = commit, file = rel_file },
  }
  for _, rev in ipairs(revisions) do
    specs[#specs + 1] = { rev = rev.full, file = rev.file }
  end
  local ok, err = store:prefetch_sync(specs)
  if not ok then
    error(err)
  end

  local current_lines = store:get_lines(commit, rel_file)
  if not current_lines then
    return {}
  end

  local block = Block.new(current_lines, start_line, end_line)
  local shown = {}

  for idx, rev in ipairs(revisions) do
    local prev_lines = store:get_lines(rev.full, rev.file)
    if not prev_lines then
      break
    end

    local prev_block = block:create_previous_block(prev_lines)
    local changed = not block:content_equals(prev_block)

    if changed and idx > 1 then
      table.insert(shown, revisions[idx - 1].short)
    end

    block = prev_block
    if block:is_empty() then
      break
    end

    if idx == #revisions then
      table.insert(shown, rev.short)
    end
  end

  return shown
end

-- ============================================================================
-- Test infrastructure
-- ============================================================================

local passed = 0
local failed = 0
local skipped = 0

local function format_test_name(tc)
  local line_range = tc.start_line == tc.end_line
      and tostring(tc.start_line)
    or string.format('%d-%d', tc.start_line, tc.end_line)
  return string.format('%s:%s:%s', tc.commit, tc.file, line_range)
end

local function run_test(tc)
  io.write(string.format('  %s ... ', format_test_name(tc)))

  if not tc.expected_commits then
    io.write('SKIP (no expected_commits)\n')
    skipped = skipped + 1
    return
  end

  local actual = track_commits(tc.commit, tc.file, tc.start_line, tc.end_line)

  -- Compute intersection count
  local expected_set = {}
  for _, h in ipairs(tc.expected_commits) do
    expected_set[h] = true
  end
  local intersect = 0
  for _, h in ipairs(actual) do
    if expected_set[h] then
      intersect = intersect
          + 1
    end
  end

  local total = math.max(#actual, #tc.expected_commits)
  local match = intersect == total and #actual == #tc.expected_commits

  if match then
    io.write(string.format('PASS (%d commits, %d/%d)\n', #actual, intersect, total))
    passed = passed + 1
  else
    io.write(string.format('FAIL (%d/%d)\n', intersect, total))
    io.write(string.format('    expected (%d): %s\n', #tc.expected_commits, table.concat(tc.expected_commits, ', ')))
    io.write(string.format('    actual   (%d): %s\n', #actual, table.concat(actual, ', ')))

    -- Show first positional divergence
    local max_len = math.max(#actual, #tc.expected_commits)
    for i = 1, max_len do
      local e = tc.expected_commits[i] or '(none)'
      local a = actual[i] or '(none)'
      if e ~= a then
        io.write(string.format('    first diff at index %d: expected=%s actual=%s\n', i, e, a))
        break
      end
    end

    failed = failed + 1
  end
end

-- ============================================================================
-- Test cases
--
-- Format:
--   commit:           the git commit to use as the "current" version
--   file:             file path relative to repo root
--   start_line:       1-based start line
--   end_line:         1-based end line
--   expected_commits: list of 7-8 char commit hashes (fill in from IDEA)
-- ============================================================================

local test_cases = {
  {
    commit = '0adb3a6c',
    file = 'vim/init.lua',
    start_line = 3,
    end_line = 12,
    expected_commits = { "0ae3adc8", "f1fc0785", "1fb8c391", "89d25c75", },
  },
  {
    commit = '0adb3a6c',
    file = 'zshrc',
    start_line = 21,
    end_line = 40,
    expected_commits = { "ce5ecd12", "d58731fb", "d75b8ad8", "3f1fa317", "48001df8", "1aeddefb", "2f0dd903", "1a665baa", "eae97b80", "673aa3cd", "66756491", "00189d5e", "e75b53a1", "cbe17c94", "b401c762", "b415b5a4", "be432ca1", "9c43e737", },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/lua/lu5je0/plugins.lua',
    start_line = 27,
    end_line = 45,
    expected_commits = { "11785101", "dfd2d011", "dce8dc32", "4687f21b", "94684ac8", "96549eca", "321dd5f5", "09edeb08", "889f3736", "09c9d307", "b8b5d7d7", "94d9fc04", "c038f4e2", "8d248830", "d8c6c236", "2343c957", },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/lua/lu5je0/plugins.lua',
    start_line = 110,
    end_line = 135,
    expected_commits = { "369bd084", "82dc68ce", "a6dda7d6", "321dd5f5", "790db9e5", "068d9de1", "afe7b925", "9b57cd2f", "e4416b1e", },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/lua/lu5je0/mappings.lua',
    start_line = 50,
    end_line = 70,
    expected_commits = { "b68f6a0a", "15739373", "d51d7330", "a940acfb", "e5340d57", "69561870", "4498a8fb", "35d57303", "95d73de4", "a279c347" },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/lua/lu5je0/options.lua',
    start_line = 1,
    end_line = 20,
    expected_commits = { "ef8241f1", "517101a4", "ec828bce", "4a2140af", "55190f97", "2c54c801", "b74945dc", "4d5f55bc", "a3e012f2", "55a54f53", "5da645c0", "3487139c" },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/lua/lu5je0/autocmds.lua',
    start_line = 80,
    end_line = 100,
    expected_commits = { "05b97965", "06be3812", "ecfd94f8", "9d7b5677" },
  },
  {
    commit = '0adb3a6c',
    file = 'tmux/tmux.conf',
    start_line = 10,
    end_line = 30,
    expected_commits = { "f0fd7a09", "c7ff4f5e", "70e68820", "c79711b8", "0db0632b", "9654cab7", "c53df9a5", "f3f092ad", "12bbdc16", "8940e6fe", "bf8c8eb0", },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/lua/lu5je0/commands.lua',
    start_line = 100,
    end_line = 120,
    expected_commits = { "6884fb90", "80aea8ba", "2c54c801", "2eda94f4", "23ad0b71", "4007cf81", "3f7ed14a", "321d30d5", "daab957f", },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/init.lua',
    start_line = 148,
    end_line = 181,
    expected_commits = { "36d5a4fc", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/init.lua',
    start_line = 183,
    end_line = 260,
    expected_commits = { "452b5d3c", "36d5a4fc", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/ui.lua',
    start_line = 130,
    end_line = 188,
    expected_commits = { "fe661db9", "2e2ee17c", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/block.lua',
    start_line = 116,
    end_line = 198,
    expected_commits = { "8b1b55be", "752ebf2f" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/init.lua',
    start_line = 79,
    end_line = 125,
    expected_commits = { "452b5d3c", "fe661db9", "d630de00", "36d5a4fc", "80a2dd45", "e1f32c70", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/init.lua',
    start_line = 127,
    end_line = 146,
    expected_commits = { "452b5d3c", "36d5a4fc", "e23d8d1b", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/init.lua',
    start_line = 36,
    end_line = 60,
    expected_commits = { "452b5d3c", "d630de00", "e1f32c70", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/ui.lua',
    start_line = 20,
    end_line = 83,
    expected_commits = { "452b5d3c", "d630de00", "0adb3a6c" },
  },
  {
    commit = '9c1c12c9',
    file = 'vim/lua/lu5je0/ext/git/line-log/ui.lua',
    start_line = 256,
    end_line = 340,
    expected_commits = { "fe661db9", "d630de00", "72ba5321", "347e9a19", "0adb3a6c" },
  },
  {
    commit = '0adb3a6c',
    file = 'vim/init.lua',
    start_line = 15,
    end_line = 23,
    expected_commits = { "8494efcf", "55190f97", "321dd5f5", "ea498a60", "89d25c75", "d0e1f9e5", "d776da43", "2f196585", "3487139c", "5b6574ee", "27cc9eeb", "5974104c", "f749bf2c", "f8724863", "9ed21b28", "0f52f146", "76c6aae6", "a3018a9d", "b07784bc", "cf3604f1", "2e564cd4", "46e51993", "1794bf92", "773dbc57", "c87e3c1c", "b43d7871", "76bbd90a", "6156f904", "9a1591f1", "234798c7", "db386ed3", "d4b48667", "365636eb", "efc5eeb4", "0e97f282", "fc7bb485", "da2ddd27", "b69ed4a7", "c9c968ad", "8aea061c", "5f43320b", "c0918895", "bab98e53", "447aa585", "c8e8b9e3", "006a3b1d", "faca7993", "c9441e92", "d5dc7ffb", "f002ee5d", "46351007", "48f93eee", "422069dc", "5f492a39", "9ad44a4a", "517455d4", "a5d06dfe", "a3a05766", "2709fb66", "e4c60e67", "c33b133f", "0bfbeeb4", "b70dd8b6", "6a3196f1", "b12c03c2", "36b34cfb", "95c97d94", "3cf5569f", "46174f4a", "371e0b7c", "3b5657ea", "51c4a135", "d32b6850", "07cd89d2", "057699b8", "b919df3c", "2f802ac7", "51317819", "c79711b8", "1b5ae473", "3ca7ce0d", "6dc6ce37", "edb28ef2", "f8251cee", "a72bc7e5", "da26df88", "fa1fbe65", "e52c7638", "481b8669", "b72aa670", "3ee3a7fb", "eec1205d", "31984e87", "6642d409", "a99c8c87", "34a6cecd", "9d98f27a", "c75a353a", "93550558", "767e172f", "9b91d949", "4a78f29e", "805f769e", "6d44fdc5", "745e8fb7", "4682e4a2", "a1a2d482", "db254ad1", "81aad924", "7ecf7ac6", "656db73d", "a6ac8597", "3e1f4c30", "4f7cd145", "cd0f2969", "add907a6", "c21c9c9e", "079ac9fa", "4d782eb2", "a8962e5f", "71b40cf6", "dd2345f5", "f3cb72f1", "0f100770", "ca9d8275", "73eae625", "962bb058", "9c71c186", "f720d2c1", "e9ba323d", "d111a8d1", "4f256a79", "d2183621", "45e8a643", "e15b32ef", "d744ee25", "bc500458", "a2d0374b", "25ff4d67", "c12d6cbe", "500f1e56", "126d5214", "1b29610b", "e917227f", "1cdf623f", "4aadeb83", "0795711d", "c1191048", "c70922b1", "4a0c7fcd", "b30c51ae", "1aa40ba8", "4d96a719", "e309179e", "77fc5b85", "93b4dad3", "3f7477c6", "80effe7b", "8d4e9d2b", "6cf56af8", "c2bd56dd", "b71f42d4", "b3e224d2", "f31f47b0", "9e5a88e6", "56f4102c", "785e6f68", "c38e33cd", "efe1a66e", "b86edafe", "c1f14110", "2d96c4ad", "543e7a77", "827c057b", "c4ecd2b7", "6c031606", "90e7ec5f", "f81d827d", "40f66746", "52d57f0e", "31d7414e", "0814a452", "7e7599f5", "0993164b", "21e8f2c1", "81e9ab47", "50ae7af4", "88d49a4e", "743517ec", "f7bdbec5", "fc6ca226", "07e798f8", "a41efcc0", "67535fc2", "a650ec1b", "dd3e4c06", "982f550b", "c3347363", "c27a5a59", "13139286", "1a23c714", "ec1c62f1", "34c97cf8", "66644aae", "52ff88f7", },
  },
}

-- ============================================================================
-- Run
-- ============================================================================

print('line-log block tracking tests')
print(string.rep('-', 60))
print()

for _, tc in ipairs(test_cases) do
  run_test(tc)
end

print(string.rep('-', 60))
print(string.format('Total: %d  Passed: %d  Failed: %d  Skipped: %d', passed + failed + skipped, passed, failed, skipped))

if failed > 0 then
  vim.cmd('cq 1')
else
  vim.cmd('qa!')
end
