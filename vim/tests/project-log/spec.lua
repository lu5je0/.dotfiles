-- Project-log kitty graph tests
-- Usage: cd vim && nvim --headless -u NONE -l tests/project-log/spec.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
vim.opt.runtimepath:prepend(repo_root .. '/vim')

local core = require('lu5je0.ext.git.project-log.core')
local kitty = require('lu5je0.ext.git.project-log.kitty')

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

local VALID_COLORS = {
  Red = true, Yellow = true, Blue = true, Purple = true, Cyan = true,
  BoldRed = true, BoldYellow = true, BoldBlue = true, BoldPurple = true, BoldCyan = true,
}

local VALID_CHARS = {}
for _, ch in ipairs({ '●', '│', '─', '╮', '╭', '╯', '╰', '┴', '┬', '┤', '├', '┼', ' ', '?' }) do
  VALID_CHARS[ch] = true
end

local function run_case(name, range)
  io.write(string.format('  %s ... ', name))
  local commits = load_commits(range)
  local errors = {}

  local ok, graph = pcall(kitty.build, commits, true)
  if not ok then
    io.write(string.format('%sFAIL%s\n', color.red, color.reset))
    io.write('    kitty.build error: ' .. tostring(graph) .. '\n')
    failed = failed + 1
    return
  end

  if #graph == 0 and #commits > 0 then
    errors[#errors + 1] = 'graph is empty but commits exist'
  end

  local seen_hashes = {}
  for _, row in ipairs(graph) do
    local oid = row[1] and row[1].oid
    if oid then
      if seen_hashes[oid] then
        errors[#errors + 1] = 'duplicate oid: ' .. oid:sub(1, 8)
      end
      seen_hashes[oid] = true
    end

    for _, cell in ipairs(row) do
      if cell.color and not VALID_COLORS[cell.color] then
        errors[#errors + 1] = 'invalid color: ' .. tostring(cell.color)
      end
      if cell.text and not VALID_CHARS[cell.text] then
        errors[#errors + 1] = 'invalid char: ' .. cell.text .. ' (bytes: ' .. #cell.text .. ')'
      end
    end
  end

  for _, commit in ipairs(commits) do
    if not seen_hashes[commit.hash] then
      errors[#errors + 1] = 'missing commit: ' .. commit.short_hash
    end
  end

  if #errors == 0 then
    io.write(string.format('%sPASS%s\n', color.green, color.reset))
    passed = passed + 1
    return
  end

  io.write(string.format('%sFAIL%s\n', color.red, color.reset))
  for i = 1, math.min(#errors, 5) do
    io.write('    ' .. errors[i] .. '\n')
  end
  if #errors > 5 then
    io.write('    ... and ' .. (#errors - 5) .. ' more\n')
  end
  failed = failed + 1
end

run_case('crossed branch joins', '0357ae54~1..HEAD')
run_case('nested merge joins', '2eb17050~1..419a960c')
run_case('side merge after crossover', '5b7e2846~1..2eb17050')
run_case('merge collapses through middle lane', '65a66c78~1..5a0206da')
run_case('wide merge with spaced continuation', '62b07ca6~1..HEAD')
run_case('multi-lane close after inner join', 'bf903126~1..5fe3a5a0')

io.write(string.format('\nproject-log kitty graph: %d passed, %d failed\n', passed, failed))
if failed > 0 then
  os.exit(1)
end
