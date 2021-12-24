local M = {}

function M.menu()
  local Menu = require('nui.menu')
  local event = require('nui.utils.autocmd').event

  local menu = Menu({
    relative = 'cursor',
    position = {
      row = 0,
      col = 0,
    },
    border = {
      highlight = 'MyHighlightGroup',
      style = 'single',
      text = {
        top = 'Choose Something',
        top_align = 'center',
      },
    },
    win_options = {
      -- winblend = 10,
      winhighlight = 'Normal:Normal',
    },
  }, {
    lines = {
      Menu.item('Item 1'),
      Menu.item('Item 2'),
    },
    max_width = 20,
    separator = {
      char = '-',
      text_align = 'right',
    },
    keymap = {
      focus_next = { 'j', '<Down>', '<Tab>' },
      focus_prev = { 'k', '<Up>', '<S-Tab>' },
      close = { '<Esc>', '<C-c>' },
      submit = { '<CR>', '<Space>' },
    },
    on_close = function()
      print('CLOSED')
    end,
    on_submit = function(item)
      print('SUBMITTED', vim.inspect(item))
    end,
  })

  menu:mount()
  menu:on(event.BufLeave, menu.menu_props.on_close, { once = true })
end

return M
