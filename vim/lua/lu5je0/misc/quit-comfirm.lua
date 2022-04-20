local M = {}

local function exit_vim_pupop(msg)
  local Popup = require('nui.popup')
  local event = require('nui.utils.autocmd').event
  local content = msg
  local lines = string.split(content, '\n')

  local popup_options = {
    enter = true,
    border = {
      style = 'single',
      highlight = 'Fg',
      text = {
        -- top = 'Exiting',
        -- top_align = 'center',
      },
    },
    highlight = 'Normal:Normal',
    position = {
      row = '45%',
      col = '48%',
    },
    relative = 'editor',
    size = {
      width = 55,
      height = #lines,
    },
    opacity = 1,
    zindex = 100,
  }

  local popup = Popup(popup_options)

  popup:mount()

  vim.fn.win_execute(popup.winid, 'set ft=confirm')
  vim.api.nvim_buf_set_lines(0, 0, #lines, false, lines)
  vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup.bufnr, 'readonly', true)
  vim.fn.cursor { 99, 99 }

  -- unmount component when cursor leaves buffer
  popup:on(event.BufLeave, function()
    popup:unmount()
  end)

  popup:map('n', '<esc>', function()
    popup:unmount()
  end, { noremap = true })

  popup:map('n', 'q', function()
    popup:unmount()
  end, { noremap = true, nowait = true })

  popup:map('n', '<c-c>', function()
    popup:unmount()
  end, { noremap = true, nowait = true })

  popup:map('n', '<cr>', function()
    popup:unmount()
  end, { noremap = true, nowait = true })

  return popup
end

local function exit_vim_with_dialog()
  local unsave_buffers = {}

  for _, buffer in ipairs(vim.fn.getbufinfo { bufloaded = 1, buflisted = 1 }) do
    if buffer.changed == 1 then
      table.insert(unsave_buffers, buffer)
    end
  end

  local msg = nil
  if #unsave_buffers ~= 0 then
    msg = 'The change of the following buffers will be discarded.\n'
    for _, buffer in ipairs(unsave_buffers) do
      local file_icon = require('nvim-web-devicons').get_icon(buffer.name, vim.fn.getbufvar(buffer.bufnr, '&filetype'), { default = true })
      local filename = vim.fn.fnamemodify(buffer.name, ':t')
      if filename == '' then
        filename = '[No Name] '
      end
      local name = file_icon .. ' ' .. filename
      name = '  ' .. name
      msg = msg .. '\n' .. name
    end
    msg = msg .. '\n\n             [N]o, (Y)es, (S)ave ALl: '
  else
    msg = '                       Exit vim?'
    msg = msg .. '\n                     [N]o, (Y)es: '
  end

  local popup = exit_vim_pupop(msg)

  popup:map('n', 'n', function()
    popup:unmount()
  end, { noremap = true, nowait = true })

  popup:map('n', '<leader>Q', function() end, { noremap = true, nowait = true })

  popup:map('n', 'y', function()
    vim.cmd('qa!')
  end, { noremap = true, nowait = true })

  popup:map('n', 's', function()
    vim.cmd('wqa!')
  end, { noremap = true, nowait = true })
end

local function exit_vim_by_comfirm()
  local unsave_buffers = {}

  for _, buffer in ipairs(vim.fn.getbufinfo { bufloaded = 1, buflisted = 1 }) do
    if buffer.changed == 1 then
      table.insert(unsave_buffers, buffer)
    end
  end

  local msg = nil
  local options = '&No\n&Yes'

  if #unsave_buffers ~= 0 then
    msg = 'The change of the following buffers will be discarded.'
    for _, buffer in ipairs(unsave_buffers) do
      local name = require('nvim-web-devicons').get_icon(buffer.name, string.split(buffer.name, '.')[-1]) .. ' ' .. vim.fn.fnamemodify(buffer.name, ':t')
      if name == '' then
        name = '[No Name] ' .. buffer.bufnr
      end
      msg = msg .. '\n' .. name
    end

    options = options .. '\n&Save All'
  else
    msg = 'Exit vim?'
  end

  local confirm_value = vim.fn.confirm(msg, options)
  if confirm_value == 1 then
    return
  elseif confirm_value == 2 then
    vim.cmd('qa!')
  elseif confirm_value == 3 then
    vim.cmd('wqa!')
  end
end

M.exit = exit_vim_with_dialog

return M
