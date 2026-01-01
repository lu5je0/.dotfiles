local M = {}

local keys = require('lu5je0.core.keys')

local group = vim.api.nvim_create_augroup('VM_custom', { clear = true })

local MODE = {
  NORMAL = 'n',
  VISUAL = 'v',
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
      nmap <nowait> <buffer> p "+<Plug>(VM-p-Paste)
      nmap <buffer> <silent> v :call b:VM_Selection.Global.extend_mode()<cr>
      nmap <buffer> <c-x> <Plug>(VM-Skip-Region)
      nmap <buffer> <c-p> <Plug>(VM-Remove-Region)
      ]]

      keys.wrap_mapping('n', '<Esc>', function(rhs)
        if M.mode() == MODE.VISUAL then
          vim.cmd('call b:VM_Selection.Global.cursor_mode()')
        else
          rhs()
        end
      end, { buffer = 0 })

      vim.b.in_visual_multi = true
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'visual_multi_exit',
    callback = function()
      vim.cmd [[
      silent! unmap <buffer> <leader>y
      silent! unmap <buffer> p
      silent! unmap <buffer> v
      ]]
      vim.b.in_visual_multi = false
    end,
  })

  vim.g.VM_custom_motions = {
    ['L'] = '$',
    ['H'] = '^',
  }

  -- blink.cmp 冲突
  vim.g.VM_maps = {
    ["I Down Arrow"] = "",
    ["I Return"] = "",
    ["I Up Arrow"] = "",
  }
end

return M
