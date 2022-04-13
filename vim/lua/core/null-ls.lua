local null_ls = require('null-ls')

null_ls.setup {
  -- debug = true,
  sources = {
    require('null-ls').builtins.formatting.stylua.with {
      extra_args = { '--config-path', vim.fn.stdpath('config') .. '/stylua.toml' },
    },
    require('null-ls').builtins.formatting.autopep8,
    require('core.null-ls-extra.sql-formatter'),
    -- require("null-ls").builtins.code_actions.refactoring
    -- require("null-ls").builtins.diagnostics.eslint,
    -- require("null-ls").builtins.completion.spell,
  },
  on_attach = function(client)
    vim.keymap.set('n', '<leader>cf', _G.lsp_format_wrapper(vim.lsp.buf.formatting), { silent = true, buffer = true })
    vim.keymap.set('v', '<leader>cf', _G.lsp_format_wrapper(vim.lsp.buf.range_formatting), { silent = true, buffer = true })
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
