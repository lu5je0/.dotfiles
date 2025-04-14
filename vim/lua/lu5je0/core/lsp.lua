local M = {}

local function config_diagnostic()
  vim.diagnostic.config {
    virtual_text = false,
    underline = true,
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
        [vim.diagnostic.severity.ERROR] = 'DiagnosticSignError',
        [vim.diagnostic.severity.WARN] = 'DiagnosticSignWarn',
        [vim.diagnostic.severity.INFO] = 'DiagnosticSignInfo',
        [vim.diagnostic.severity.HINT] = 'DiagnosticSignHint',
      },
    },
  }
end

local function keymap(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lsp.lua' }

  -- keymap('n', 'gd', vim.lsp.buf.definition, opts)
  -- keymap('n', 'gn', vim.lsp.buf.implementation, opts)
  -- keymap('n', 'gb', vim.lsp.buf.references, opts)

  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  -- keymap('n', '<leader>cc', vim.lsp.buf.code_action, opts)
  -- keymap('v', '<leader>cc', vim.lsp.buf.code_action, opts)

  -- format
  -- keymap('n', '<leader>cf', vim.lsp.buf.formatting, opts)
  -- keymap('v', '<leader>cf', vim.lsp.buf.range_formatting, opts)

  vim.keymap.set("n", "<leader>ch", function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
  end, { desc = "LSP | Toggle Inlay Hints", silent = true })

  vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, opts)

  -- keymap('n', 'gu', vim.lsp.buf.declaration, opts)
  -- keymap('i', '<c-p>', vim.lsp.buf.signature_help, opts)
  vim.keymap.set('n', '<leader>Wa', vim.lsp.buf.add_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wr', vim.lsp.buf.remove_workspace_folder, opts)
  vim.keymap.set('n', '<leader>Wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, opts)
  -- keymap('n', '<leader>cr', vim.lsp.buf.rename, opts)

  vim.keymap.set('n', '[e', function()
    vim.diagnostic.jump({ count = -1, float = true })
  end, opts)
  vim.keymap.set('n', ']e', function()
    vim.diagnostic.jump({ count = 1, float = true })
  end, opts)
  vim.keymap.set('n', '<leader>ce', vim.diagnostic.setloclist, opts)

  vim.keymap.set('n', '<leader><space>', function()
    vim.diagnostic.open_float { scope = 'line', opts }
  end)
end

local function on_attach(bufnr)
  keymap(bufnr)
end

function M.setup()
  local installed_server_names = { 'delance', 'lua_ls' }

  for _, lsp_name in ipairs(require('mason-lspconfig').get_installed_servers()) do
    table.insert(installed_server_names, lsp_name)
  end

  config_diagnostic()
  -- config_lsp(installed_server_names)
  
  vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(ctx)
      on_attach(ctx.buf)
    end
  })

  vim.lsp.enable(installed_server_names)
  
  -- 防止因 lazyload 导致 vim xxx.lua 时，lsp未启动
  vim.api.nvim_exec_autocmds('FileType', {
    group = 'nvim.lsp.enable'
  })
end

return M
