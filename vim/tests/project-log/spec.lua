-- Project-log graph tests
-- Usage: cd vim && nvim --headless -u NONE -l tests/project-log/spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local core = require('lu5je0.ext.git.project-log.core')

local passed = 0
local failed = 0
local color = {
  reset = '\27[0m',
  green = '\27[32m',
  red = '\27[31m',
}

local function load_commits(range)
  local result = vim.system({
    'git',
    'log',
    '--graph',
    '--date=format:%Y-%m-%d %H:%M:%S',
    '--pretty=format:%x1e%H%x00%h%x00%ad%x00%an%x00%s%x00%P',
    '--name-status',
    '--find-renames',
    '--find-copies',
    range,
    '--',
    '.',
  }, { text = true, cwd = repo_root }):wait()
  if result.code ~= 0 then
    error(result.stderr or 'git log failed')
  end
  return core.parse_log(result.stdout or '')
end

local function graphs_by_short_hash(commits)
  local graphs = {}
  for _, commit in ipairs(commits) do
    graphs[commit.short_hash] = commit.graph
  end
  return graphs
end

local function run_case(name, range, expected)
  io.write(string.format('  %s ... ', name))
  local graphs = graphs_by_short_hash(load_commits(range))
  local errors = {}
  for short_hash, expected_graph in pairs(expected) do
    local actual = graphs[short_hash]
    if actual ~= expected_graph then
      errors[#errors + 1] = string.format('%s expected=%s actual=%s', short_hash, expected_graph, actual or '(missing)')
    end
  end

  if #errors == 0 then
    io.write(string.format('%sPASS%s\n', color.green, color.reset))
    passed = passed + 1
    return
  end

  io.write(string.format('%sFAIL%s\n', color.red, color.reset))
  for _, err in ipairs(errors) do
    io.write('    ' .. err .. '\n')
  end
  failed = failed + 1
end

run_case('full-history crossed branch joins', '0357ae54~1..HEAD', {
  ca1d53f3 = '│ M─┐',
  ['01df7a82'] = '│ o │',
  ['0ba05c1d'] = 'o │ │',
  d8e143d2 = 'o─│─┘',
  ['70b36d64'] = 'M─│─┐',
  ['4c725ed7'] = '│ │ o',
  fbedadd9 = 'o │ │',
  ['7117b69b'] = 'o─│─┘',
  ['0357ae54'] = 'o─┘',
})

run_case('nested merge joins', '2eb17050~1..419a960c', {
  ['64e62056'] = 'M─┐',
  b2a6eca9 = '│ M─┐',
  ['3798c973'] = '│ o │',
  ['503ae902'] = 'o │ │',
  ['25ba2b28'] = 'M─│─┤',
  ['639f89b8'] = '│ o─┘',
  fa36495d = 'o │',
  ['936b05e6'] = 'o─┘',
})

run_case('side merge after crossover', '5b7e2846~1..2eb17050', {
  ['69187d33'] = 'M─│─┐',
  ['9de3ebd0'] = '│ M─┤',
  d4564753 = 'o │ │',
  ['2acf11f0'] = 'M─┼─┘',
})

run_case('merge collapses through middle lane', '65a66c78~1..5a0206da', {
  b41008cd = 'M─┐',
  a50cf71e = '│ o',
  dc16fff9 = 'o │',
  b7095898 = 'M─┤',
  e0c1385b = 'o │',
  ['65a66c78'] = 'o─┘',
})

run_case('wide merge with spaced continuation', '62b07ca6~1..HEAD', {
  ce0db1c3 = '│ o─┘',
  ['1ece6443'] = '│ │ M─│─┐',
  ['70ace34d'] = '│ o─│─┘ │',
  a2748dfb = '│ o │ ┌─┘',
  ['984c99fe'] = '│ o─│─┘',
  ['58a4649b'] = '│ o─┘',
  ['6c8e9e40'] = 'o │',
  ['62b07ca6'] = 'o─┘',
})

run_case('multi-lane close after inner join', 'bf903126~1..5fe3a5a0', {
  f047ba6b = 'o │ │',
  bf903126 = 'o─┴─┘',
})

io.write(string.format('\nproject-log graph: %d passed, %d failed\n', passed, failed))
if failed > 0 then
  os.exit(1)
end
