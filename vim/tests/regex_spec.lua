-- Tests for lu5je0.lang.regex
-- Usage: cd vim && nvim --headless -u NONE -l tests/regex_spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(repo_root)

local regex = require('lu5je0.lang.regex')

local color = {
  reset = '\27[0m',
  green = '\27[32m',
  red = '\27[31m',
  cyan = '\27[36m',
}

local passed = 0
local failed = 0

local function run(name, fn)
  io.write(string.format('  %s ... ', name))
  local ok, err = pcall(fn)
  if ok then
    io.write(color.green .. 'PASS' .. color.reset .. '\n')
    passed = passed + 1
  else
    io.write(color.red .. 'FAIL' .. color.reset .. '\n    ' .. tostring(err) .. '\n')
    failed = failed + 1
  end
end

local function assert_match(r, str)
  if not r or r:match_str(str) == nil then
    error(string.format('expected "%s" to match', str), 2)
  end
end

local function assert_no_match(r, str)
  if r and r:match_str(str) ~= nil then
    error(string.format('expected "%s" NOT to match', str), 2)
  end
end

-- ============================================================================
io.write(color.cyan .. 'regex.compile' .. color.reset .. '\n')
-- ============================================================================

run('nil returns nil', function()
  assert(regex.compile(nil) == nil)
end)

run('empty string returns nil', function()
  assert(regex.compile('') == nil)
end)

run('plain text matches', function()
  local r = regex.compile('hello')
  assert_match(r, 'hello_world')
  assert_no_match(r, 'goodbye')
end)

run('case-insensitive by default', function()
  local r = regex.compile('lua')
  assert_match(r, 'init.LUA')
  assert_match(r, 'Lua_file')
  assert_match(r, 'foo.lua')
end)

run('dot matches any character', function()
  local r = regex.compile('a.c')
  assert_match(r, 'abc')
  assert_match(r, 'axc')
  assert_no_match(r, 'ac')
end)

run('$ anchors to end', function()
  local r = regex.compile('\\.lua$')
  assert_match(r, 'init.lua')
  assert_no_match(r, 'lua_stuff.txt')
end)

run('^ anchors to start', function()
  local r = regex.compile('^init')
  assert_match(r, 'init.lua')
  assert_no_match(r, 'my_init.lua')
end)

run('alternation with (|)', function()
  local r = regex.compile('(foo|bar)')
  assert_match(r, 'foobar')
  assert_match(r, 'bar_baz')
  assert_no_match(r, 'baz_qux')
end)

run('+ quantifier', function()
  local r = regex.compile('ab+c')
  assert_match(r, 'abbc')
  assert_match(r, 'abc')
  assert_no_match(r, 'ac')
end)

run('*? lazy quantifier', function()
  local r = regex.compile('a.*?b')
  assert_match(r, 'aXb')
  assert_match(r, 'ab')
  assert_no_match(r, 'a')
end)

run('+? lazy quantifier', function()
  local r = regex.compile('a.+?b')
  assert_match(r, 'aXb')
  assert_match(r, 'aXXb')
  assert_no_match(r, 'ab')
end)

run('?? lazy quantifier', function()
  local r = regex.compile('ab??c')
  assert_match(r, 'ac')
  assert_match(r, 'abc')
  assert_no_match(r, 'abbc')
end)

run('\\d matches digit', function()
  local r = regex.compile('\\d+')
  assert_match(r, 'file123')
  assert_no_match(r, 'nodigits')
end)

run('invalid regex returns nil', function()
  assert(regex.compile('[unclosed') == nil)
end)

run('special chars in very magic mode', function()
  local r = regex.compile('foo\\.bar')
  assert_match(r, 'foo.bar')
  assert_no_match(r, 'fooXbar')
end)

-- ============================================================================
io.write(string.format('\n%s passed, %s failed\n',
  color.green .. tostring(passed) .. color.reset,
  (failed > 0 and color.red or color.green) .. tostring(failed) .. color.reset))

if failed > 0 then
  os.exit(1)
end
