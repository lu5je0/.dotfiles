local M = {}

local ori_v_count = 0
local replace_map = {
  increment = {},
  decrement = {},
}

local function reset_replace_map()
  replace_map = {
    increment = {},
    decrement = {},
  }
end

function M.generate(loop_list, allow_caps)
  for i = 1, #loop_list do
    local current = loop_list[i]
    local next = loop_list[i + 1] or loop_list[1]

    replace_map.increment[current] = next
    replace_map.decrement[next] = current

    if allow_caps then
      local capitalized_current = string.gsub(current, "^%l", string.upper)
      local capitalized_next = string.gsub(next, "^%l", string.upper)
      local all_caps_current = string.upper(current)
      local all_caps_next = string.upper(next)

      replace_map.increment[capitalized_current] = capitalized_next
      replace_map.decrement[capitalized_next] = capitalized_current
      replace_map.increment[all_caps_current] = all_caps_next
      replace_map.decrement[all_caps_next] = all_caps_current
    end
  end
end

local function setup_default_cycles()
  local letters = {
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  }

  for _, letter in ipairs(letters) do
    M.generate({
      letter .. 0,
      letter .. 1,
      letter .. 2,
      letter .. 3,
      letter .. 4,
      letter .. 5,
      letter .. 6,
      letter .. 7,
      letter .. 8,
      letter .. 9,
    }, true)
  end

  M.generate({ 'true', 'false' }, true)
  M.generate({ 'yes', 'no' }, true)
  M.generate({ 'on', 'off' }, true)
  M.generate({ 'enable', 'disable' }, true)
  M.generate({ 'enabled', 'disabled' }, true)

  M.generate({
    'Matins',
    'Lauds',
    'Prime',
    'Terce',
    'Sext',
    'Nones',
    'Vespers',
    'Compline',
    'Vigil',
  })

  M.generate({ 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday' }, true)
  M.generate({ 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun' }, true)

  M.generate({
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
  }, true)
end

local function check_postion_word(words, target_position, target_word)
  local i, j = string.find(words, "%S+")
  local position = 0

  if i == 1 then
    position = j
    if position > target_position then
      return string.find(words:sub(i, j), target_word)
    end
  end

  for word in string.gmatch(words, "%s+%S+") do
    position = position + string.len(word)
    local s_word = word:gsub("%s", "")
    if position - string.len(s_word) >= target_position then
      return false
    end
    if position > target_position then
      return string.find(s_word, target_word)
    end
  end

  return false
end

local function number_exist_in_word(line, current_column)
  local space_after_cursor = string.find(line:sub(current_column + 1, string.len(line)), " ")

  if space_after_cursor and space_after_cursor > 1 then
    local word_after_cursor = line:sub(current_column + 1, current_column + space_after_cursor)
    if string.match(word_after_cursor, "%d") then
      return true
    end
  elseif space_after_cursor == nil then
    local last_string = line:sub(current_column + 1, string.len(line))
    if string.match(last_string, "%d") then
      return true
    end
  end

  return false
end

local function get_hyphen_separated_numeric_segment(line, current_column)
  local col = current_column + 1
  local ch = line:sub(col, col)
  if ch == '' or not ch:match('%d') then
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
  local new_num = direction == 'decrement' and (old_num - delta) or (old_num + delta)

  local new = tostring(new_num)
  if old:sub(1, 1) == '0' and old_num >= 0 and new_num >= 0 and #new < #old then
    new = string.format('%0' .. tostring(#old) .. 'd', new_num)
  end

  return line:sub(1, start_col - 1) .. new .. line:sub(end_col + 1)
end

M.run = function(direction)
  local start_position = vim.api.nvim_win_get_cursor(0)
  local start_line = vim.api.nvim_get_current_line()
  local start_column = start_position[2]

  local function tryMatch(last_position)
    local line = vim.api.nvim_get_current_line()
    local cword = vim.fn.expand('<cword>')
    local current_position = vim.api.nvim_win_get_cursor(0)
    local current_column = current_position[2]

    if vim.v.count ~= 0 then
      ori_v_count = vim.v.count
    end

    if tonumber(cword) ~= nil or number_exist_in_word(line, current_column) then
      return false
    end

    if string.find(line:sub(current_column + 1, current_column + 1), "[^][a-zA-Z0-9]") then
      if (current_column + 1) == vim.fn.strlen(line) then
        vim.api.nvim_win_set_cursor(0, start_position)
        return false
      end
      vim.cmd('normal! w')
      return tryMatch(current_position)
    end

    if last_position[1] < current_position[1] then
      vim.api.nvim_win_set_cursor(0, start_position)
      return false
    end

    local match = direction == 'decrement'
      and replace_map.decrement[cword]
      or replace_map.increment[cword]

    if match then
      if cword:sub(1, 1) ~= line:sub(current_column + 1, current_column + 1) then
        if check_postion_word(line, current_column, cword) then
          vim.cmd('normal! b')
        else
          vim.cmd('normal! w')
        end
        return tryMatch(current_position)
      elseif (current_column + 1) == vim.fn.strlen(line) then
        vim.api.nvim_win_set_cursor(0, start_position)
        return false
      end

      for _ = 0, ori_v_count - 1 do
        match = direction == 'decrement'
          and replace_map.decrement[cword]
          or replace_map.increment[cword]
        if match then
          cword = match
        else
          return false
        end
      end

      ori_v_count = 0
      vim.cmd('normal! "_ciw' .. match)
      vim.cmd('normal! b')
      return true
    else
      if (current_column + 1) == vim.fn.strlen(line) then
        vim.api.nvim_win_set_cursor(0, start_position)
        return false
      end
      vim.cmd('normal! w')
      return tryMatch(current_position)
    end
  end

  if not tryMatch(start_position) then
    -- In values like 2026-02-24, Vim treats "-24" as a negative number for <C-a>/<C-x>.
    -- Handle the numeric segment explicitly as a positive value.
    local seg_start, seg_end = get_hyphen_separated_numeric_segment(start_line, start_column)
    if seg_start ~= nil and seg_end ~= nil then
      local target_v_count = ori_v_count
      ori_v_count = 0
      local new_line = apply_increment_on_segment(start_line, seg_start, seg_end, direction, target_v_count)
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

    local target_v_count = ori_v_count
    ori_v_count = 0
    if target_v_count ~= nil and target_v_count > 0 then
      if direction == 'increment' then
        return vim.cmd('normal!' .. target_v_count .. '\001')
      end
      if direction == 'decrement' then
        return vim.cmd('normal!' .. target_v_count .. '\024')
      end
    else
      if direction == 'increment' then
        return vim.cmd('normal!' .. '\001')
      end
      if direction == 'decrement' then
        return vim.cmd('normal!' .. '\024')
      end
    end
  end
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
    for _, val in pairs(options.allow_caps_additions) do
      M.generate(val, true)
    end
  end

  if options.additions ~= nil then
    for _, val in pairs(options.additions) do
      M.generate(val)
    end
  end

  pcall(vim.api.nvim_del_user_command, 'Boole')
  vim.api.nvim_create_user_command('Boole', function(args)
    M.run(args.args)
  end, {
    nargs = 1,
    complete = function()
      return { 'increment', 'decrement' }
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
