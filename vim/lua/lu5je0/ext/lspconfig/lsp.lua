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

  if require('lu5je0.core.plugin-loader').is_loaded('telescope.nvim') then
    require('lu5je0.ext.telescope').lsp_keymaping(bufnr)
  else
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', 'gn', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', 'gb', vim.lsp.buf.references, opts)
  end

  vim.keymap.set('n', 'gu', vim.lsp.buf.declaration, opts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  vim.keymap.set('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  vim.keymap.set('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename, opts)
  vim.keymap.set('n', '<leader>cc', vim.lsp.buf.code_action, opts)
  vim.keymap.set('v', '<leader>cc', vim.lsp.buf.code_action, opts)
  vim.keymap.set('n', '[e', vim.diagnostic.goto_prev, opts)
  vim.keymap.set('n', ']e', vim.diagnostic.goto_next, opts)
  vim.keymap.set('n', '<leader>ce', vim.diagnostic.setloclist, opts)
  vim.keymap.set('n', '<leader>cf', vim.lsp.buf.formatting, opts)
  vim.keymap.set('v', '<leader>cf', vim.lsp.buf.range_formatting, opts)
  vim.keymap.set('n', '<leader><space>', function()
    vim.diagnostic.open_float { scope = 'line', opts }
  end)

  -- illuminate
  require('illuminate').on_attach(client)
  vim.cmd [[
  " cursor word highlight
  highlight LspReferenceText guibg=none gui=none
  highlight LspReferenceWrite guibg=#344134 gui=none
  highlight LspReferenceRead guibg=#344134 gui=none
  ]]
end

local function config()
  local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())

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
