vim.bo.shiftwidth = 2

-- 在内建 Lua ftplugin 前加载依赖，避免 FileType 重放。
require('lazy').load { plugins = { 'lazydev.nvim', 'nvim-colorizer.lua' } }

-- 首次加载时已进入 FileType，需主动挂载当前 buffer。
local colorizer = require('colorizer')
if not colorizer.is_buffer_attached(0) then
  colorizer.attach_to_buffer(0, nil, 'filetype')
end
