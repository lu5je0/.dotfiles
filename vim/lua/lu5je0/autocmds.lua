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
    if vim.bo.filetype == 'gitcommit' then
      return
    end
    if vim.fn.line("'\"") > 0 and vim.fn.line("'\"") <= vim.fn.line("$") then
      vim.fn.setpos('.', vim.fn.getpos("'\""))
    end
    
    require('lu5je0.misc.time-machine').read_undo_if_is_time_machine_file()
  end
})

-- 0.13 起 vim.hl.on_yank 已废弃（0.14 移除），改用 vim.hl.hl_op。
local highlight_yank = vim.fn.has('nvim-0.13') == 1 and vim.hl.hl_op or vim.hl.on_yank

vim.api.nvim_create_autocmd('TextYankPost', {
  group = M.default_group,
  pattern = '*',
  callback = function()
    pcall(highlight_yank, { higroup = "Visual", timeout = 300 })
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

-- remove padding around Neovim instance 
-- vim.api.nvim_create_autocmd({ "UIEnter", "ColorScheme" }, {
--   callback = function()
--     local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
--     if not normal.bg then return end
--     io.write(string.format("\027]11;#%06x\027\\", normal.bg))
--   end,
-- })
--
-- vim.api.nvim_create_autocmd("UILeave", {
--   callback = function() io.write("\027]111\027\\") end,
-- })

return M
