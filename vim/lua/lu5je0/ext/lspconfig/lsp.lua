local M = {}

local installed_server_names = require('mason-lspconfig').get_installed_servers()

local lspconfig = require("lspconfig")

local autostart_filetypes = {}

M.capabilities = nil

local function diagnostic()
  vim.diagnostic.config {
    virtual_text = false,
    underline = true,
    float = {
      source = 'always',
    },
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
        [vim.diagnostic.severity.HINT] = 'DiagnosticSignHint',
        [vim.diagnostic.severity.INFO] = 'DiagnosticSignInfo',
        [vim.diagnostic.severity.WARN] = 'DiagnosticSignWarn',
        [vim.diagnostic.severity.ERROR] = 'DiagnosticSignError',
      },
    },
  }
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

  -- keymap('n', 'gu', vim.lsp.buf.declaration, opts)
  -- keymap('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  keymap('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  keymap('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  keymap('n', '<leader>Wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  -- keymap('n', '<leader>cr', vim.lsp.buf.rename, opts)
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
  -- local capabilities = require('blink.cmp').get_lsp_capabilities()

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
      autostart = false,
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
    elseif server_name == 'tsserver' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.tsserver').on_init
      opts.on_attach = require('lu5je0.ext.lspconfig.lspservers.tsserver').on_attach(opts.on_attach)
    elseif server_name == 'jdtls' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.jdtls').on_init
    end
    
    for _, filetype in ipairs(server.document_config.default_config.filetypes) do
      table.insert(autostart_filetypes, filetype)
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

local function start_lsp()
  local bigfile = require('lu5je0.ext.big-file')
  if vim.tbl_contains(autostart_filetypes, vim.bo.filetype) then
    if not bigfile.is_big_file(vim.api.nvim_get_current_buf()) then
      vim.cmd('LspStart')
    end
  end
end

function M.setup()
  diagnostic()
  config()
  semantic_token_highlight()
  
  vim.defer_fn(function()
    start_lsp()
  end, 0)
  
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('lsp_autocmd_group', { clear = true }),
    pattern = autostart_filetypes,
    callback = function()
      start_lsp()
    end,
  })
end

return M
