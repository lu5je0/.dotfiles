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
    preview_lines_above = 2,
  })
end

local function find_definition()
  --- @diagnostic disable-next-line: missing-parameter
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request_all(0, 'textDocument/definition', params, function(results)
    for _, res in pairs(results or {}) do
      if not res.result or #res.result == 0 then
        return
      else
        local location = res.result[1]
        local uri = location.uri or location.targetUri
        local range = location.range or location.targetRange
        
        local same_file = vim.uri_to_fname(uri) == vim.fn.expand('%:p:')
        local same_line = (vim.api.nvim_win_get_cursor(0)[1] - 1) == range.start.line

        if not same_file or not same_line then
          require('vim.lsp.util').jump_to_location(location, 'utf-8', true)
        else
          vim.cmd('Lspsaga lsp_finder')
        end
      end
    end
  end)
end

local function keymap(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lspsaga' }

  vim.keymap.set('n', 'gd', find_definition, opts)
  vim.keymap.set('n', 'gb', '<cmd>Lspsaga lsp_finder<CR>', opts)

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
