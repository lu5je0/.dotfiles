local utils = require('lu5je0.misc.timestamp.utils')

local M = {}
local timestamp_show_ns = vim.api.nvim_create_namespace('timestamp-show')
local timestamp_show_enabled = {}
local timestamp_show_augroup = vim.api.nvim_create_augroup('timestamp-show-refresh', { clear = false })
local timestamp_show_autocmd_registered = {}
local timestamp_show_hl = 'TimestampShowVirtText'

vim.api.nvim_set_hl(0, timestamp_show_hl, { fg = '#4B515E' })

local function render_timestamp_show_line(buf, row0)
  vim.api.nvim_buf_clear_namespace(buf, timestamp_show_ns, row0, row0 + 1)
  local line = vim.api.nvim_buf_get_lines(buf, row0, row0 + 1, false)[1]
  if not line then
    return 0
  end

  local mark_count = 0
  for _, num, end_idx_exclusive in line:gmatch('()(%d+)()') do
    local formatted = utils.format_timestamp_like(num)
    if formatted then
      vim.api.nvim_buf_set_extmark(buf, timestamp_show_ns, row0, end_idx_exclusive - 1, {
        virt_text = { { '(' .. formatted .. ')', timestamp_show_hl } },
        virt_text_pos = 'inline',
        priority = 80,
      })
      mark_count = mark_count + 1
    end
  end

  return mark_count
end

local function render_timestamp_show(buf)
  vim.api.nvim_buf_clear_namespace(buf, timestamp_show_ns, 0, -1)
  local mark_count = 0
  local line_count = vim.api.nvim_buf_line_count(buf)
  for row0 = 0, line_count - 1 do
    mark_count = mark_count + render_timestamp_show_line(buf, row0)
  end
  return mark_count
end

local function ensure_timestamp_show_autocmd(buf)
  if timestamp_show_autocmd_registered[buf] then
    return
  end

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = timestamp_show_augroup,
    buffer = buf,
    callback = function(args)
      if not timestamp_show_enabled[args.buf] then
        return
      end
      local row0 = vim.api.nvim_win_get_cursor(0)[1] - 1
      render_timestamp_show_line(args.buf, row0)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = timestamp_show_augroup,
    buffer = buf,
    once = true,
    callback = function(args)
      timestamp_show_enabled[args.buf] = nil
      timestamp_show_autocmd_registered[args.buf] = nil
    end,
  })

  timestamp_show_autocmd_registered[buf] = true
end

function M.toggle_timestamp_show()
  local buf = vim.api.nvim_get_current_buf()
  if timestamp_show_enabled[buf] then
    vim.api.nvim_buf_clear_namespace(buf, timestamp_show_ns, 0, -1)
    timestamp_show_enabled[buf] = nil
    vim.notify('TimestampShow: hidden')
    return
  end

  local mark_count = render_timestamp_show(buf)

  if mark_count == 0 then
    timestamp_show_enabled[buf] = nil
    vim.notify('TimestampShow: no timestamp-like value found', vim.log.levels.WARN)
    return
  end

  timestamp_show_enabled[buf] = true
  ensure_timestamp_show_autocmd(buf)
  vim.notify(string.format('TimestampShow: %d item(s)', mark_count))
end

return M
