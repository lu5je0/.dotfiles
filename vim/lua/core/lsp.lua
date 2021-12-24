local M = {}

M.servers = { 'sumneko_lua', 'pyright', 'jsonls', 'bashls', 'vimls' }

local lua_setting = {
  Lua = {
    completion = {
      callSnippet = 'Disable',
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
  local function buf_set_keymap(...)
    vim.api.nvim_buf_set_keymap(bufnr, ...)
  end
  local function buf_set_option(...)
    vim.api.nvim_buf_set_option(bufnr, ...)
  end

  -- Show diagnostics in a pop-up window on hover
  _G.LspDiagnosticsPopupHandler = function()
    local current_cursor = vim.api.nvim_win_get_cursor(0)
    local last_popup_cursor = vim.w.lsp_diagnostics_last_cursor or { nil, nil }

    -- Show the popup diagnostics window,
    -- but only once for the current cursor location (unless moved afterwards).
    if not (current_cursor[1] == last_popup_cursor[1] and current_cursor[2] == last_popup_cursor[2]) then
      vim.w.lsp_diagnostics_last_cursor = current_cursor
      if vim.fn.has('nvim-0.6') == 1 then
        vim.diagnostic.open_float(0, { scope = 'cursor' }) -- for neovim 0.6.0+, replaces show_{line,position}_diagnostics
      else
        vim.lsp.diagnostic.show_position_diagnostics({ show_header = false })
      end
    end
  end
  vim.cmd([[
  augroup LSPDiagnosticsOnHover
    autocmd!
    autocmd CursorHold * lua _G.LspDiagnosticsPopupHandler()
  augroup END
  ]])

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Mappings.
  local opts = { noremap = true, silent = true }

  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_set_keymap('n', 'gu', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
  buf_set_keymap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
  buf_set_keymap('n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
  buf_set_keymap('n', 'gn', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
  buf_set_keymap('i', '<c-p>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
  buf_set_keymap('n', '<leader>Wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
  buf_set_keymap('n', '<leader>Wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
  buf_set_keymap('n', '<leader>Wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
  buf_set_keymap('n', 'gy', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
  buf_set_keymap('n', '<leader>cr', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
  buf_set_keymap('n', '<leader>cc', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
  buf_set_keymap('v', '<leader>cc', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
  buf_set_keymap('n', 'gb', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
  buf_set_keymap('n', '[e', '<cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
  buf_set_keymap('n', ']e', '<cmd>lua vim.diagnostic.goto_next()<CR>', opts)
  buf_set_keymap('n', '<leader>ce', '<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
  buf_set_keymap('n', '<leader>cf', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)
  buf_set_keymap('v', '<leader>cf', '<cmd>lua vim.lsp.buf.range_formatting()<CR>', opts)
  buf_set_keymap('n', '<leader><space>', "<cmd>lua vim.diagnostic.open_float({scope='line'})<CR>", opts)

  -- cursor word highlight
  require('illuminate').on_attach(client)
  vim.cmd([[
  highlight LspReferenceText guibg=none gui=none
  highlight LspReferenceWrite guibg=#344134 gui=none
  highlight LspReferenceRead guibg=#344134 gui=none
  ]])
end

local capabilities = (function()
  -- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
  local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
  capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)
  -- log.info(capabilities)
  return capabilities
end)()

local function lsp_signature_config()
  require('lsp_signature').setup({
    floating_window = true, -- show hint in a floating window, set to false for virtual text only mode
    floating_window_above_cur_line = true, -- try to place the floating above the current line when possible Note:
    -- will set to true when fully tested, set to false will use whichever side has more space
    -- this setting will be helpful if you do not want the PUM and floating win overlap
    hint_enable = false, -- virtual hint enable
    timer_interval = 100000,
    handler_opts = {
      border = 'single', -- double, rounded, single, shadow, none
    },
    always_trigger = false,
    toggle_key = '<c-p>', -- toggle signature on and off in insert mode,  e.g. toggle_key = '<M-x>'
  })

  vim.cmd([[
  imap <m-p> <c-p>
  augroup clean_signature
  autocmd!
  autocmd BufEnter * silent! autocmd! Signature InsertEnter | silent! autocmd! Signature CursorHoldI
  augroup END
  ]])
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
      local luadev = require('lua-dev').setup({
        lspconfig = opts,
      })
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
  vim.diagnostic.config({
    virtual_text = false,
    underline = true,
    float = {
      source = 'always',
    },
    severity_sort = true,
    update_in_insert = true,
  })
  local signs = { Error = ' ', Warn = ' ', Hint = ' ', Info = ' ' }
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
