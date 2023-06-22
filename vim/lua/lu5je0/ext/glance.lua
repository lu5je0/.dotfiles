local M = {}

local glance = require('glance')

local function cursor_in_range(range)
  -- {
  --   ["end"] = {
  --     character = 18,
  --     line = 15
  --   },
  --   start = {
  --     character = 6,
  --     line = 15
  --   }
  -- }
  local cursor = vim.api.nvim_win_get_cursor(0)
  
  if cursor[1] >= (range.start.line + 1) and cursor[1] <= (range['end'].line + 1) then
    if cursor[2] >= (range.start.character) and cursor[2] <= (range['end'].character) then
      return true
    end
  end
end

local function keymap(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr, desc = 'lspsaga' }

  -- nnoremap gD <CMD>Glance definitions<CR>
  -- nnoremap gR <CMD>Glance references<CR>
  -- nnoremap gY <CMD>Glance type_definitions<CR>
  -- nnoremap gM <CMD>Glance implementations<CR>
  vim.keymap.set('n', 'gd', function()
    local win = vim.api.nvim_get_current_win()
    
    glance.open('definitions', {
      hooks = {
        before_open = function(results, open, jump, method)
          if #results == 1 then
            local range = results[1].range or results[1].targetSelectionRange
            local in_range = cursor_in_range(range)
            if win == vim.api.nvim_get_current_win() and not in_range then
              jump(results[1]) -- argument is optional
            end
            if in_range then
              glance.open('references')
            end
          else
            open(results) -- argument is optional
          end
        end,
      }
    })
  end, opts)
  vim.keymap.set('n', 'gb', '<cmd>Glance references<cr>', opts)
  vim.keymap.set('n', 'gn', '<cmd>Glance implementations<CR>', opts)

  -- Code action
  -- vim.keymap.set('n', '<leader>cc', '<cmd>Lspsaga code_action<CR>', opts)
  -- vim.keymap.set('v', '<leader>cc', '<cmd><C-U>Lspsaga range_code_action<CR>', opts)
  -- vim.keymap.set('n', 'K', '<cmd>Lspsaga hover_doc<CR>', opts)
end

function M.setup()
  require('glance').setup({
    detached = false,
    -- your configuration
  })
  
  
  local group = vim.api.nvim_create_augroup('glance', { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      keymap(args.buf)
    end
  })
end

return M
