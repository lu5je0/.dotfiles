local M = {}

M.servers = {
  "sumneko_lua", "pyright", "jsonls", "bashls", "vimls"
}

M.on_attach = function(client, bufnr)
  local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

  -- Show diagnostics in a pop-up window on hover
  _G.LspDiagnosticsPopupHandler = function()
    local current_cursor = vim.api.nvim_win_get_cursor(0)
    local last_popup_cursor = vim.w.lsp_diagnostics_last_cursor or {nil, nil}

    -- Show the popup diagnostics window,
    -- but only once for the current cursor location (unless moved afterwards).
    if not (current_cursor[1] == last_popup_cursor[1] and current_cursor[2] == last_popup_cursor[2]) then
      vim.w.lsp_diagnostics_last_cursor = current_cursor
      -- vim.diagnostic.open_float(0, {scope="cursor"})   -- for neovim 0.6.0+, replaces show_{line,position}_diagnostics
      vim.lsp.diagnostic.show_position_diagnostics({show_header = false})
    end
  end
  vim.cmd [[
  augroup LSPDiagnosticsOnHover
    autocmd!
    autocmd CursorHold * lua _G.LspDiagnosticsPopupHandler()
  augroup END
  ]]

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Mappings.
  local opts = { noremap=true, silent=true }

  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_set_keymap('n', 'gu', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
  buf_set_keymap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
  buf_set_keymap('n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
  buf_set_keymap('n', 'gn', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
  buf_set_keymap('i', '<c-p>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
  -- buf_set_keymap('n', '<leader>wa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
  -- buf_set_keymap('n', '<leader>wr', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
  -- buf_set_keymap('n', '<leader>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
  buf_set_keymap('n', 'gy', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
  buf_set_keymap('n', '<leader>cr', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
  buf_set_keymap('n', '<leader>cc', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
  buf_set_keymap('n', 'gb', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
  buf_set_keymap('n', '[d', '<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
  buf_set_keymap('n', ']d', '<cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
  buf_set_keymap('n', '<leader>ce', '<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
  buf_set_keymap('n', '<leader>cf', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)
  buf_set_keymap('n', '<leader><space>', '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
end

M.lua_setting = {
  Lua = {
    -- completion = {
    --   callSnippet = "Replace",
    -- },
    runtime = {
      -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
      version = "LuaJIT",
    },
    workspace = {
      maxPreload = 100000,
      preloadFileSize = 10000
    },
    diagnostics = {
      -- Get the language server to recognize the `vim` global
      globals = {"vim"},
    },
    telemetry = { enable = false }
  }
}

M.capabilities = (function ()
  -- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
  local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
  capabilities = require("cmp_nvim_lsp").update_capabilities(capabilities)
  -- log.info(capabilities)
  return capabilities
end)()

M.lsp_signature_config = function()
  require "lsp_signature".setup({
    floating_window = true, -- show hint in a floating window, set to false for virtual text only mode
    floating_window_above_cur_line = true, -- try to place the floating above the current line when possible Note:
    -- will set to true when fully tested, set to false will use whichever side has more space
    -- this setting will be helpful if you do not want the PUM and floating win overlap
    hint_enable = false, -- virtual hint enable
    timer_interval = 100000,
    handler_opts = {
      border = "single"   -- double, rounded, single, shadow, none
    },
    always_trigger = false,
    toggle_key = '<c-p>' -- toggle signature on and off in insert mode,  e.g. toggle_key = '<M-x>'
  })

  vim.cmd[[
  augroup clean_signature
  autocmd!
  autocmd BufEnter * silent! autocmd! Signature InsertEnter | silent! autocmd! Signature CursorHoldI
  augroup END
  ]]
end

M.lsp_installer_config = function()
  local installer = require("nvim-lsp-installer")

  for _, lang in pairs(M.servers) do
    local ok, server = installer.get_server(lang)
    if ok then
      if not server:is_installed() then
        print("Installing " .. lang)
        server:install()
      end
    end
  end

  -- Register a handler that will be called for all installed servers.
  installer.on_server_ready(function(server)
    local opts = {
      capabilities = M.capabilities,
      on_attach = M.on_attach
    }

    if server.name == "sumneko_lua" then
      opts.settings = M.lua_setting
      local luadev = require("lua-dev").setup({
        lspconfig = opts
      })
      server:setup(luadev)
    else
      server:setup(opts)
    end
  end)
end

M.lsp_diagnostic = function()
  -- diagnostic
  vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
      underline = true,
      virtual_text = false,
      signs = true,
      update_in_insert = true,
    }
  )
  local signs = { Error = " ", Warn = " ", Hint = " ", Info = " " }
  for type, icon in pairs(signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
  end
end

function M.setup()
  M.lsp_diagnostic()
  M.lsp_signature_config()
  M.lsp_installer_config()
end

return M
