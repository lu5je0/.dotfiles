local M = {}

local function get_outline_width()
  local tab = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tab)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "Outline" then
      return vim.api.nvim_win_get_width(win)
    end
  end
  return nil
end

local function remember_width()
  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(args)
      if vim.bo[args.buf].filetype ~= 'Outline' then
        return
      end
      require('outline.config').o.outline_window.width = get_outline_width()
    end
  })
end

local function keymap()
  vim.keymap.set('n', '<leader>s', function()
    vim.cmd('Outline!')
  end)

  vim.keymap.set('n', '<leader>fs', function()
    vim.cmd('OutlineOpen')
    -- vim.cmd('norm zz')
  end)
end

function M.setup()
  require('outline').setup {
    outline_window = {
      center_on_jump = true,
      width = 36,
    },
    symbols = {
      icons = {
        String = { icon = '󰰢', hl = 'String' },
        Number = { icon = '', hl = 'Number' },
      },
    },
  }
  keymap()
  remember_width()
end

return M
