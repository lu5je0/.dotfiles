local M = {}

local augroup = vim.api.nvim_create_augroup('deferClip', {})
local active_entry = {}

local clipboard = require('lu5je0.misc.tui-bridge.ext.clipboard').setup()

local function sync_from(init)
  local text = clipboard.output({ eol = 'lf' })
  if not text then
    return
  end

  local data = vim.split(text, '\n', { plain = true })
  -- 避免切换窗口后regtype丢失
  if active_entry ~= nil and #data < 100 and text == vim.fn.getreg('"') then
    if init then
      -- 第一次进入neovim时，"有值直接返回
      active_entry = { lines = vim.split(vim.fn.getreg('"'), '\n'), regtype = vim.fn.getregtype('"') }
    end
    return
  end
  active_entry = { lines = data, regtype = 'v' }
end

function M.copy(lines, regtype)
  clipboard.input(table.concat(lines, '\n'))
  active_entry = { lines = lines, regtype = regtype }
end

function M.get_active()
  return { active_entry.lines, active_entry.regtype }
end

function M.setup()
  vim.o.clipboard = 'unnamed'

  local set_fn = function(lines, regtype)
    M.copy(lines, regtype)
  end

  local get_fn = function()
    return M.get_active()
  end

  vim.g.clipboard = {
    name = 'wsl-clipboard',
    copy = {
      ['+'] = set_fn,
      ['*'] = set_fn,
    },
    paste = {
      ['+'] = get_fn,
      ['*'] = get_fn,
    },
  }

  vim.api.nvim_create_autocmd({ 'FocusGained' }, {
    group = augroup,
    callback = sync_from,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      if active_entry and active_entry.lines then
        local bridge = require('lu5je0.misc.tui-bridge.tui-bridge').singleton()
        bridge.call('clipboard', 'input', { text = table.concat(active_entry.lines, '\n') }, { wait_response = true })
      end
    end,
  })
  sync_from(true)
  
  vim.keymap.set('i', '<c-v>', function()
    sync_from(true)
    require('lu5je0.core.keys').feedkey('<c-r>+')
  end)
end

return M
