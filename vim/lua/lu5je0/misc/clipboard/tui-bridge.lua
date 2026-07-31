local M = {}

local augroup = vim.api.nvim_create_augroup('deferClip', {})
local active_entry = {}

local clipboard = require('lu5je0.misc.tui-bridge.ext.clipboard').setup()

-- nvim 内是否有尚未写入系统剪切板的 yank。
-- 只有此标记为 true 时才允许把缓存回写系统剪切板，
-- 否则失焦时会把系统剪切板里更新的内容（如截图图片）覆盖掉。
local pending_copy = false
local input_timer = vim.uv.new_timer()

local function delay_input(text)
  input_timer:stop()
  input_timer:start(500, 0, vim.schedule_wrap(function()
    pending_copy = false
    clipboard.input(text)
  end))
end

local function flush_pending_copy()
  if pending_copy and active_entry and active_entry.lines then
    input_timer:stop()
    pending_copy = false
    clipboard.input(table.concat(active_entry.lines, '\n'))
  end
end

local function apply_synced_text(text, init)
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

local function sync_from(init)
  apply_synced_text(clipboard.output({ eol = 'lf' }), init)
end

local function sync_from_async(init)
  clipboard.output_async({ eol = 'lf' }, function(text)
    apply_synced_text(text, init)
  end)
end

function M.copy(lines, regtype)
  pending_copy = true
  delay_input(table.concat(lines, '\n'))
  active_entry = { lines = lines, regtype = regtype }
end

function M.get_active()
  -- 首次 paste 且异步 initial sync 还没回来时，缓存为空会返回 nil 触发 E353，
  -- 这里按需做一次同步读补上，避免和启动异步同步抢跑。
  if active_entry.lines == nil then
    sync_from()
  end
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

  vim.api.nvim_create_autocmd({ 'VimLeavePre' }, {
    group = augroup,
    callback = flush_pending_copy,
  })
  sync_from_async(true)

  vim.keymap.set('i', '<c-v>', function()
    sync_from(true)
    require('lu5je0.core.keys').feedkey('<c-r>+')
  end)
end

return M
