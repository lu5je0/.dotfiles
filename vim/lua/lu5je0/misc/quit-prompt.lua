local M = {}

local devicons = require('nvim-web-devicons')

local function exit_vim_pupop(msg)
  local Popup = require('nui.popup')
  local event = require('nui.utils.autocmd').event

  local width = 55
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
      width = width,
      height = 2 + #msg.text,
    },
    opacity = 1,
    zindex = 100,
  }

  local popup = Popup(popup_options)

  popup:mount()

  vim.fn.win_execute(popup.winid, 'set ft=confirm')

  local function text_align_center(text)
    text = string.rep(' ', math.floor((width - #text) / 2)) .. text
    return text
  end

  local function get_extension(filename)
    return filename:match(".+%.(%w+)$")
  end

  vim.api.nvim_buf_set_lines(0, 0, 1, false, { text_align_center(msg.title) })

  local title_group
  if #msg.text == 0 then
    title_group = 'Green'
  else
    title_group = 'Red'
  end

  vim.api.nvim_buf_add_highlight(0, -1, title_group, 0, 0, -1)
  for i, filename in ipairs(msg.text) do
    local icon, hi_group = devicons.get_icon(filename, get_extension(filename), {})
    vim.api.nvim_buf_set_lines(0, i, i + 1, false, { ' ' .. icon .. ' ' .. filename })
    vim.api.nvim_buf_add_highlight(0, -1, hi_group, i, 1, 5)
  end
  vim.api.nvim_buf_set_lines(0, #msg.text + 1, #msg.text + 2, false, { text_align_center(msg.choice) })

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

  local content = { title = '', choice = '', text = {} }
  if #unsave_buffers ~= 0 then
    content.title = 'The change of the following buffers will be discarded.'

    for _, buffer in ipairs(unsave_buffers) do
      local filename = vim.fn.fnamemodify(buffer.name, ':t')
      if filename == '' then
        filename = '[No Name] '
      end
      table.insert(content.text, filename)
    end

    content.choice = '[N]o, (Y)es, (S)ave ALl'
  else
    content.title = 'Exit vim?'
    content.choice = '[N]o, (Y)es: '
  end

  local popup = exit_vim_pupop(content)

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
