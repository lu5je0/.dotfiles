local M = {}

local function get_state(bufnr)
  local core = require('lu5je0.ext.diff-base.core')
  return core.state[bufnr]
end

local function reference_lines(s)
  return s.staged or s.base
end

local function find_hunk_at(hunks, lnum)
  for _, h in ipairs(hunks) do
    if h.type == 'delete' then
      if lnum == h.new_start or lnum == h.new_start + 1 then return h end
    else
      local s = h.new_start
      local e = h.new_start + h.new_count - 1
      if lnum >= s and lnum <= e then return h end
    end
  end
  return nil
end

local function get_old_lines(reference, hunk)
  local lines = {}
  for i = hunk.old_start, hunk.old_start + hunk.old_count - 1 do
    lines[#lines + 1] = reference[i] or ''
  end
  return lines
end

local function get_new_lines(bufnr, hunk)
  if hunk.new_count == 0 then return {} end
  return vim.api.nvim_buf_get_lines(bufnr, hunk.new_start - 1, hunk.new_start - 1 + hunk.new_count, false)
end

local function lines_equal(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- Apply a hunk-shaped replacement to a reference array, substituting the
-- region [old_start, old_start+old_count) with `replacement`.
local function splice(reference, hunk, replacement)
  local out = {}
  if hunk.old_count == 0 then
    for i = 1, hunk.old_start do out[#out + 1] = reference[i] end
    for _, l in ipairs(replacement) do out[#out + 1] = l end
    for i = hunk.old_start + 1, #reference do out[#out + 1] = reference[i] end
  else
    for i = 1, hunk.old_start - 1 do out[#out + 1] = reference[i] end
    for _, l in ipairs(replacement) do out[#out + 1] = l end
    for i = hunk.old_start + hunk.old_count, #reference do out[#out + 1] = reference[i] end
  end
  return out
end

function M.next_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s or #s.hunks == 0 then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  for _, h in ipairs(s.hunks) do
    local target = h.type == 'delete' and (h.new_start == 0 and 1 or h.new_start) or h.new_start
    if target > lnum then
      vim.api.nvim_win_set_cursor(0, { math.max(1, target), 0 })
      return
    end
  end
  local h = s.hunks[1]
  local target = h.type == 'delete' and (h.new_start == 0 and 1 or h.new_start) or h.new_start
  vim.api.nvim_win_set_cursor(0, { math.max(1, target), 0 })
end

function M.prev_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s or #s.hunks == 0 then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  for i = #s.hunks, 1, -1 do
    local h = s.hunks[i]
    local target = h.type == 'delete' and (h.new_start == 0 and 1 or h.new_start) or h.new_start
    if target < lnum then
      vim.api.nvim_win_set_cursor(0, { math.max(1, target), 0 })
      return
    end
  end
  local h = s.hunks[#s.hunks]
  local target = h.type == 'delete' and (h.new_start == 0 and 1 or h.new_start) or h.new_start
  vim.api.nvim_win_set_cursor(0, { math.max(1, target), 0 })
end

function M.preview_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk_at(s.hunks, lnum)
  if not hunk then
    vim.notify('No hunk at cursor', vim.log.levels.INFO)
    return
  end
  local old_lines = get_old_lines(reference_lines(s), hunk)
  local new_lines = get_new_lines(bufnr, hunk)
  local content = {}
  for _, l in ipairs(old_lines) do content[#content + 1] = '- ' .. l end
  for _, l in ipairs(new_lines) do content[#content + 1] = '+ ' .. l end
  if #content == 0 then content = { '(empty)' } end

  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, content)
  vim.bo[pbuf].filetype = 'diff'
  vim.bo[pbuf].modifiable = false
  local width = 0
  for _, l in ipairs(content) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(math.max(width + 2, 30), vim.o.columns - 4)
  local height = math.min(#content, 20)
  vim.api.nvim_open_win(pbuf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == pbuf then
          vim.api.nvim_win_close(win, true)
        end
      end
      if vim.api.nvim_buf_is_valid(pbuf) then
        vim.api.nvim_buf_delete(pbuf, { force = true })
      end
    end,
  })
end

function M.reset_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk_at(s.hunks, lnum)
  if not hunk then
    if s.staged and find_hunk_at(s.staged_hunks or {}, lnum) then
      M.unstage_hunk()
    end
    return
  end
  local old_lines = get_old_lines(reference_lines(s), hunk)
  local start = hunk.new_start - 1
  local end_line = start + hunk.new_count
  if hunk.type == 'delete' then
    vim.api.nvim_buf_set_lines(bufnr, hunk.new_start, hunk.new_start, false, old_lines)
  else
    vim.api.nvim_buf_set_lines(bufnr, start, end_line, false, old_lines)
  end
end

function M.reset_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.deepcopy(reference_lines(s)))
end

function M.stage_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk_at(s.hunks, lnum)
  if not hunk then
    if s.staged and find_hunk_at(s.staged_hunks or {}, lnum) then
      M.unstage_hunk()
    end
    return
  end

  local new_lines = get_new_lines(bufnr, hunk)
  local merged = splice(reference_lines(s), hunk, new_lines)

  local core = require('lu5je0.ext.diff-base.core')
  if lines_equal(merged, s.base) then
    core.unstage(bufnr)
  else
    core.stage_lines(bufnr, merged)
  end
end

function M.stage_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local core = require('lu5je0.ext.diff-base.core')
  local st = get_state(bufnr)
  if st and lines_equal(lines, st.base) then
    core.unstage(bufnr)
  else
    core.stage_lines(bufnr, lines)
  end
end

function M.unstage_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s or not s.staged then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk_at(s.staged_hunks or {}, lnum)
  if not hunk then return end

  local base_segment = {}
  for i = hunk.old_start, hunk.old_start + hunk.old_count - 1 do
    base_segment[#base_segment + 1] = s.base[i] or ''
  end

  local new_staged = {}
  if hunk.new_count == 0 then
    for i = 1, hunk.new_start do new_staged[#new_staged + 1] = s.staged[i] end
    for _, l in ipairs(base_segment) do new_staged[#new_staged + 1] = l end
    for i = hunk.new_start + 1, #s.staged do new_staged[#new_staged + 1] = s.staged[i] end
  else
    for i = 1, hunk.new_start - 1 do new_staged[#new_staged + 1] = s.staged[i] end
    for _, l in ipairs(base_segment) do new_staged[#new_staged + 1] = l end
    for i = hunk.new_start + hunk.new_count, #s.staged do new_staged[#new_staged + 1] = s.staged[i] end
  end

  local core = require('lu5je0.ext.diff-base.core')
  if lines_equal(new_staged, s.base) then
    core.unstage(bufnr)
  else
    core.stage_lines(bufnr, new_staged)
  end
end

function M.unstage_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local core = require('lu5je0.ext.diff-base.core')
  core.unstage(bufnr)
end

function M.diffthis()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local ft = vim.bo[bufnr].filetype
  vim.cmd('vsplit')
  local sbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(sbuf)
  vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, vim.deepcopy(reference_lines(s)))
  vim.bo[sbuf].filetype = ft
  vim.bo[sbuf].modifiable = false
  vim.bo[sbuf].buftype = 'nofile'
  vim.cmd('diffthis')
  vim.cmd('wincmd p')
  vim.cmd('diffthis')
end

function M.select_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk_at(s.hunks, lnum)
  if not hunk or hunk.type == 'delete' or hunk.new_count == 0 then return end
  vim.cmd('normal! ' .. hunk.new_start .. 'GV' .. (hunk.new_start + hunk.new_count - 1) .. 'G')
end

return M
