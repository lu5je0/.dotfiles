local lifecycle = require('lu5je0.ext.sidebar.lifecycle')
local model = require('lu5je0.ext.sidebar.sources.history.model')

local M = {}
local prefix = '[FILTER]: '

function M.header(query)
  local line = prefix .. '/' .. query .. '/'
  return {
    lines = { line },
    items = { { type = 'filter', line_idx = 0 } },
    highlights = {
      { line = 0, hl = 'SidebarLiveFilterPrefix', col_start = 0, col_end = #prefix },
      { line = 0, hl = 'SidebarLiveFilterValue', col_start = #prefix, col_end = #line },
    },
  }
end

function M.close(h, window_closed)
  local prompt = h.author_prompt
  if not prompt then
    return
  end
  h.author_prompt = nil
  if prompt.job then
    pcall(prompt.job.kill, prompt.job)
  end
  if not window_closed and prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
    vim.api.nvim_win_close(prompt.win, true)
  end
  if window_closed and not h.author_filter then
    vim.schedule(function()
      if lifecycle.is_current(prompt.ctx) and not h.author_prompt then
        prompt.redraw()
      end
    end)
  end
end

function M.open(redraw, apply)
  local ctx = lifecycle.capture()
  local ts = ctx.state
  local h = ts.history
  if not h.repo_root or not lifecycle.is_current(ctx) then
    return
  end
  M.close(h)
  local prompt = { ctx = ctx, redraw = redraw }
  h.author_prompt = prompt
  if not h.author_filter then
    redraw()
  end
  vim.api.nvim_win_call(ts.win, function()
    vim.fn.winrestview { lnum = 1, topline = 1, col = 0, leftcol = 0 }
  end)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'prompt'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].completeopt = 'menu,menuone'
  vim.b[buf].completion = false
  vim.fn.prompt_setprompt(buf, '')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { h.author_filter or '' })

  local info = vim.fn.getwininfo(ts.win)[1]
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'win',
    win = ts.win,
    bufpos = { 0, #prefix },
    row = 0,
    col = 0,
    width = math.max(1, info.width - info.textoff - #prefix),
    height = 1,
    style = 'minimal',
    border = 'none',
  })
  vim.w[win].statusline_parent = ts.win
  vim.wo[win].winhighlight = 'NormalFloat:SidebarLiveFilterValue'
  prompt.win = win
  local candidates = {}
  prompt.job = model.load_authors(h.repo_root, function(entries)
    if lifecycle.is_current(ctx) and h.author_prompt == prompt then
      candidates = entries
      prompt.job = nil
    end
  end)

  local function finish(query)
    if h.author_prompt ~= prompt then
      return
    end
    vim.cmd.stopinsert()
    M.close(h)
    if lifecycle.is_current(ctx) then
      local changed = query and apply(vim.trim(query:gsub('[%z\r\n]', ' ')))
      if not changed and not h.author_filter then
        redraw()
      end
    end
  end

  local opts = { buffer = buf, nowait = true }
  vim.keymap.set({ 'n', 'i' }, '<Esc>', function()
    finish()
  end, opts)
  vim.keymap.set('n', '<CR>', function()
    finish(vim.api.nvim_get_current_line())
  end, opts)
  vim.keymap.set('i', '<CR>', function()
    return vim.fn.pumvisible() == 1 and '<C-y><CR>' or '<CR>'
  end, { buffer = buf, expr = true })
  vim.keymap.set('i', '<Tab>', function()
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.keycode('<C-n>'), 'in', false)
      return
    end
    local column = vim.api.nvim_win_get_cursor(win)[2]
    local typed = vim.fn.tolower(vim.api.nvim_get_current_line():sub(1, column))
    local matches = vim.tbl_filter(function(candidate)
      return vim.startswith(vim.fn.tolower(candidate.word), typed)
    end, candidates)
    if #matches > 0 then
      vim.fn.complete(1, matches)
    end
  end, opts)
  vim.fn.prompt_setcallback(buf, finish)
  vim.fn.prompt_setinterrupt(buf, function()
    finish()
  end)
  vim.cmd.startinsert { bang = true }
end

return M
