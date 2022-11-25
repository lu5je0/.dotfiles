return {
  on_attach = function(origin_on_attach_fn)
    return function(client, bufnr)
      origin_on_attach_fn(client, bufnr)
      -- client.server_capabilities.documentFormattingProvider
      -- client.server_capabilities.documentRangeFormattingProvider
    end
  end,
  settings = {
    Lua = {
      format = {
        enable = true,
        -- Put format options here
        -- NOTE: the value should be STRING!!
        defaultConfig = {
          indent_style = "space",
          indent_size = "2",
        }
      },
      completion = {
        callSnippet = 'Disable',
        postfix = '.',
        autoRequire = false,
      },
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = 'LuaJIT',
      },
      workspace = {
        maxPreload = 100000,
        preloadFileSize = 10000,
        checkThirdParty = false,
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = { 'vim' },
        neededFileStatus = {
          ['trailing-space'] = 'None'
        }
      },
      telemetry = { enable = false },
    },
  },
  wrap_opts = function(opts)
    return require('lua-dev').setup {
      lspconfig = opts,
    }
  end
}
