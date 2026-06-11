local M = {}

local function get_state(bufnr)
  local core = require('lu5je0.ext.git.snapshot.core')
  return core.state[bufnr]
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

local function get_old_lines(base, hunk)
  local lines = {}
  for i = hunk.old_start, hunk.old_start + hunk.old_count - 1 do
    lines[#lines + 1] = base[i] or ''
  end
  return lines
end

local function get_new_lines(bufnr, hunk)
  if hunk.new_count == 0 then return {} end
  return vim.api.nvim_buf_get_lines(bufnr, hunk.new_start - 1, hunk.new_start - 1 + hunk.new_count, false)
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
  local old_lines = get_old_lines(s.base, hunk)
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
  if not hunk then return end
  local old_lines = get_old_lines(s.base, hunk)
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
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.deepcopy(s.base))
end

function M.stage_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk = find_hunk_at(s.hunks, lnum)
  if not hunk then return end

  local new_lines = get_new_lines(bufnr, hunk)
  local base = vim.deepcopy(s.base)
  local before = {}
  local after = {}
  if hunk.old_count == 0 then
    for i = 1, hunk.old_start do before[#before + 1] = base[i] end
    for i = hunk.old_start + 1, #base do after[#after + 1] = base[i] end
  else
    for i = 1, hunk.old_start - 1 do before[#before + 1] = base[i] end
    for i = hunk.old_start + hunk.old_count, #base do after[#after + 1] = base[i] end
  end
  local merged = {}
  vim.list_extend(merged, before)
  vim.list_extend(merged, new_lines)
  vim.list_extend(merged, after)

  local core = require('lu5je0.ext.git.snapshot.core')
  core.update_base(bufnr, merged)
end

function M.stage_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local core = require('lu5je0.ext.git.snapshot.core')
  core.update_base(bufnr, lines)
end

function M.diffthis()
  local bufnr = vim.api.nvim_get_current_buf()
  local s = get_state(bufnr)
  if not s then return end
  local ft = vim.bo[bufnr].filetype
  vim.cmd('vsplit')
  local sbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(sbuf)
  vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, vim.deepcopy(s.base))
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
