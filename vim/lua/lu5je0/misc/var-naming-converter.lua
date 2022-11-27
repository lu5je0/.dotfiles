local M = {}
local visual_util = require('lu5je0.core.visual')

local function is_contain_space(var_name)
  return var_name:match(' ') ~= nil
end

local function split(var_name)
  var_name = var_name:gsub('(%S)(%u)', '%1_%2'):lower()
  local tokens = {}
  for token in string.gmatch(var_name, '[a-zA-Z0-9]+') do
    table.insert(tokens, token)
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

M.convert_to_camel = function(word_mode)
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

M.convert_to_snake = function(word_mode)
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

M.convert_to_pascal = function(word_mode)
  base_convert(function(tokens)
    local var_name = ''
    for _, token in ipairs(tokens) do
      var_name = var_name .. token:gsub('^%l', string.upper)
    end
    return var_name
  end, word_mode)

  vim_add_repeat('Pascal', word_mode)
end

M.convert_to_kebab = function(word_mode)
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

M.key_mapping = function()
  -- stylua: ignore start
  local opts = { desc = 'var-naming-converter.lua' }
  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToCamelWORD)', function() M.convert_to_camel('WORD') end, opts)
  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToCamelword)', function() M.convert_to_camel('word') end, opts)

  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToSnakeWORD)', function() M.convert_to_snake('WORD') end, opts)
  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToSnakeword)', function() M.convert_to_snake('word') end, opts)

  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToPascalWORD)', function() M.convert_to_pascal('WORD') end, opts)
  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToPascalword)', function() M.convert_to_pascal('word') end, opts)

  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToKebabWORD)', function() M.convert_to_kebab('WORD') end, opts)
  vim.keymap.set({ 'n', 'x' }, '<plug>(ConvertToKebabword)', function() M.convert_to_kebab('word') end, opts)
  
  vim.cmd[[
  xmap <leader>cnc <plug>(ConvertToCamelword)
  nmap <leader>cnc <plug>(ConvertToCamelword)
  nmap <leader>cnC <plug>(ConvertToCamelWORD)

  xmap <leader>cns <plug>(ConvertToSnakeword)
  nmap <leader>cns <plug>(ConvertToSnakeword)
  nmap <leader>cnS <plug>(ConvertToSnakeWORD)

  xmap <leader>cnk <plug>(ConvertToKebabword)
  nmap <leader>cnk <plug>(ConvertToKebabword)
  nmap <leader>cnK <plug>(ConvertToKebabWORD)

  xmap <leader>cnp <plug>(ConvertToPascalword)
  nmap <leader>cnp <plug>(ConvertToPascalword)
  nmap <leader>cnP <plug>(ConvertToPascalWORD)
  ]]
  -- stylua: ignore end
end

return M
