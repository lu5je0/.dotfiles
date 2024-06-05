local M = {}

local installed_server_names = require('mason-lspconfig').get_installed_servers()

local lspconfig = require("lspconfig")

local function diagnostic()
  vim.diagnostic.config {
    virtual_text = false,
    underline = true,
    float = {
      source = 'always',
    },
    severity_sort = true,
    update_in_insert = true,
  }
  local signs = { Error = '  ', Warn = '  ', Hint = '  ', Info = '  ' }
  for type, icon in pairs(signs) do
    local hl = 'DiagnosticSign' .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
  end
  -- vim.cmd('highlight DiagnosticSignWarn guibg=NONE guifg=#9D806F')
end

function M.on_attach(client, bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lsp.lua' }
  local keymap = vim.keymap.set

  -- keymap('n', 'gd', vim.lsp.buf.definition, opts)
  -- keymap('n', 'gn', vim.lsp.buf.implementation, opts)
  -- keymap('n', 'gb', vim.lsp.buf.references, opts)
  
  keymap('n', 'K', vim.lsp.buf.hover, opts)
  -- keymap('n', '<leader>cc', vim.lsp.buf.code_action, opts)
  -- keymap('v', '<leader>cc', vim.lsp.buf.code_action, opts)
  
  -- format
  -- keymap('n', '<leader>cf', vim.lsp.buf.formatting, opts)
  -- keymap('v', '<leader>cf', vim.lsp.buf.range_formatting, opts)
  
  keymap("n", "<leader>ch", function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
  end, { desc = "LSP | Toggle Inlay Hints", silent = true })
  
  keymap('n', 'gy', vim.lsp.buf.type_definition, opts)

  keymap('n', 'gu', vim.lsp.buf.declaration, opts)
  -- keymap('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  keymap('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  keymap('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  keymap('n', '<leader>Wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  keymap('n', '<leader>cr', vim.lsp.buf.rename, opts)
  keymap('n', '[e', vim.diagnostic.goto_prev, opts)
  keymap('n', ']e', vim.diagnostic.goto_next, opts)
  keymap('n', '<leader>ce', vim.diagnostic.setloclist, opts)
  
  keymap('n', '<leader><space>', function()
    vim.diagnostic.open_float { scope = 'line', opts }
  end)
  
  if client.server_capabilities.documentSymbolProvider then
    local navic = require("nvim-navic")
    navic.attach(client, bufnr)
  end
  
  -- client.server_capabilities.semanticTokensProvider = nil
  -- vim.lsp.buf.inlay_hint(bufnr, true)
end

local function config()
  -- nvim-cmp
  local capabilities = require('cmp_nvim_lsp').default_capabilities()

  -- nvim-ufo
  capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true
  }

  for _, server_name in pairs(installed_server_names) do
    local server = lspconfig[server_name]

    local opts = {
      capabilities = capabilities,
      on_attach = M.on_attach,
    }

    if server_name == 'lua_ls' then
      local lua_ls_config = require('lu5je0.ext.lspconfig.lspservers.lua-ls-config')
      opts.settings = lua_ls_config.settings
      opts.on_attach = lua_ls_config.on_attach(opts.on_attach)
    elseif server_name == 'pyright' then
      local pyright_config = require('lu5je0.ext.lspconfig.lspservers.pyright-config')
      opts.on_init = pyright_config.on_init
      opts.settings = pyright_config.settings
    elseif server_name == 'pylsp' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.pylsp').on_init
    elseif server_name == 'jdtls' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.jdtls').on_init
    end

    server.setup(opts)
  end

  vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(
    vim.lsp.handlers.signature_help, {
    border = 'rounded',
    close_events = { 'InsertLeave' },
    focusable = false
  })
end

local function semantic_token_highlight()
  vim.cmd [[
    " hi! link @lsp.type.variable.lua RedItalic
    " hi! link @lsp.typemod.variable.defaultLibrary.lua CyanItalic
    " hi! link @lsp.mod.defaultLibrary.lua CyanItalic
  ]]
end

function M.setup()
  diagnostic()
  config()
  semantic_token_highlight()
  vim.defer_fn(function()
    vim.cmd("LspStart")
  end, 0)
end

return M
