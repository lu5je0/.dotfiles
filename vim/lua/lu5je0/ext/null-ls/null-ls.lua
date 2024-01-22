local null_ls = require('null-ls')

null_ls.setup {
  -- debug = true,
  sources = {
    null_ls.builtins.formatting.autopep8.with {
      extra_args = { '--max-line-length', '120' }
    },
    -- null_ls.builtins.diagnostics.yamllint.with {
    --   extra_args = { '--no-warnings' }
    -- },
    null_ls.builtins.formatting.jq,
    -- null_ls.builtins.diagnostics.markdownlint,
    -- null_ls.builtins.code_actions.refactoring
    -- null_ls.builtins.diagnostics.eslint,
    -- null_ls.builtins.completion.spell,
  },
  ---@diagnostic disable-next-line: unused-local
  on_attach = require('lu5je0.ext.lspconfig.lsp').on_attach
}

-- local trailing_space = {
--   method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
--   -- method = null_ls.methods.DIAGNOSTICS,
--   filetypes = { 'vim', 'python', 'bash', 'c', 'java', 'sh', 'zsh', 'js', 'rs', 'jproperties', 'yaml', 'lua' },
--   generator = {
--     fn = function(params)
--       local diagnostics = {}
--       -- sources have access to a params object
--       -- containing info about the current file and editor state
--       for i, line in ipairs(params.content) do
--         if line:find('[^ ]') then
--           local col, end_col = line:find(' +$')
--           if col and end_col then
--             -- null-ls fills in undefined positions
--             -- and converts source diagnostics into the required format
--             table.insert(diagnostics, {
--               row = i,
--               col = col,
--               end_col = end_col + 1,
--               source = 'trailing_space',
--               message = 'trailing space',
--               severity = 4,
--             })
--           end
--         end
--       end
--       return diagnostics
--     end,
--   },
-- }
-- null_ls.register(trailing_space)

vim.api.nvim_create_user_command("NullLsToggle", function()
  require("null-ls").toggle({})
end, {})

vim.api.nvim_create_user_command("NullLsEnable", function()
  vim.notify('NullLsEnabled')
end, {})
