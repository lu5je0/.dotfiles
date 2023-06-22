local M = {}

local keys = require('lu5je0.core.keys')

local group = vim.api.nvim_create_augroup('VM_custom', { clear = true })

local MODE = {
  NORMAL = 'NORMAL',
  VISUAL = 'VISUAL',
}

function M.mode()
  if vim.g['Vm'].extend_mode == 1 then
    return MODE.VISUAL
  else
    return MODE.NORMAL
  end
end

function M.setup()
  vim.g.VM_show_warnings = 0
  vim.g.VM_set_statusline = 0
  vim.g.VM_silent_exit = 1

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'visual_multi_mappings',
    callback = function()
      vim.cmd [[
      nmap <buffer> <leader>y "+y
      nmap <buffer> <silent> v :call b:VM_Selection.Global.extend_mode()<cr>
      ]]
      vim.keymap.set('n', '<esc>', function()
        if M.mode() == MODE.VISUAL then
          vim.cmd('call b:VM_Selection.Global.cursor_mode()')
        else
          keys.feedkey('<Plug>(VM-Exit)')
        end
      end, { buffer = true })
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'visual_multi_exit',
    callback = function()
      vim.cmd [[
      silent! unmap <buffer> <leader>y
      silent! unmap <buffer> v
      ]]
    end,
  })

  vim.g.VM_custom_motions = {
    ['L'] = '$',
    ['H'] = '^',
  }
end

return M
