local group = vim.api.nvim_create_augroup('lspsaga', { clear = true })

local function init()
  require("lspsaga").init_lsp_saga({
    finder_action_keys = {
      open = "<cr>",
      quit = "<ESC>",
    },
    code_action_lightbulb = {
      enable = false,
    },
    code_action_keys = {
      quit = "<ESC>",
    },
  })
end

local function keymap(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lspsaga' }

  vim.keymap.set('n', 'gd', '<cmd>Lspsaga lsp_finder<CR>', opts)
  -- Code action
  vim.keymap.set('n', '<leader>cc', '<cmd>Lspsaga code_action<CR>', opts)
  vim.keymap.set('v', '<leader>cc', '<cmd><C-U>Lspsaga range_code_action<CR>', opts)
  vim.keymap.set('n', 'K', '<cmd>Lspsaga hover_doc<CR>', opts)
end

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(args)
    init()
    keymap(args.buf)
  end
})
