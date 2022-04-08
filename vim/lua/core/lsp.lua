local M = {}

M.servers = { 'sumneko_lua', 'pyright', 'jsonls', 'bashls', 'vimls' }

local lua_setting = {
  Lua = {
    completion = {
      callSnippet = 'Disable',
      postfix = ".",
      autoRequire = false
    },
    runtime = {
      -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
      version = 'LuaJIT',
    },
    workspace = {
      maxPreload = 100000,
      preloadFileSize = 10000,
    },
    diagnostics = {
      -- Get the language server to recognize the `vim` global
      globals = { 'vim' },
    },
    telemetry = { enable = false },
  },
}

local pyright_setting = {
  on_init = function(client)
    local orig_rpc_request = client.rpc.request
    function client.rpc.request(method, params, handler, ...)
      local orig_handler = handler
      if method == 'textDocument/completion' then
        -- Idiotic take on <https://github.com/fannheyward/coc-pyright/blob/6a091180a076ec80b23d5fc46e4bc27d4e6b59fb/src/index.ts#L90-L107>.
        handler = function(...)
          local err, result = ...
          if not err and result then
            local items = result.items or result
            for _, item in ipairs(items) do
              if
                not (item.data and item.data.funcParensDisabled)
                and (
                  item.kind == vim.lsp.protocol.CompletionItemKind.Function
                  or item.kind == vim.lsp.protocol.CompletionItemKind.Method
                  or item.kind == vim.lsp.protocol.CompletionItemKind.Constructor
                )
              then
                item.insertText = item.label .. '$1'
                item.insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet
              end
            end
          end
          return orig_handler(...)
        end
      end
      return orig_rpc_request(method, params, handler, ...)
    end
  end,
}

local function on_attach(client, bufnr)
  -- Show diagnostics in a pop-up window on hover
  -- _G.LspDiagnosticsPopupHandler = function()
  --   local current_cursor = vim.api.nvim_win_get_cursor(0)
  --   local last_popup_cursor = vim.w.lsp_diagnostics_last_cursor or { nil, nil }
  --
  --   -- Show the popup diagnostics window,
  --   -- but only once for the current cursor location (unless moved afterwards).
  --   if not (current_cursor[1] == last_popup_cursor[1] and current_cursor[2] == last_popup_cursor[2]) then
  --     vim.w.lsp_diagnostics_last_cursor = current_cursor
  --     if vim.fn.has('nvim-0.6') == 1 then
  --       vim.diagnostic.open_float(0, { scope = 'cursor' }) -- for neovim 0.6.0+, replaces show_{line,position}_diagnostics
  --     else
  --       ---@diagnostic disable-next-line: deprecated
  --       vim.lsp.diagnostic.show_position_diagnostics({ show_header = false })
  --     end
  --   end
  -- end
  -- vim.cmd([[
  -- augroup LSPDiagnosticsOnHover
  --   autocmd!
  --   autocmd CursorHold * lua _G.LspDiagnosticsPopupHandler()
  -- augroup END
  -- ]])

  -- Mappings.
  local opts = { noremap = true, silent = true, buffer = bufnr }

  vim.keymap.set('n', 'gu', vim.lsp.buf.declaration, opts)
  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  vim.keymap.set('n', 'gn', vim.lsp.buf.implementation, opts)
  -- vim.keymap.set('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  vim.keymap.set('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wl', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, opts)
  vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)
  vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename, opts)
  vim.keymap.set('n', '<leader>cc', vim.lsp.buf.code_action, opts)
  vim.keymap.set('v', '<leader>cc', vim.lsp.buf.code_action, opts)
  vim.keymap.set('n', 'gb', vim.lsp.buf.references, opts)
  vim.keymap.set('n', '[e', vim.diagnostic.goto_prev, opts)
  vim.keymap.set('n', ']e', vim.diagnostic.goto_next, opts)
  vim.keymap.set('n', '<leader>ce', vim.diagnostic.setloclist, opts)
  vim.keymap.set('n', '<leader>cf', vim.lsp.buf.formatting, opts)
  vim.keymap.set('v', '<leader>cf', vim.lsp.buf.range_formatting, opts)
  vim.keymap.set('n', '<leader><space>', function() vim.diagnostic.open_float({scope='line', opts}) end)

  -- illuminate
  require('illuminate').on_attach(client)
  vim.keymap.set('i', '<c-p>', require('lsp_signature').on_InsertEnter, { silent = true })
  vim.cmd([[
  " cursor word highlight
  highlight LspReferenceText guibg=none gui=none
  highlight LspReferenceWrite guibg=#344134 gui=none
  highlight LspReferenceRead guibg=#344134 gui=none
  
  autocmd! Signature InsertEnter
  ]])

end

local capabilities = (function()
  return require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
end)()

local function lsp_signature_config()
  require('lsp_signature').setup {
    floating_window = true, -- show hint in a floating window, set to false for virtual text only mode
    floating_window_above_cur_line = true, -- try to place the floating above the current line when possible Note:
    -- will set to true when fully tested, set to false will use whichever side has more space
    -- this setting will be helpful if you do not want the PUM and floating win overlap
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
      opts.settings = lua_setting
      local luadev = require('lua-dev').setup {
        lspconfig = opts,
      }
      server:setup(luadev)
    elseif server.name == 'pyright' then
      opts.on_init = pyright_setting.on_init
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
