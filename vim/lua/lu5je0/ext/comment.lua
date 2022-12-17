local function gcc()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local fold_close_end_line = vim.fn.foldclosedend(line)
  if fold_close_end_line ~= -1 then
    require('lu5je0.core.keys').feedkey((fold_close_end_line - line + 1) .. '<Plug>(comment_toggle_linewise_count)')
  else
    require('lu5je0.core.keys').feedkey(vim.api.nvim_get_vvar('count') == 0 and '<Plug>(comment_toggle_linewise_current)' or '10<Plug>(comment_toggle_linewise_count)')
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
