local null_ls = require('null-ls')

-- null-ls 没有文件名 format
function _G.lsp_format_wrapper(fn)
  local function wrapper()
    local buf_name = vim.api.nvim_buf_get_name(0)

    local update_buf_name = false
    if vim.bo.filetype == 'sql' and vim.api.nvim_buf_get_name(0) == '' then
      vim.api.nvim_buf_set_name(0, 'tmp')
      update_buf_name = true
    end
    fn()

    if update_buf_name then
      vim.api.nvim_buf_set_name(0, buf_name)
    end
  end
  return wrapper
end


-- 避免null-ls在没有文件名的时候报错
local make_params = require('null-ls.utils').make_params
require('null-ls.utils').make_params = function(...)
  if vim.api.nvim_buf_get_name(0) == '' then
    select(1, ...).method = nil
  end
  return make_params(...)
end


null_ls.setup {
  -- debug = true,
  sources = {
    -- require('null-ls').builtins.formatting.stylua.with {
    --   extra_args = { '--config-path', vim.fn.stdpath('config') .. '/stylua.toml' },
    -- },
    require('null-ls').builtins.formatting.autopep8,
    require('lu5je0.ext.null-ls-extra.sql-formatter'),
    -- require("null-ls").builtins.code_actions.refactoring
    -- require("null-ls").builtins.diagnostics.eslint,
    -- require("null-ls").builtins.completion.spell,
  },
  ---@diagnostic disable-next-line: unused-local
  on_attach = function(client)
    local opts = { silent = true, buffer = true, desc = 'null-ls'}
    vim.keymap.set('n', '<leader>cf', _G.lsp_format_wrapper(vim.lsp.buf.formatting), opts)
    vim.keymap.set('v', '<leader>cf', _G.lsp_format_wrapper(vim.lsp.buf.range_formatting), opts)
  end,
}

local trailing_space = {
  method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
  -- method = null_ls.methods.DIAGNOSTICS,
  filetypes = { 'vim', 'python', 'bash', 'c', 'java', 'sh', 'zsh', 'js', 'rs', 'jproperties', 'yaml' },
  generator = {
    fn = function(params)
      local diagnostics = {}
      -- sources have access to a params object
      -- containing info about the current file and editor state
      for i, line in ipairs(params.content) do
        if line:find('[^ ]') then
          local col, end_col = line:find(' +$')
          if col and end_col then
            -- null-ls fills in undefined positions
            -- and converts source diagnostics into the required format
            table.insert(diagnostics, {
              row = i,
              col = col,
              end_col = end_col + 1,
              source = 'trailing_space',
              message = 'trailing space',
              severity = 4,
            })
          end
        end
      end
      return diagnostics
    end,
  },
}

null_ls.register(trailing_space)
