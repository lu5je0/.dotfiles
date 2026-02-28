local M = {}

local function all_trim(s)
  return s:match('^%s*(.*)'):match('(.-)%s*$')
end

local function split_ws(line)
  return vim.split(line, '%s+', { trimempty = true })
end

local MONTH_NAME_MAP = {
  JAN = 1,
  FEB = 2,
  MAR = 3,
  APR = 4,
  MAY = 5,
  JUN = 6,
  JUL = 7,
  AUG = 8,
  SEP = 9,
  OCT = 10,
  NOV = 11,
  DEC = 12,
}

local DOW_NAME_MAP = {
  SUN = 0,
  MON = 1,
  TUE = 2,
  WED = 3,
  THU = 4,
  FRI = 5,
  SAT = 6,
}

local function parse_value(raw, min_v, max_v, name_map, is_dow)
  if raw == nil or raw == '' then
    return nil
  end

  local v = tonumber(raw)
  if not v then
    local key = raw:upper()
    v = name_map and name_map[key] or nil
  end

  if v == nil then
    return nil
  end

  if is_dow and v == 7 then
    v = 0
  end

  if v < min_v or v > max_v then
    return nil
  end

  return v
end

local function parse_field(field, opts)
  local min_v = opts.min
  local max_v = opts.max
  local name_map = opts.names
  local is_dow = opts.is_dow or false

  if field == '*' then
    return { any = true, set = nil }
  end

  local set = {}
  local parts = vim.split(field, ',', { trimempty = true })
  if #parts == 0 then
    return nil
  end

  for _, part in ipairs(parts) do
    local base, step_s = part:match('^(.-)/(%d+)$')
    local step = step_s and tonumber(step_s) or 1
    if step == nil or step <= 0 then
      return nil
    end

    local target = base or part
    if target == '' then
      return nil
    end

    local start_v, end_v
    if target == '*' then
      start_v = min_v
      end_v = max_v
    else
      local left, right = target:match('^([^%-]+)%-(.+)$')
      if left and right then
        start_v = parse_value(left, min_v, max_v, name_map, is_dow)
        end_v = parse_value(right, min_v, max_v, name_map, is_dow)
        if start_v == nil or end_v == nil or start_v > end_v then
          return nil
        end
      else
        start_v = parse_value(target, min_v, max_v, name_map, is_dow)
        if start_v == nil then
          return nil
        end
        if base then
          end_v = max_v
        else
          end_v = start_v
        end
      end
    end

    for v = start_v, end_v, step do
      set[v] = true
    end
  end

  return { any = false, set = set }
end

local function parse_cron_expr(expr)
  local fields = split_ws(expr)
  if #fields ~= 5 then
    return nil, 'cron expression must contain exactly 5 fields'
  end

  local minute = parse_field(fields[1], { min = 0, max = 59 })
  local hour = parse_field(fields[2], { min = 0, max = 23 })
  local dom = parse_field(fields[3], { min = 1, max = 31 })
  local month = parse_field(fields[4], { min = 1, max = 12, names = MONTH_NAME_MAP })
  local dow = parse_field(fields[5], { min = 0, max = 7, names = DOW_NAME_MAP, is_dow = true })

  if minute == nil or hour == nil or dom == nil or month == nil or dow == nil then
    return nil, 'invalid cron field'
  end

  return {
    minute = minute,
    hour = hour,
    dom = dom,
    month = month,
    dow = dow,
  }, nil
end

local function field_match(field, v)
  if field.any then
    return true
  end
  return field.set[v] == true
end

local function day_match(schedule, dom_v, dow_v)
  local dom_any = schedule.dom.any
  local dow_any = schedule.dow.any
  local dom_ok = field_match(schedule.dom, dom_v)
  local dow_ok = field_match(schedule.dow, dow_v)

  if dom_any and dow_any then
    return true
  end
  if dom_any then
    return dow_ok
  end
  if dow_any then
    return dom_ok
  end
  return dom_ok or dow_ok
end

local function timestamp_match(schedule, ts)
  local t = os.date('*t', ts)
  local dow_v = t.wday - 1

  return field_match(schedule.minute, t.min)
      and field_match(schedule.hour, t.hour)
      and field_match(schedule.month, t.month)
      and day_match(schedule, t.day, dow_v)
end

local function next_runs(schedule, count, now_ts)
  local now = now_ts or os.time()
  local ts = now - (now % 60) + 60
  local out = {}
  local max_steps = 60 * 24 * 366 * 10 -- 10 years
  local steps = 0

  while #out < count and steps < max_steps do
    if timestamp_match(schedule, ts) then
      table.insert(out, os.date('%Y-%m-%d %H:%M:%S', ts))
    end
    ts = ts + 60
    steps = steps + 1
  end

  return out
end

local function extract_cron_expr(line)
  local fields = split_ws(line)
  if #fields < 5 then
    return nil
  end

  for i = 1, (#fields - 4) do
    local expr = table.concat({ fields[i], fields[i + 1], fields[i + 2], fields[i + 3], fields[i + 4] }, ' ')
    local schedule = parse_cron_expr(expr)
    if schedule ~= nil then
      return expr
    end
  end

  return nil
end

function M.parse_line(count)
  count = tonumber(count) or 10
  if count <= 0 then
    count = 10
  end

  local line = all_trim(vim.api.nvim_get_current_line())
  local expr = extract_cron_expr(line)
  if expr == nil then
    vim.notify('CronParser: no valid 5-field cron expression found in current line', vim.log.levels.ERROR)
    return
  end

  local schedule, err = parse_cron_expr(expr)
  if schedule == nil then
    vim.notify('CronParser: ' .. err, vim.log.levels.ERROR)
    return
  end

  local runs = next_runs(schedule, count)
  if #runs == 0 then
    vim.notify('CronParser: no next run found in 10 years (check expression)', vim.log.levels.ERROR)
    return
  end

  print(expr)
  print(table.concat(runs, '\n'))
end

M._test = {
  parse_cron_expr = parse_cron_expr,
  extract_cron_expr = extract_cron_expr,
  next_runs = next_runs,
}

return M
