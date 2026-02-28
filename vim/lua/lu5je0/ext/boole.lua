local M = {}

local DIRECTIONS = {
  increment = 'increment',
  decrement = 'decrement',
}

local DEFAULT_CYCLES = {
  { values = { 'true', 'false' }, allow_caps = true },
  { values = { 'yes', 'no' }, allow_caps = true },
  { values = { 'on', 'off' }, allow_caps = true },
  { values = { 'enable', 'disable' }, allow_caps = true },
  { values = { 'enabled', 'disabled' }, allow_caps = true },
  { values = { 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday' }, allow_caps = true },
  { values = { 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun' }, allow_caps = true },
  {
    values = {
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    },
    allow_caps = true,
  },
}

local state = {
  count = 0,
  replace_map = {
    increment = {},
    decrement = {},
  },
}

local function reset_replace_map()
  state.replace_map = {
    increment = {},
    decrement = {},
  }
end

local function capitalize_first(value)
  return value:gsub('^%l', string.upper)
end

local function get_map(direction)
  if direction == DIRECTIONS.decrement then
    return state.replace_map.decrement
  end
  return state.replace_map.increment
end

local function is_line_end(line, col0)
  return (col0 + 1) == vim.fn.strlen(line)
end

local function first_char_under_cursor(line, col0)
  return line:sub(col0 + 1, col0 + 1)
end

local function move_next_word()
  vim.cmd('normal! w')
end

local function move_prev_word()
  vim.cmd('normal! b')
end

local function reset_cursor(pos)
  vim.api.nvim_win_set_cursor(0, pos)
end

local function consume_count()
  local count = state.count
  state.count = 0
  return count
end

local function word_contains_position_word(words, target_position, target_word)
  local i, j = words:find('%S+')
  local position = 0

  if i == 1 then
    position = j
    if position > target_position then
      return words:sub(i, j):find(target_word)
    end
  end

  for word in words:gmatch('%s+%S+') do
    position = position + #word
    local trimmed_word = word:gsub('%s', '')
    if position - #trimmed_word >= target_position then
      return false
    end
    if position > target_position then
      return trimmed_word:find(target_word)
    end
  end

  return false
end

local function has_number_after_cursor_in_word(line, col0)
  local segment = line:sub(col0 + 1, #line)
  local space_after_cursor = segment:find(' ')

  if space_after_cursor and space_after_cursor > 1 then
    return line:sub(col0 + 1, col0 + space_after_cursor):match('%d') ~= nil
  end
  if space_after_cursor == nil then
    return line:sub(col0 + 1, #line):match('%d') ~= nil
  end

  return false
end

local function get_hyphen_separated_numeric_segment(line, col0)
  local col = col0 + 1
  local ch = line:sub(col, col)
  if ch == '' or ch:match('%d') == nil then
    return nil
  end

  local start_col = col
  while start_col > 1 and line:sub(start_col - 1, start_col - 1):match('%d') do
    start_col = start_col - 1
  end

  local end_col = col
  while line:sub(end_col + 1, end_col + 1):match('%d') do
    end_col = end_col + 1
  end

  local prev = line:sub(start_col - 1, start_col - 1)
  local prev_prev = line:sub(start_col - 2, start_col - 2)
  if prev == '-' and prev_prev:match('%d') ~= nil then
    return start_col, end_col
  end
  return nil
end

local function apply_increment_on_segment(line, start_col, end_col, direction, count)
  local old = line:sub(start_col, end_col)
  local old_num = tonumber(old)
  if old_num == nil then
    return nil
  end

  local delta = count > 0 and count or 1
  local new_num = direction == DIRECTIONS.decrement and (old_num - delta) or (old_num + delta)

  local new = tostring(new_num)
  if old:sub(1, 1) == '0' and old_num >= 0 and new_num >= 0 and #new < #old then
    new = string.format('%0' .. tostring(#old) .. 'd', new_num)
  end

  return line:sub(1, start_col - 1) .. new .. line:sub(end_col + 1)
end

local function apply_vim_default_increment(direction, count)
  if count ~= nil and count > 0 then
    if direction == DIRECTIONS.increment then
      return vim.cmd('normal!' .. count .. '\001')
    end
    if direction == DIRECTIONS.decrement then
      return vim.cmd('normal!' .. count .. '\024')
    end
    return
  end

  if direction == DIRECTIONS.increment then
    return vim.cmd('normal!' .. '\001')
  end
  if direction == DIRECTIONS.decrement then
    return vim.cmd('normal!' .. '\024')
  end
end

local function next_cycle_value(direction, current, count)
  local map = get_map(direction)
  local next_value = map[current]
  if not next_value then
    return nil
  end

  local steps = count > 0 and count or 1
  for _ = 1, steps - 1 do
    next_value = map[next_value]
    if not next_value then
      return nil
    end
  end

  return next_value
end

local function replace_current_word(value)
  vim.cmd('normal! "_ciw' .. value)
  move_prev_word()
end

local function try_cycle_replace(direction, start_position)
  local last_position = start_position

  while true do
    local line = vim.api.nvim_get_current_line()
    local cword = vim.fn.expand('<cword>')
    local current_position = vim.api.nvim_win_get_cursor(0)
    local current_column = current_position[2]

    if tonumber(cword) ~= nil or has_number_after_cursor_in_word(line, current_column) then
      return false
    end

    local cursor_char = first_char_under_cursor(line, current_column)
    if cursor_char:find('[^][a-zA-Z0-9]') then
      if is_line_end(line, current_column) then
        reset_cursor(start_position)
        return false
      end
      move_next_word()
      last_position = current_position
    elseif last_position[1] < current_position[1] then
      reset_cursor(start_position)
      return false
    else
      local match = get_map(direction)[cword]
      if match then
        if cword:sub(1, 1) ~= cursor_char then
          if word_contains_position_word(line, current_column, cword) then
            move_prev_word()
          else
            move_next_word()
          end
          last_position = current_position
        elseif is_line_end(line, current_column) then
          reset_cursor(start_position)
          return false
        else
          local replacement = next_cycle_value(direction, cword, state.count)
          if not replacement then
            return false
          end
          consume_count()
          replace_current_word(replacement)
          return true
        end
      else
        if is_line_end(line, current_column) then
          reset_cursor(start_position)
          return false
        end
        move_next_word()
        last_position = current_position
      end
    end
  end
end

function M.generate(loop_list, allow_caps)
  for i = 1, #loop_list do
    local current = loop_list[i]
    local next_value = loop_list[i + 1] or loop_list[1]

    state.replace_map.increment[current] = next_value
    state.replace_map.decrement[next_value] = current

    if allow_caps then
      local title_current = capitalize_first(current)
      local title_next = capitalize_first(next_value)
      local upper_current = current:upper()
      local upper_next = next_value:upper()

      state.replace_map.increment[title_current] = title_next
      state.replace_map.decrement[title_next] = title_current
      state.replace_map.increment[upper_current] = upper_next
      state.replace_map.decrement[upper_next] = upper_current
    end
  end
end

local function setup_default_cycles()
  for byte = string.byte('a'), string.byte('z') do
    local letter = string.char(byte)
    local loop = {}
    for n = 0, 9 do
      loop[#loop + 1] = letter .. n
    end
    M.generate(loop, true)
  end

  for _, cycle in ipairs(DEFAULT_CYCLES) do
    M.generate(cycle.values, cycle.allow_caps)
  end
end

function M.run(direction)
  local start_position = vim.api.nvim_win_get_cursor(0)
  local start_line = vim.api.nvim_get_current_line()
  local start_column = start_position[2]

  if direction ~= DIRECTIONS.increment and direction ~= DIRECTIONS.decrement then
    return
  end
  state.count = vim.v.count ~= 0 and vim.v.count or 0

  if try_cycle_replace(direction, start_position) then
    return
  end

  -- For values like 2026-02-24, Vim treats "-24" as negative on <C-a>/<C-x>.
  -- Handle the numeric segment after "-" as positive.
  local seg_start, seg_end = get_hyphen_separated_numeric_segment(start_line, start_column)
  if seg_start ~= nil and seg_end ~= nil then
    local target_count = consume_count()
    local new_line = apply_increment_on_segment(start_line, seg_start, seg_end, direction, target_count)
    if new_line ~= nil then
      vim.api.nvim_set_current_line(new_line)
      local new_seg_end = seg_start
      while new_line:sub(new_seg_end + 1, new_seg_end + 1):match('%d') do
        new_seg_end = new_seg_end + 1
      end
      vim.api.nvim_win_set_cursor(0, { start_position[1], new_seg_end - 1 })
    end
    return
  end

  apply_vim_default_increment(direction, consume_count())
end

function M.setup(opts)
  reset_replace_map()
  setup_default_cycles()

  local options = vim.tbl_deep_extend('force', {
    mappings = {},
    additions = {
      -- { 'Foo', 'Bar' },
    },
    allow_caps_additions = {
      { 'enable', 'disable' },
    },
  }, opts or {})

  if options.allow_caps_additions ~= nil then
    for _, cycle in pairs(options.allow_caps_additions) do
      M.generate(cycle, true)
    end
  end

  if options.additions ~= nil then
    for _, cycle in pairs(options.additions) do
      M.generate(cycle)
    end
  end

  pcall(vim.api.nvim_del_user_command, 'Boole')
  vim.api.nvim_create_user_command('Boole', function(args)
    M.run(args.args)
  end, {
    nargs = 1,
    complete = function()
      return { DIRECTIONS.increment, DIRECTIONS.decrement }
    end,
  })

  vim.keymap.set('n', '<c-a>', require('lu5je0.core.cursor').wapper_fn_for_solid_guicursor(function()
    vim.cmd('Boole increment')
  end))

  vim.keymap.set('n', '<c-x>', require('lu5je0.core.cursor').wapper_fn_for_solid_guicursor(function()
    vim.cmd('Boole decrement')
  end))

  if options.mappings.increment ~= nil then
    vim.keymap.set({ 'n', 'v' }, options.mappings.increment, '<Cmd>Boole increment<CR>')
  end

  if options.mappings.decrement ~= nil then
    vim.keymap.set({ 'n', 'v' }, options.mappings.decrement, '<Cmd>Boole decrement<CR>')
  end
end

return M
