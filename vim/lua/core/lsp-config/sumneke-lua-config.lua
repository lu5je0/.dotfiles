return {
  on_attach = function(origin_on_attach_fn)
    return function(client, bufnr)
      origin_on_attach_fn(client, bufnr)
      client.resolved_capabilities.document_formatting = false
      client.resolved_capabilities.document_range_formatting = false
    end
  end,
  settings = {
    Lua = {
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
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = { 'vim' },
      },
      telemetry = { enable = false },
    },
  },
}
