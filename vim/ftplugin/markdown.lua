vim.g.markdown_folding = 0

-- 直接加载依赖，避免 lazy 的 FileType 重放重复初始化语法高亮。
require('lazy').load { plugins = { 'render-markdown', 'snacks.nvim' } }
