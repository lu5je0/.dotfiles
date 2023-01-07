local function gcc()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local fold_close_end_line = vim.fn.foldclosedend(line)
  
  -- 如果当前行是foldedline
  if fold_close_end_line ~= -1 then
    
    -- 如果fold_close_end_line是最后一行要特殊处理, 不然无法注释
    if vim.api.nvim_buf_line_count(0) == fold_close_end_line then
      vim.cmd('norm zo')
    end
    
    require('lu5je0.core.keys').feedkey((fold_close_end_line - line + 1) .. '<Plug>(comment_toggle_linewise_count)')

    -- 给注释创建fold
    -- vim.defer_fn(function()
    --   vim.cmd('norm zf' .. (fold_close_end_line - line) .. 'j')
    -- end, 0)
  else
    local op_cnt = vim.api.nvim_get_vvar('count')
    if op_cnt == 0 then
      require('lu5je0.core.keys').feedkey('<Plug>(comment_toggle_linewise_current)') 
    else
      require('lu5je0.core.keys').feedkey(tostring(op_cnt) .. '<Plug>(comment_toggle_linewise_count)')
    end
  end
end

require('Comment').setup {
  opleader = {
    -- Line-comment keymap
    line = 'gc',
    -- Block-comment keymap
    block = 'gC',
  },
  toggler = {
    -- Line-comment toggle keymap
    line = 'gcc',
    -- Block-comment toggle keymap
    block = 'gcgc',
  },
}
vim.keymap.set('n', 'gcc', gcc)
