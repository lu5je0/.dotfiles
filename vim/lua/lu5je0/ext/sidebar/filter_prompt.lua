local config = require('lu5je0.ext.sidebar.config')
local lifecycle = require('lu5je0.ext.sidebar.lifecycle')
local source_base = require('lu5je0.ext.sidebar.source_base')
local view = require('lu5je0.ext.sidebar.view')

local M = {}
local prefix = '[FILTER]: '

function M.header(source, query)
  if not source.filter_prompt and not query then
    return
  end
  if source.filter_prompt then
    query = nil
  end
  local line = query and (prefix .. '/' .. query .. '/') or prefix
  local header = {
    lines = { line },
    items = { { type = 'filter', line_idx = 0 } },
    highlights = {
      { line = 0, line_hl_group = 'SidebarLiveFilterBackground' },
      { line = 0, hl = 'SidebarLiveFilterPrefix', col_start = 0, col_end = #prefix },
    },
  }
  if query then
    header.highlights[3] = { line = 0, hl = 'SidebarLiveFilterValue', col_start = #prefix, col_end = #line }
  end
  return header
end

local function redraw_header(prompt)
  local first = prompt.source.display_items[1]
  local last = first and first.type == 'filter' and 1 or 0
  source_base.render(prompt.spec, { header_only = true }, 0, last)
end

function M.close(source, window_closed)
  local prompt = source.filter_prompt
  if not prompt then
    return
  end
  source.filter_prompt = nil
  if prompt.job then
    pcall(prompt.job.kill, prompt.job)
  end
  if window_closed then
    vim.schedule(function()
      if lifecycle.is_current(prompt.ctx) and not source.filter_prompt then
        redraw_header(prompt)
      end
    end)
  elseif prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
    vim.api.nvim_win_close(prompt.win, true)
  end
end

function M.on_window_closed(ts, win)
  local source = ts[config.tabs[ts.active_tab_idx].id]
  if source.filter_prompt and source.filter_prompt.win == win then
    M.close(source, true)
  end
end

function M.open(ctx, spec, query, apply, configure)
  if not lifecycle.is_current(ctx) then
    return
  end
  local source = ctx.state[spec.state_key or spec.id]
  M.close(source)
  local prompt = { ctx = ctx, source = source, spec = spec }
  source.filter_prompt = prompt
  redraw_header(prompt)

  local parent = ctx.state.win
  vim.api.nvim_win_call(parent, function()
    vim.fn.winrestview { lnum = 1, topline = 1, col = 0, leftcol = 0 }
  end)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'prompt'
  vim.bo[buf].bufhidden = 'wipe'
  vim.b[buf].completion = false
  vim.fn.prompt_setprompt(buf, '')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query or '' })
  vim.api.nvim_buf_set_extmark(buf, view.ns_id(), 0, 0, { line_hl_group = 'SidebarLiveFilterValue' })

  local info = vim.fn.getwininfo(parent)[1]
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'win',
    win = parent,
    bufpos = { 0, #prefix },
    row = 0,
    col = 0,
    width = math.max(1, info.width - info.textoff - #prefix),
    height = 1,
    style = 'minimal',
    border = 'none',
  })
  prompt.win = win
  vim.w[win].statusline_parent = parent

  local function finish(input)
    if source.filter_prompt ~= prompt then
      return
    end
    vim.cmd.stopinsert()
    M.close(source)
    if lifecycle.is_current(ctx) and not (input and apply(input)) then
      redraw_header(prompt)
    end
  end

  local opts = { buffer = buf, nowait = true }
  local function cancel()
    finish()
  end
  vim.keymap.set({ 'n', 'i' }, '<Esc>', cancel, opts)
  vim.keymap.set('n', '<CR>', function()
    finish(vim.api.nvim_get_current_line())
  end, opts)
  vim.fn.prompt_setcallback(buf, finish)
  vim.fn.prompt_setinterrupt(buf, cancel)
  if configure then
    configure(prompt, buf)
  end
  vim.cmd.startinsert { bang = true }
end

return M
