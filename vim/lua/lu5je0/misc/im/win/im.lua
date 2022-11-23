local M = {}

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
local path = vim.fn.stdpath('config')

M.disable_ime = function()
  io.popen(path .. '/lib/toDisableIME.exe 2>/dev/null'):close()
end

M.enable_ime = function()
  io.popen(path .. '/lib/toEnableIME.exe 2>/dev/null'):close()
end

local function create_autocmd()
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.disable_ime()
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.enable_ime()
    end
  })
end

M.setup = function()
  create_autocmd()
end

return M
