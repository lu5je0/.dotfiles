-- History Tig graph tests
-- Usage: cd vim && nvim --headless -u NONE -l tests/project-log/spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local core = require('lu5je0.ext.sidebar.sources.history.core')
local tig = require('lu5je0.ext.sidebar.sources.history.tig')

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
    '--topo-order',
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

local function verify_rows(rows, commits)
  assert(#rows == #commits, 'each commit must have one graph row')
  for _, row in ipairs(rows) do
    local raw = {}
    for _, cell in ipairs(row.cells) do raw[#raw + 1] = cell.text end
    assert(row.text == table.concat(raw):sub(2), 'display must omit the first padding byte like Tig draw_graph_utf8')
    assert(row.width == vim.fn.strdisplaywidth(row.text))
    local offset = 0
    for _, span in ipairs(row.spans) do
      assert(span.first == offset and span.last > span.first, 'display highlights must remain aligned')
      offset = span.last
    end
    assert(offset == #row.text)
  end
end

local function run_case(name, range)
  io.write(string.format('  %s ... ', name))
  local ok, err = pcall(function()
    local commits = load_commits(range)
    verify_rows(tig.build(commits), commits)
  end)
  if ok then
    passed = passed + 1
    io.write(string.format('%sPASS%s\n', color.green, color.reset))
  else
    failed = failed + 1
    io.write(string.format('%sFAIL%s\n    %s\n', color.red, color.reset, tostring(err)))
  end
end

run_case('crossed branch joins', '0357ae54~1..HEAD')
run_case('nested merge joins', '2eb17050~1..419a960c')
run_case('side merge after crossover', '5b7e2846~1..2eb17050')
run_case('merge collapses through middle lane', '65a66c78~1..5a0206da')
run_case('wide merge with spaced continuation', '62b07ca6~1..HEAD')
run_case('multi-lane close after inner join', 'bf903126~1..5fe3a5a0')

-- Golden cells captured from unmodified Tig 2.6.0 graph-v2.c, including
-- its color IDs. No Tig binary or network access is required by the tests.
local fixtures_path = repo_root .. '/vim/tests/project-log/tig-fixtures.json'
local fixtures = vim.json.decode(table.concat(vim.fn.readfile(fixtures_path), '\n'))
for _, fixture in ipairs(fixtures) do
  local rows = tig.build(fixture.commits)
  local cells = {}
  for _, row in ipairs(rows) do cells[#cells + 1] = row.cells end
  verify_rows(rows, fixture.commits)
  if vim.deep_equal(cells, fixture.expected) then
    passed = passed + 1
    io.write('  Tig v2 ' .. fixture.name .. ' ... PASS\n')
  else
    failed = failed + 1
    io.write('  Tig v2 ' .. fixture.name .. ' ... FAIL\n')
  end
end

io.write(string.format('\nproject-log graphs: %d passed, %d failed\n', passed, failed))
if failed > 0 then
  os.exit(1)
end
