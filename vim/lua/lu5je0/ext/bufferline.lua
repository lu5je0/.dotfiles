local M = {}

local bl = require('bufferline')

local buffer_name_map = {}

bl.setup {
  options = {
    numbers = function(opts)
      return string.format('%s', opts.raise(opts.ordinal))
    end,
    hover = {
      enabled = true,
      delay = 100,
      reveal = {'close'}
    },
    style_preset = bl.style_preset.no_italic,
    offsets = {
      {
        filetype = 'dbui',
        text = 'DBUI',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'dapui_scopes',
        text = 'DEBUG',
        highlight = 'Directory',
        text_align = 'center',
      },
      {
        filetype = 'fern',
        text = 'Fern',
        highlight = 'NvimTreeNormal',
        text_align = 'center',
      },
      {
        filetype = 'neo-tree',
        text = 'NeoTree',
        highlight = 'Normal',
        text_align = 'center',
      },
      {
        filetype = 'NvimTree',
        text = 'NvimTree',
        highlight = 'NvimTreeNormal',
        text_align = 'center',
        separator = '█'
      },
      {
        filetype = 'Outline',
        text = 'Symbols',
        highlight = 'Red',
        text_align = 'center',
        separator = '█'
      },
      {
        filetype = 'vista',
        text = 'Vista',
        highlight = 'Directory',
        text_align = 'center',
      },
    },
    max_name_length = 12,
    tab_size = 15,
    -- custom_filter = function(buf_number, buf_numbers)
    --   if vim.bo[buf_number].filetype == 'fugitive' then
    --     return false
    --   end
    --   return true
    -- end,
    buffer_close_icon = '󰅖',
    name_formatter = function(buf)
      if buf.path and #buf.path > 0 then
        return nil
      end
      
      if buffer_name_map[buf.bufnr] ~= nil then
        return 'Untitled-' .. buffer_name_map[buf.bufnr]
      end
      local numbers = {}
      local valid_buffers = require("bufferline.utils").get_valid_buffers()
      for _, valid_bufnr in ipairs(valid_buffers) do
        if buffer_name_map[valid_bufnr] ~= nil and vim.api.nvim_buf_get_name(valid_bufnr) == '' then
          table.insert(numbers, buffer_name_map[valid_bufnr])
        end
      end
      table.sort(numbers)
      local function get_next_number()
        for i = 1, #numbers do
          if i == 1 and numbers[1] ~= 1 then
            return 1
          end
          if numbers[i + 1] == nil then
            return i + 1
          end
          if numbers[i + 1] - numbers[i] > 1 then
            return i + 1
          end
        end
        return 1
      end
      local target_num = get_next_number()
      buffer_name_map[buf.bufnr] = target_num
      return 'Untitled-' .. target_num
    end
  },
  highlights = {
    buffer_selected = {
      gui = "bold"
    },
    offset_separator = {
      fg = '#33353f',
      bg = 'None',
    },
    close_button_selected = {
      fg = '#6a7487',
      bg = 'None',
    },
  },
}

vim.cmd([[
nnoremap <silent><leader>0 <cmd>BufferLinePick<cr>
]])

for i = 1, 9, 1 do
  vim.keymap.set('n', '<leader>' .. i, function() bl.go_to_buffer(i, true) end)
end

vim.keymap.set('n', '<leader>to', function()
  vim.cmd [[
  BufferLineCloseLeft
  BufferLineCloseRight
  ]]
  vim.cmd('norm :<cr>')
end)

vim.keymap.set('n', '<leader>th', function()
  vim.cmd [[ BufferLineCloseLeft ]]
  vim.cmd('norm :<cr>')
end)

vim.keymap.set('n', '<leader>tl', function()
  vim.cmd [[ BufferLineCloseRight ]]
  vim.cmd('norm :<cr>')
end)

vim.api.nvim_create_user_command('BufferLinePickSplit', function(_)
  require('bufferline.pick').choose_then(function(bufnr)
    vim.cmd('vert sbuffer ' .. bufnr)
  end)
end, { force = true, nargs = '*', range = true })

return M
