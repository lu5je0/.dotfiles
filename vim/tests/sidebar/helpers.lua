-- Shared test infrastructure for sidebar specs.
-- Usage:
--   local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/helpers.lua')
-- or, with package.path patched:
--   local h = require('sidebar.helpers')

local M = {}

M.color = {
  reset = '\27[0m',
  green = '\27[32m',
  red = '\27[31m',
  cyan = '\27[36m',
}

local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
M.eq = deep_eq

function M.dump(v, depth)
  depth = depth or 0
  if depth > 4 then return '...' end
  if type(v) ~= 'table' then return tostring(v) end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = string.format('%s=%s', tostring(k), M.dump(val, depth + 1))
  end
  table.sort(parts)
  return '{' .. table.concat(parts, ', ') .. '}'
end

--- Construct a fresh runner with its own pass/fail counters and
--- group/run/assert/finish helpers. Each spec file builds one runner.
function M.make_runner()
  local color = M.color
  local passed, failed = 0, 0

  local function group(name)
    io.write(color.cyan .. name .. color.reset .. '\n')
  end

  local function run(name, fn)
    io.write('  ' .. name .. ' ... ')
    local ok, err = pcall(fn)
    if ok then
      io.write(color.green .. 'PASS' .. color.reset .. '\n')
      passed = passed + 1
    else
      io.write(color.red .. 'FAIL' .. color.reset .. '\n    ' .. tostring(err) .. '\n')
      failed = failed + 1
    end
  end

  local function assert_eq(actual, expected, msg)
    if not deep_eq(actual, expected) then
      error(string.format('%s\n      actual:   %s\n      expected: %s',
        msg or 'assertion failed', M.dump(actual), M.dump(expected)), 2)
    end
  end

  local function assert_truthy(v, msg)
    if not v then error(msg or 'expected truthy, got nil/false', 2) end
  end

  local function finish()
    io.write(string.format('\n%s passed, %s failed\n',
      color.green .. tostring(passed) .. color.reset,
      (failed > 0 and color.red or color.green) .. tostring(failed) .. color.reset))
    if failed > 0 then os.exit(1) end
  end

  return {
    group = group,
    run = run,
    assert_eq = assert_eq,
    assert_truthy = assert_truthy,
    finish = finish,
    passed = function() return passed end,
    failed = function() return failed end,
  }
end

return M
