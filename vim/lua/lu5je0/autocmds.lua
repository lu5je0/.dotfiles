local M = {}

M.default_group = vim.api.nvim_create_augroup('l_main_autocmd_group', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    vim.cmd('set formatoptions-=o')
  end,
})

vim.api.nvim_create_autocmd({ 'VimEnter' }, {
  group = M.default_group,
  pattern = '*',
  callback = function(args)
    if args.file ~= "" and vim.fn.isdirectory(args.file) == 1 then
      vim.bo.swapfile = false
    end
  end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    if vim.fn.line("'\"") > 0 and vim.fn.line("'\"") <= vim.fn.line("$") then
      if vim.bo.filetype == 'gitcommit' then
        return
      end
      vim.fn.setpos('.', vim.fn.getpos("'\""))
    end
    
    require('lu5je0.misc.time-machine').read_undo_if_is_time_machine_file()
  end
})

vim.api.nvim_create_autocmd('TextYankPost', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    pcall(vim.highlight.on_yank, { higroup = "Visual", timeout = 300 })
  end
})

local update_select_mode = false
vim.api.nvim_create_autocmd('ModeChanged', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    local mode = vim.api.nvim_get_mode().mode
    -- telescope不变色
    if mode == 's' and vim.o.buftype ~= 'prompt' then
      if vim.fn.has('wsl') == 1 then
        vim.cmd('hi Visual guibg=#D1D3CB guifg=#242424')
      else
        vim.cmd('hi Visual guibg=#ead6ac guifg=#242424')
      end
      update_select_mode = true
    elseif mode == 'v' or mode == 'n' then
      if update_select_mode then
        vim.cmd('hi Visual guibg=#3b3e48 guifg=none')
        update_select_mode = false
      end
    end
  end,
})

vim.cmd [[
command -bar -nargs=? -complete=help Help execute HelpCurwin(<q-args>)
let s:did_open_help = v:false

function HelpCurwin(subject) abort
  let mods = 'silent noautocmd keepalt'
  if !s:did_open_help
    execute mods .. ' help'
    execute mods .. ' helpclose'
    let s:did_open_help = v:true
  endif
  if !empty(getcompletion(a:subject, 'help'))
    execute mods .. ' edit ' .. &helpfile
    set buftype=help
  endif
  return 'help ' .. a:subject
endfunction
]]


-- 进入 Visual 模式时设置 showcmd 为 true
vim.api.nvim_create_autocmd('ModeChanged', {
    group = M.default_group,
    pattern = '*:[vV\x16]*',  -- \x16 是 Ctrl-V 的十六进制表示
    callback = function()
        vim.opt.showcmd = true
    end,
})

-- 退出 Visual 模式时设置 showcmd 为 false
vim.api.nvim_create_autocmd('ModeChanged', {
    group = M.default_group,
    pattern = '[vV\x16]*:*',  -- \x16 是 Ctrl-V 的十六进制表示
    callback = function()
        vim.opt.showcmd = false
    end,
})

return M
