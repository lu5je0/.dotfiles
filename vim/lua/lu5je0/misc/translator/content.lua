local M = {}

local function trim(s)
  if s == nil or s == vim.NIL then
    return ''
  end
  if type(s) ~= 'string' then
    s = tostring(s)
  end
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

function M.build_display_lines(result)
  local lines = {}
  local hls = {}

  local function add_line(text, hl)
    table.insert(lines, text)
    if hl then
      table.insert(hls, { row = #lines - 1, col_start = 0, col_end = -1, hl = hl })
    end
  end

  local engine = result.engine or ''
  local phonetic = result.phonetic or ''
  local translation = trim(result.translation or '')
  local definition = trim(result.definition or '')
  local exchange = trim(result.exchange or '')

  if engine ~= '' then
    add_line('[' .. engine .. ']', 'Identifier')
  end
  add_line('[' .. phonetic .. ']', 'Function')

  add_line('中文释义：', 'Title')
  if translation ~= '' then
    for _, line in ipairs(vim.split(translation, '\n', { plain = true, trimempty = true })) do
      add_line(trim(line), 'String')
    end
  else
    add_line('(empty)', 'Comment')
  end

  if definition ~= '' then
    add_line(engine == 'hanzi' and '补充信息：' or '英文释义：', 'Title')
    for _, line in ipairs(vim.split(definition, '\n', { plain = true, trimempty = true })) do
      add_line(trim(line))
    end
  end

  if exchange ~= '' then
    add_line('变形：', 'Title')
    for _, line in ipairs(vim.split(exchange, '\n', { plain = true, trimempty = true })) do
      add_line(trim(line), 'Constant')
    end
  end

  return lines, hls
end

function M.first_meaning(result)
  local translation = trim(result.translation or '')
  if translation == '' then
    return nil
  end
  local first = vim.split(translation, '\n', { plain = true, trimempty = true })[1]
  if not first then
    return nil
  end
  return trim((first:gsub('^%a+%.%s*', '')))
end

return M
