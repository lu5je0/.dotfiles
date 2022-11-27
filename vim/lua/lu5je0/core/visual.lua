local M = {}

function M.get_visual_selection_as_array()
  local _, ls, cs, le, ce = nil, nil, nil, nil, nil
  
  if vim.api.nvim_get_mode().mode == 'v' then
    _, ls, cs = unpack(vim.fn.getpos('v'))
    le, ce = unpack(vim.api.nvim_win_get_cursor(0))
  else
    _, ls, cs = unpack(vim.fn.getpos("'<"))
    _, le, ce = unpack(vim.fn.getpos("'>"))
    ce = ce - 1
  end
  
  -- 判断当前字符是否为多字节字符
  local offset = 1
  local cursor_char = vim.api.nvim_eval("strgetchar(getline('.')[col('.') - 1:], 0)")
  if cursor_char > 256 then
    offset = 3
  end
  
  return vim.api.nvim_buf_get_text(0, ls - 1, cs - 1, le - 1, ce + offset, {})
end

function M.get_visual_selection_as_string()
  return table.concat(M.get_visual_selection_as_array(), '\n')
end

function M.visual_replace(text)
  vim.fn['visual#replace'](text)
end

vim.keymap.set('v', 'M', function()
  print(M.get_visual_selection_as_string())
end, {})

return M
