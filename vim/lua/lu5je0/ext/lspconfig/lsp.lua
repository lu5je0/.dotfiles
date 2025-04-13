local M = {}

local function config_diagnostic()
  vim.diagnostic.config {
    virtual_text = false,
    underline = true,
    severity_sort = true,
    update_in_insert = true,
    signs = {
      text = {
        -- [vim.diagnostic.severity.ERROR] = '',
        -- [vim.diagnostic.severity.WARN] = '',
      },
      linehl = {
        -- [vim.diagnostic.severity.ERROR] = '',
      },
      numhl = {
        [vim.diagnostic.severity.ERROR] = 'DiagnosticSignError',
        [vim.diagnostic.severity.WARN] = 'DiagnosticSignWarn',
        [vim.diagnostic.severity.INFO] = 'DiagnosticSignInfo',
        [vim.diagnostic.severity.HINT] = 'DiagnosticSignHint',
      },
    },
  }
end

local function keymap(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lsp.lua' }

  -- keymap('n', 'gd', vim.lsp.buf.definition, opts)
  -- keymap('n', 'gn', vim.lsp.buf.implementation, opts)
  -- keymap('n', 'gb', vim.lsp.buf.references, opts)

  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  -- keymap('n', '<leader>cc', vim.lsp.buf.code_action, opts)
  -- keymap('v', '<leader>cc', vim.lsp.buf.code_action, opts)

  -- format
  -- keymap('n', '<leader>cf', vim.lsp.buf.formatting, opts)
  -- keymap('v', '<leader>cf', vim.lsp.buf.range_formatting, opts)

  vim.keymap.set("n", "<leader>ch", function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
  end, { desc = "LSP | Toggle Inlay Hints", silent = true })

  vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)

  -- keymap('n', 'gu', vim.lsp.buf.declaration, opts)
  -- keymap('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  vim.keymap.set('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  -- keymap('n', '<leader>cr', vim.lsp.buf.rename, opts)

  vim.keymap.set('n', '[e', function()
    vim.diagnostic.jump({ count = -1, float = true })
  end, opts)
  vim.keymap.set('n', ']e', function()
    vim.diagnostic.jump({ count = 1, float = true })
  end, opts)
  vim.keymap.set('n', '<leader>ce', vim.diagnostic.setloclist, opts)

  vim.keymap.set('n', '<leader><space>', function()
    vim.diagnostic.open_float { scope = 'line', opts }
  end)
end

function M.on_attach(client, bufnr)
  keymap(bufnr)
end

-- local function config_lsp(installed_server_names)
--   local lspconfig = require("lspconfig")
--
--   -- nvim-cmp
--   -- local capabilities = require('cmp_nvim_lsp').default_capabilities()
--   local capabilities = require('blink.cmp').get_lsp_capabilities()
--
--   -- -- nvim-ufo
--   -- capabilities.textDocument.foldingRange = {
--   --   dynamicRegistration = false,
--   --   lineFoldingOnly = true
--   -- }
--
--   for _, server_name in pairs(installed_server_names) do
--     local server = lspconfig[server_name]
--
--     local opts = {
--       capabilities = capabilities,
--       on_attach = M.on_attach,
--       -- autostart = false,
--     }
--
--     if server_name == 'lua_ls' then
--       local lua_ls_config = require('lu5je0.ext.lspconfig.lspservers.lua-ls-config')
--       opts.settings = lua_ls_config.settings
--       opts.on_attach = lua_ls_config.on_attach(opts.on_attach)
--     elseif server_name == 'pyright' then
--       local pyright_config = require('lu5je0.ext.lspconfig.lspservers.pyright-config')
--       opts.on_init = pyright_config.on_init
--       opts.settings = pyright_config.settings
--     elseif server_name == 'pylsp' then
--       opts.on_init = require('lu5je0.ext.lspconfig.lspservers.pylsp').on_init
--     elseif server_name == 'tsserver' then
--       opts.on_init = require('lu5je0.ext.lspconfig.lspservers.tsserver').on_init
--       opts.on_attach = require('lu5je0.ext.lspconfig.lspservers.tsserver').on_attach(opts.on_attach)
--     elseif server_name == 'jdtls' then
--       opts.on_init = require('lu5je0.ext.lspconfig.lspservers.jdtls').on_init
--     end
--
--     server.setup(opts)
--   end
-- end

function M.setup()
  local installed_server_names = { 'delance', 'lua_ls' }

  for _, lsp_name in ipairs(require('mason-lspconfig').get_installed_servers()) do
    table.insert(installed_server_names, lsp_name)
  end

  config_diagnostic()
  -- config_lsp(installed_server_names)

  vim.lsp.enable(installed_server_names)
end

return M
