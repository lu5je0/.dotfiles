local M = {}

M.servers = { 'sumneko_lua', 'pyright', 'jsonls', 'bashls', 'vimls' }

local function on_attach(client, bufnr)
  -- Mappings.
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lsp.lua' }

  if packer_plugins and packer_plugins['telescope.nvim'] and packer_plugins['telescope.nvim'].loaded then
    require('lu5je0.ext.telescope').lsp_keymaping(bufnr)
  else
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', 'gn', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', 'gb', vim.lsp.buf.references, opts)
  end

  vim.keymap.set('n', 'gu', vim.lsp.buf.declaration, opts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  -- vim.keymap.set('i', '<c-p>', vim.lsp.buf.signature_help, opts)
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

  -- lsp_signature
  vim.keymap.set('i', '<c-p>', require('lsp_signature').on_InsertEnter, { silent = true })
  vim.cmd('autocmd! Signature InsertEnter')
end

local capabilities = (function()
  return require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
end)()

local function lsp_signature_config()
  require('lsp_signature').setup {
    floating_window = true, -- show hint in a floating window, set to false for virtual text only mode
    floating_window_above_cur_line = true,
    check_completion_visible = true,
    hint_enable = false, -- virtual hint enable
    timer_interval = 200,
    handler_opts = {
      border = 'single', -- double, rounded, single, shadow, none
    },
    always_trigger = true,
    toggle_key = nil, -- toggle signature on and off in insert mode,  e.g. toggle_key = '<M-x>'
  }
end

local function lsp_installer_config()
  local installer = require('nvim-lsp-installer')

  for _, lang in pairs(M.servers) do
    local ok, server = installer.get_server(lang)
    if ok then
      if not server:is_installed() then
        print('Installing ' .. lang)
        server:install()
      end
    end
  end

  -- Register a handler that will be called for all installed servers.
  installer.on_server_ready(function(server)
    local opts = {
      capabilities = capabilities,
      on_attach = on_attach,
    }

    if server.name == 'sumneko_lua' then
      local sumneko_lua_config = require('lu5je0.ext.lsp-config.sumneke-lua-config')
      opts.settings = sumneko_lua_config.settings
      opts.on_attach = sumneko_lua_config.on_attach(opts.on_attach)
      opts = sumneko_lua_config.wrap_opts(opts)
      server:setup(opts)
    elseif server.name == 'pyright' then
      opts.on_init = require('lu5je0.ext.lsp-config.pyright-config').on_init
      server:setup(opts)
    else
      server:setup(opts)
    end
  end)
end

local function lsp_diagnostic()
  -- diagnostic
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

function M.setup()
  lsp_diagnostic()
  lsp_signature_config()
  lsp_installer_config()
end

return M
