local M = {}

-- 80ms左右
-- local STD_PATH = vim.fn.stdpath('config')
-- local DISABLE_IME = STD_PATH .. '/lib/toDisableIME.exe'
-- local ENABLE_IME = STD_PATH .. '/lib/toEnableIME.exe'

-- 这样比较快 40ms左右
local DISABLE_IME = '/mnt/d/bin/toDisableIME.exe'
local ENABLE_IME = '/mnt/d/bin/toEnableIME.exe'


function M.normal()
  vim.uv.new_thread(function(path)
    ---@diagnostic disable-next-line: missing-fields, missing-parameter
    local handle = vim.uv.spawn(path, {
      stdio = { nil, nil, nil }
    })
    if handle and not handle:is_closing() then handle:close() end
  end, DISABLE_IME)
end

-- 切换到 Insert 模式 (恢复之前记住的状态)
function M.insert()
    vim.uv.new_thread(function(path)
      ---@diagnostic disable-next-line: missing-fields, missing-parameter
      local handle = vim.uv.spawn(path, {
        stdio = { nil, nil, nil }
      })
      if handle and not handle:is_closing() then handle:close() end
    end, ENABLE_IME)
end

function M.setup()
  return M
end

return M
