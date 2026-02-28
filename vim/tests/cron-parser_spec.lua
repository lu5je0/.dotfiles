local dotfiles_root = os.getenv('DOTFILES_ROOT')
if not dotfiles_root or dotfiles_root == '' then
  error('DOTFILES_ROOT is required')
end

package.path = table.concat({
  dotfiles_root .. '/vim/lua/?.lua',
  dotfiles_root .. '/vim/lua/?/init.lua',
  package.path,
}, ';')

vim = vim or {}
vim.split = vim.split or function(s, sep, opts)
  opts = opts or {}
  if sep == '%s+' then
    local out = {}
    for w in string.gmatch(s, '%S+') do
      table.insert(out, w)
    end
    return out
  end

  local out = {}
  if sep == '' then
    if not opts.trimempty then
      table.insert(out, s)
    end
    return out
  end

  local start = 1
  while true do
    local i, j = string.find(s, sep, start)
    if not i then
      local tail = string.sub(s, start)
      if tail ~= '' or not opts.trimempty then
        table.insert(out, tail)
      end
      break
    end

    local part = string.sub(s, start, i - 1)
    if part ~= '' or not opts.trimempty then
      table.insert(out, part)
    end
    start = j + 1
  end

  return out
end

local cron = require('lu5je0.misc.cron-parser')
local t = cron._test

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or 'assert failed') .. ('\nexpected: %s\nactual: %s'):format(tostring(expected), tostring(actual)))
  end
end

local function assert_true(v, msg)
  if not v then
    error(msg or 'assert_true failed')
  end
end

local function test_extract_embedded_expression()
  local line = '# 59 9 * * * cd /home/example/auto/zeeker && /bin/python3 "/home/example/auto/zeeker/1.py" | /bin/tee -a 1.log'
  assert_eq(t.extract_cron_expr(line), '59 9 * * *', 'should extract cron from commented command line')
end

local function test_parse_weekday_names()
  local schedule, err = t.parse_cron_expr('*/15 8-10 * * MON-FRI')
  assert_true(schedule ~= nil, err or 'schedule should parse')
  assert_true(schedule.dow.set[1], 'MON should map to 1')
  assert_true(schedule.dow.set[5], 'FRI should map to 5')
  assert_true(not schedule.dow.set[0], 'SUN should not be in MON-FRI')
end

local function test_next_runs_deterministic()
  local schedule, err = t.parse_cron_expr('59 9 * * *')
  assert_true(schedule ~= nil, err or 'schedule should parse')

  -- 2026-03-01 09:58:00 UTC
  local now_ts = 1772359080
  local runs = t.next_runs(schedule, 3, now_ts)

  assert_eq(#runs, 3, 'should return 3 runs')
  assert_eq(runs[1], '2026-03-01 09:59:00', 'first run mismatch')
  assert_eq(runs[2], '2026-03-02 09:59:00', 'second run mismatch')
  assert_eq(runs[3], '2026-03-03 09:59:00', 'third run mismatch')
end

local function test_invalid_expression()
  local schedule = t.parse_cron_expr('61 9 * * *')
  assert_eq(schedule, nil, 'invalid minute should fail parsing')
end

local tests = {
  test_extract_embedded_expression,
  test_parse_weekday_names,
  test_next_runs_deterministic,
  test_invalid_expression,
}

for _, fn in ipairs(tests) do
  fn()
end

print(('PASS: %d tests'):format(#tests))
