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

local function keymap(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lspsaga' }

  -- vim.keymap.set('n', 'gd', '<cmd>Lspsaga lsp_finder<CR>', opts)
  vim.keymap.set('n', 'gd', function()
    ---@diagnostic disable-next-line: missing-parameter
    local params = vim.lsp.util.make_position_params()
    vim.lsp.buf_request_all(0, 'textDocument/definition', params, function(results)
      -- print(dump(results))
      for _, res in pairs(results or {}) do
        if not res.result or #res.result == 0 then
          return
        else
          local location = res.result[1]
          local uri = nil
          local range = nil
          if location.uri then
            uri = location.uri
            range = location.range
          else
            uri = location.targetUri
            range = location.targetRange
          end
          uri = require('lu5je0.lang.string-util').url_decode(uri)
          local positon = { range.start.line + 1, range.start.character + 1 }
          local current_file_path = 'file://' .. vim.fn.expand('%:p:')

          if not uri == current_file_path or (vim.api.nvim_win_get_cursor(0)[1] - 1) ~= range.start.line then
            vim.cmd(('e +call\\ cursor(%d,%d) %s'):format(positon[1], positon[2], uri:gsub('^file://', '')))
          else
            vim.cmd('Lspsaga lsp_finder')
          end
        end
      end
    end)
  end, opts)
  
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
