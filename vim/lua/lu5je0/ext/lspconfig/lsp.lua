local M = {}

require('nvim-lsp-installer').setup {
  ensure_installed = {}
}

local installed_server_names = (function()
  local r = {}
  for _, v in pairs(require('nvim-lsp-installer').get_installed_servers()) do
    table.insert(r, v.name)
  end
  return r;
end)()

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
  local signs = { Error = ' ', Warn = ' ', Hint = ' ', Info = ' ' }
  for type, icon in pairs(signs) do
    local hl = 'DiagnosticSign' .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
  end
end

local function on_attach(client, bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lsp.lua' }
  local keymap = vim.keymap.set

  -- ****
  -- lspsaga
  -- ****
  keymap('n', 'gd', '<cmd>Lspsaga lsp_finder<CR>', opts)
  -- Code action
  keymap('n', '<leader>cc', '<cmd>Lspsaga code_action<CR>', opts)
  keymap('v', '<leader>cc', '<cmd><C-U>Lspsaga range_code_action<CR>', opts)
  keymap('n', 'K', '<cmd>Lspsaga hover_doc<CR>', opts)

  -- ****
  -- basic
  -- ****
  -- keymap('n', 'gd', vim.lsp.buf.definition, opts)
  keymap('n', 'gy', vim.lsp.buf.type_definition, opts)
  keymap('n', 'gn', vim.lsp.buf.implementation, opts)
  keymap('n', 'gb', vim.lsp.buf.references, opts)

  keymap('n', 'gu', vim.lsp.buf.declaration, opts)
  -- keymap('n', 'K', vim.lsp.buf.hover, opts)
  keymap('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  keymap('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  keymap('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  keymap('n', '<leader>Wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  keymap('n', '<leader>cr', vim.lsp.buf.rename, opts)
  -- keymap('n', '<leader>cc', vim.lsp.buf.code_action, opts)
  -- keymap('v', '<leader>cc', vim.lsp.buf.code_action, opts)
  keymap('n', '[e', vim.diagnostic.goto_prev, opts)
  keymap('n', ']e', vim.diagnostic.goto_next, opts)
  keymap('n', '<leader>ce', vim.diagnostic.setloclist, opts)
  keymap('n', '<leader>cf', vim.lsp.buf.formatting, opts)
  keymap('v', '<leader>cf', vim.lsp.buf.range_formatting, opts)
  keymap('n', '<leader><space>', function()
    vim.diagnostic.open_float { scope = 'line', opts }
  end)

  -- illuminate
  require('illuminate').on_attach(client)

  -- nvim-ufo
  -- require('ufo').setup()

  vim.cmd [[
  " cursor word highlight
  highlight LspReferenceText guibg=none gui=none
  highlight LspReferenceWrite guibg=#344134 gui=none
  highlight LspReferenceRead guibg=#344134 gui=none
  ]]
end

local function config()
  local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())

  -- nvim-ufo
  capabilities.textDocument.foldingRange = {
    dynamicRegistration = false,
    lineFoldingOnly = true
  }

  for _, server_name in pairs(installed_server_names) do
    local server = lspconfig[server_name]

    local opts = {
      capabilities = capabilities,
      on_attach = on_attach,
    }

    if server_name == 'sumneko_lua' then
      local sumneko_lua_config = require('lu5je0.ext.lspconfig.lspservers.sumneke-lua-config')
      opts.settings = sumneko_lua_config.settings
      opts.on_attach = sumneko_lua_config.on_attach(opts.on_attach)
      opts = sumneko_lua_config.wrap_opts(opts)
    elseif server_name == 'pyright' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.pyright-config').on_init
    elseif server_name == 'tsserver' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.pyright-config').on_init
    elseif server_name == 'tsserver' then
      opts.on_init = require('lu5je0.ext.lspconfig.lspservers.pyright-config').on_init
      -- opts.root_dir = require('lu5je0.ext.lspconfig.lspservers.tsserver').root_dir(server.document_config.default_config.root_dir);
    elseif server_name == 'jdtls' then
      -- opts.on_init = require('lu5je0.ext.lspconfig.lspservers.pyright-config').on_init
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

function M.setup()
  diagnostic()
  config()
end

return M
