local M = {}

M.filetypes = {
  'json', 'python', 'java', 'bash', 'go', 'vim', 'lua', 'cpp', 'c',
  'rust', 'toml', 'yaml', 'markdown', 'http', 'typescript',
  'javascript', 'sql', 'html', 'json5', 'regex', 'vue',
  'css', 'dockerfile', 'vimdoc', 'query', 'xml', 'groovy', 'arthas', 'plantuml'
}

local function set_treesitter_highlights()
  vim.api.nvim_set_hl(0, '@constructor.lua', { fg = '#ABB2BF' })
end

M.setup_custom_parsers = function()
  ---@diagnostic disable: missing-fields
  vim.api.nvim_create_autocmd('User', { pattern = 'TSUpdate', callback = function()
    require('nvim-treesitter.parsers').arthas = {
      install_info = {
        path = vim.fn.stdpath('config') .. '/parsers/tree-sitter-arthas',
      },
      filetype = 'arthas',
    }
    require('nvim-treesitter.parsers').plantuml = {
      install_info = {
        path = vim.fn.stdpath('config') .. '/parsers/tree-sitter-plantuml',
      },
      filetype = 'plantuml',
    }
  end })
end

M.setup = function()
  M.setup_custom_parsers()

  require("nvim-treesitter").install(M.filetypes)
  require('lu5je0.ext.fold').setup()

  local function attach(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    if vim.bo[bufnr].buftype ~= '' then
      return
    end

    if not vim.tbl_contains(M.filetypes, vim.bo[bufnr].filetype) then
      return
    end

    local ok = pcall(vim.treesitter.start, bufnr)
    if not ok then
      return
    end

    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd('doautocmd <nomodeline> User TreesitterAttach')
    end)
    
    set_treesitter_highlights()
  end

  vim.api.nvim_create_autocmd('FileType', {
    pattern = M.filetypes,
    callback = function(args)
      attach(args.buf)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    attach(bufnr)
  end
end

return M
