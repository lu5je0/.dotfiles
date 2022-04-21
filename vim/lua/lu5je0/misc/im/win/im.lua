local M = {}

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
local path = vim.fn.stdpath('config')

local function disable_ime()
  io.popen(path .. '/lib/toDisableIME.exe'):close()
end

local function enable_ime()
  io.popen(path .. '/lib/toEnableIME.exe'):close()
end

local function create_autocmd()
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      disable_ime()
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      enable_ime()
    end
  })
end

local function defer_normal_keep()
  vim.defer_fn(function()
    if vim.api.nvim_get_mode().mode == 'n' then
      disable_ime()
    end
  end, 20)
end

M.boostrap = function()
  create_autocmd()
  defer_normal_keep()
end

return M
