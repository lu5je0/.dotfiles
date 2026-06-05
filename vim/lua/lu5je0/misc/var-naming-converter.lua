local M = {}
local visual_util = require('lu5je0.core.visual')

local function is_contain_space(var_name)
  return var_name:match(' ') ~= nil
end

local function split(var_name)
  local chunks = {}
  for chunk in var_name:gmatch('[a-zA-Z0-9]+') do
    chunks[#chunks + 1] = chunk
  end
  local tokens = {}
  for _, chunk in ipairs(chunks) do
    local i = 1
    while i <= #chunk do
      local j = i + 1
      local ch = chunk:sub(i, i)
      if ch:match('%u') then
        if j <= #chunk and chunk:sub(j, j):match('%u') then
          while j <= #chunk and chunk:sub(j, j):match('%u') do j = j + 1 end
          if j <= #chunk and chunk:sub(j, j):match('%l') then j = j - 1 end
        else
          while j <= #chunk and chunk:sub(j, j):match('[%l%d]') do j = j + 1 end
        end
      else
        while j <= #chunk and chunk:sub(j, j):match('[%l%d]') do j = j + 1 end
      end
      tokens[#tokens + 1] = chunk:sub(i, j - 1):lower()
      i = j
    end
  end
  return tokens
end

local function get_var_name(word_mode)
  local var_name = nil
  if vim.api.nvim_get_mode().mode == 'v' then
    var_name = visual_util.get_visual_selection_as_string()
  else
    if word_mode == 'WORD' then
      var_name = vim.fn.expand('<cWORD>')
    else
      var_name = vim.fn.expand('<cword>')
    end
  end
  return var_name
end

local function replace_var(var_name)
  visual_util.visual_replace(var_name)
end

local function base_convert(convert_strategy_fn, word_mode)
  local var_name = get_var_name(word_mode)
  if not is_contain_space(var_name) then
    local tokens = split(var_name)
    var_name = convert_strategy_fn(tokens)
    if vim.api.nvim_get_mode().mode == 'n' then
      if word_mode == 'WORD' then
        vim.cmd('norm viW')
      else
        vim.cmd('norm viw')
      end
    end
    replace_var(var_name)
  end
end

local function vim_add_repeat(case_type, word_mode)
  local cmd = [[call repeat#set("\<plug>(ConvertTo%s%s)", 1)]]
  cmd = cmd:format(case_type, word_mode)
  vim.cmd(cmd)
end

function M.convert_to_camel(word_mode)
  base_convert(function(tokens)
    local var_name = ''
    for i, token in ipairs(tokens) do
      if i == 1 then
        var_name = var_name .. token
      else
        var_name = var_name .. token:gsub('^%l', string.upper)
      end
    end
    return var_name
  end, word_mode)

  vim_add_repeat('Camel', word_mode)
end

function M.convert_to_snake(word_mode)
  base_convert(function(tokens)
    local var_name = ''
    for i, token in ipairs(tokens) do
      if i == 1 then
        var_name = var_name .. token
      else
        var_name = var_name .. '_' .. token
      end
    end
    return var_name
  end, word_mode)

  vim_add_repeat('Snake', word_mode)
end

function M.convert_to_pascal(word_mode)
  base_convert(function(tokens)
    local var_name = ''
    for _, token in ipairs(tokens) do
      var_name = var_name .. token:gsub('^%l', string.upper)
    end
    return var_name
  end, word_mode)

  vim_add_repeat('Pascal', word_mode)
end

function M.convert_to_kebab(word_mode)
  base_convert(function(tokens)
    local var_name = ''
    for i, token in ipairs(tokens) do
      if i == 1 then
        var_name = var_name .. token
      else
        var_name = var_name .. '-' .. token
      end
    end
    return var_name
  end, word_mode)

  vim_add_repeat('Kebab', word_mode)
end

local converters = {
  { name = 'camelCase',  fn = function(tokens)
    local r = ''
    for i, t in ipairs(tokens) do r = r .. (i == 1 and t or t:gsub('^%l', string.upper)) end
    return r
  end },
  { name = 'snake_case', fn = function(tokens) return table.concat(tokens, '_') end },
  { name = 'PascalCase', fn = function(tokens)
    local r = ''
    for _, t in ipairs(tokens) do r = r .. t:gsub('^%l', string.upper) end
    return r
  end },
  { name = 'kebab-case', fn = function(tokens) return table.concat(tokens, '-') end },
  { name = 'UPPER_CASE', fn = function(tokens) return table.concat(tokens, '_'):upper() end },
}

local function generate_items(var_name)
  local tokens = split(var_name)
  local items = {}
  local seen = {}
  for _, c in ipairs(converters) do
    local result = c.fn(tokens)
    if result ~= var_name and not seen[result] then
      seen[result] = true
      items[#items + 1] = result
    end
  end
  return items
end

local function show_menu(items, screen_row, screen_col, on_select, on_cancel)
  local menu_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(menu_buf, 0, -1, false, items)
  vim.bo[menu_buf].modifiable = false

  local width = 0
  for _, item in ipairs(items) do width = math.max(width, vim.fn.strdisplaywidth(item)) end
  width = math.max(width, 1)

  local menu_win = vim.api.nvim_open_win(menu_buf, false, {
    relative = 'editor',
    row = screen_row,
    col = screen_col,
    width = width,
    height = #items,
    style = 'minimal',
    border = 'none',
    zindex = 200,
    focusable = true,
  })
  vim.api.nvim_set_current_win(menu_win)
  vim.wo[menu_win].cursorline = true
  vim.wo[menu_win].cursorlineopt = 'both'
  vim.wo[menu_win].winhighlight = 'Normal:Pmenu,CursorLine:PmenuSel,Search:None'

  local closed = false
  local function close(cb)
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(menu_win) then
      vim.api.nvim_win_close(menu_win, true)
    end
    if cb then cb() end
  end

  local bopts = { buffer = menu_buf, nowait = true, silent = true }
  vim.keymap.set('n', '<cr>', function()
    local idx = vim.api.nvim_win_get_cursor(menu_win)[1]
    close(function() on_select(items[idx]) end)
  end, bopts)
  vim.keymap.set('n', '<esc>', function() close(on_cancel) end, bopts)
  vim.keymap.set('n', 'q', function() close(on_cancel) end, bopts)
  vim.keymap.set('n', 'j', 'j', bopts)
  vim.keymap.set('n', 'k', 'k', bopts)

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = menu_buf,
    once = true,
    callback = function() close(on_cancel) end,
  })
end

function M.select_convert(word_mode)
  local in_dressing = vim.bo.filetype == 'DressingInput'
  local is_visual = vim.api.nvim_get_mode().mode == 'v'

  local vis_start_lnum, vis_start_col, vis_end_col
  if is_visual then
    local v = vim.fn.getpos('v')
    local dot = vim.fn.getpos('.')
    if v[2] < dot[2] or (v[2] == dot[2] and v[3] <= dot[3]) then
      vis_start_lnum, vis_start_col, vis_end_col = v[2], v[3], dot[3]
    else
      vis_start_lnum, vis_start_col, vis_end_col = dot[2], dot[3], v[3]
    end
  end

  local var_name
  if in_dressing then
    var_name = vim.trim(vim.api.nvim_get_current_line())
  else
    var_name = get_var_name(word_mode)
  end
  if not var_name or var_name == '' or is_contain_space(var_name) then return end

  if is_visual then
    vim.cmd('normal! \027')
  end

  local items = generate_items(var_name)
  if #items == 0 then return end

  local src_buf = vim.api.nvim_get_current_buf()
  local src_win = vim.api.nvim_get_current_win()
  local ns = vim.api.nvim_create_namespace('var_naming_hl')
  local lnum, word_byte_col

  if in_dressing then
    lnum = 1
    word_byte_col = 1
    vim.api.nvim_buf_add_highlight(src_buf, ns, 'Visual', 0, 0, #var_name)
  elseif is_visual then
    lnum = vis_start_lnum
    word_byte_col = vis_start_col
    vim.api.nvim_buf_add_highlight(src_buf, ns, 'Visual', lnum - 1, vis_start_col - 1, vis_end_col)
  else
    lnum = vim.fn.line('.')
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col('.')
    local before = line:sub(1, col)
    word_byte_col = before:find('[%w_]*$') or col
    local word_start = word_byte_col - 1
    vim.api.nvim_buf_add_highlight(src_buf, ns, 'Visual', lnum - 1, word_start, word_start + #var_name)
  end

  local spos = vim.fn.screenpos(src_win, lnum, word_byte_col)
  local screen_row = spos.row
  local screen_col = spos.col - 1

  local function clear_hl()
    if vim.api.nvim_buf_is_valid(src_buf) then
      vim.api.nvim_buf_clear_namespace(src_buf, ns, 0, -1)
    end
  end

  show_menu(items, screen_row, screen_col, function(choice)
    clear_hl()
    if in_dressing then
      if vim.api.nvim_buf_is_valid(src_buf) then
        vim.bo[src_buf].modifiable = true
        vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, { choice })
        vim.api.nvim_set_current_buf(src_buf)
        vim.cmd('normal! $')
      end
    else
      vim.api.nvim_set_current_buf(src_buf)
      if is_visual then
        vim.cmd('normal! gv')
      else
        if word_mode == 'WORD' then
          vim.cmd('normal! viW')
        else
          vim.cmd('normal! viw')
        end
      end
      replace_var(choice)
    end
  end, clear_hl)
end

function M.key_mapping()
  local opts = { desc = 'var-naming-converter.lua' }
  vim.keymap.set({ 'n', 'x' }, '<leader>cn', function() M.select_convert('word') end, opts)
end

return M
