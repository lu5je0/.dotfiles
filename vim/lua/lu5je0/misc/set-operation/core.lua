local M = {}

local OP_SYMBOL = {
  intersection = '∩',
  difference = '-',
  union = '∪',
}

local function collect_sets(lines)
  local set_a = {}
  local set_b = {}
  local blank_line_count = 0

  for _, line in ipairs(lines) do
    if line:match('^%s*$') then
      blank_line_count = blank_line_count + 1
    elseif blank_line_count == 0 then
      set_a[line] = true
    else
      set_b[line] = true
    end
  end

  return set_a, set_b, blank_line_count
end

local function set_size(set_tbl)
  local n = 0
  for _, _ in pairs(set_tbl) do
    n = n + 1
  end
  return n
end

local function set_to_sorted_list(set_tbl)
  local result = {}
  for line, _ in pairs(set_tbl) do
    table.insert(result, line)
  end
  table.sort(result)
  return result
end

local function intersection(set_a, set_b)
  local r = {}
  for k, _ in pairs(set_a) do
    if set_b[k] then
      r[k] = true
    end
  end
  return r
end

local function difference(set_a, set_b)
  local r = {}
  for k, _ in pairs(set_a) do
    if not set_b[k] then
      r[k] = true
    end
  end
  return r
end

local function union(set_a, set_b)
  local r = {}
  for k, _ in pairs(set_a) do
    r[k] = true
  end
  for k, _ in pairs(set_b) do
    r[k] = true
  end
  return r
end

function M.run(operation)
  if not operation or operation == '' then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  vim.bo[buf].filetype = 'none'

  local ok, err = pcall(function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local before_line_count = #lines
    local set_a, set_b, blank_line_count = collect_sets(lines)

    if blank_line_count ~= 1 then
      vim.notify('Only one empty line allowed', vim.log.levels.WARN)
      return
    end

    local result_set
    if operation == 'intersection' then
      result_set = intersection(set_a, set_b)
    elseif operation == 'difference' then
      result_set = difference(set_a, set_b)
    elseif operation == 'union' then
      result_set = union(set_a, set_b)
    else
      vim.notify('Unknown operation: ' .. operation, vim.log.levels.WARN)
      return
    end

    local a_count = set_size(set_a)
    local b_count = set_size(set_b)
    local result_lines = set_to_sorted_list(result_set)
    local result_count = #result_lines
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, result_lines)

    local symbol = OP_SYMBOL[operation] or '?'
    local summary = string.format(
      'SetOperation: A(%d) %s B(%d) = R(%d) | lines: %d -> %d',
      a_count,
      symbol,
      b_count,
      result_count,
      before_line_count,
      result_count
    )
    vim.notify(summary)
  end)

  vim.bo[buf].filetype = ft

  if not ok then
    vim.notify('SetOperation failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
