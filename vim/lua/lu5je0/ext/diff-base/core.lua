local M = {}

local store = require('lu5je0.ext.diff-base.store')
local diff = require('lu5je0.ext.diff-base.diff')
local signs = require('lu5je0.ext.diff-base.signs')
local keymaps = require('lu5je0.ext.diff-base.keymaps')

M.state = {}

local AUGROUP = vim.api.nvim_create_augroup('diff_base', { clear = true })

local function abspath(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then return nil end
  return vim.fn.fnamemodify(name, ':p')
end

local function update_status(bufnr, hunks)
  local s = diff.summary(hunks)
  vim.b[bufnr].diff_base_active = true
  vim.b[bufnr].diff_base_status_dict = s
end

local function recompute(bufnr)
  local s = M.state[bufnr]
  if not s then return end
  local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local reference = s.staged or s.base
  s.hunks = diff.compute(reference, current)
  if s.staged then
    s.staged_hunks = diff.compute(s.base, s.staged)
  else
    s.staged_hunks = {}
  end
  signs.draw(bufnr, { unstaged = s.hunks, staged = s.staged_hunks })
  update_status(bufnr, s.hunks)
end

local function schedule_recompute(bufnr)
  local s = M.state[bufnr]
  if not s then return end
  if s.timer then s.timer:stop(); s.timer:close(); s.timer = nil end
  local timer = (vim.uv or vim.loop).new_timer()
  s.timer = timer
  timer:start(500, 0, vim.schedule_wrap(function()
    if s.timer == timer then
      timer:stop(); timer:close(); s.timer = nil
    end
    if M.state[bufnr] and vim.api.nvim_buf_is_valid(bufnr) then
      recompute(bufnr)
    end
  end))
end

local function speculative_update(bufnr, start, old_end, new_end)
  local s = M.state[bufnr]
  if not s then return end

  local delta = new_end - old_end
  local edit_start = start + 1
  local edit_end_old = old_end

  local new_hunks = {}
  local merge_min = edit_start
  local merge_max = edit_start + (new_end - start) - 1
  local has_overlap = false
  local overlap_has_change = false
  local overlap_has_delete = false

  for _, h in ipairs(s.hunks) do
    local h_start = h.new_start
    local h_end = h.new_start + math.max(h.new_count, 1) - 1

    if h_end < edit_start then
      new_hunks[#new_hunks + 1] = h
    elseif h_start > edit_end_old then
      new_hunks[#new_hunks + 1] = {
        type = h.type,
        old_start = h.old_start,
        old_count = h.old_count,
        new_start = h.new_start + delta,
        new_count = h.new_count,
      }
    else
      has_overlap = true
      if h.type == 'change' then overlap_has_change = true end
      if h.type == 'delete' then overlap_has_delete = true end
      local shifted_h_end = h_end + delta
      if h_start < edit_start then
        merge_min = math.min(merge_min, h_start)
      end
      if shifted_h_end > merge_max then
        merge_max = shifted_h_end
      end
    end
  end

  local spec_count = merge_max - merge_min + 1
  if spec_count > 0 then
    local spec_type
    if not overlap_has_change and not overlap_has_delete then
      if old_end == start then
        spec_type = 'add'
      elseif has_overlap then
        spec_type = 'add'
      else
        spec_type = 'change'
      end
    else
      spec_type = 'change'
    end
    new_hunks[#new_hunks + 1] = {
      type = spec_type,
      old_start = merge_min,
      old_count = 0,
      new_start = merge_min,
      new_count = spec_count,
    }
  elseif delta < 0 and new_end <= start then
    new_hunks[#new_hunks + 1] = {
      type = 'delete',
      old_start = edit_start,
      old_count = old_end - start,
      new_start = start,
      new_count = 0,
    }
  end

  table.sort(new_hunks, function(a, b) return a.new_start < b.new_start end)
  s.hunks = new_hunks
  signs.draw(bufnr, { unstaged = s.hunks, staged = s.staged_hunks or {} })
end

local function attach_buf(bufnr)
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, _, start, old_end, new_end)
      if not M.state[buf] then return true end
      speculative_update(buf, start, old_end, new_end)
      schedule_recompute(buf)
    end,
    on_detach = function(_, buf)
      if M.state[buf] then
        M.detach(buf)
      end
    end,
  })
end

local function attach_autocmds(bufnr)
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = AUGROUP,
    buffer = bufnr,
    callback = function() recompute(bufnr) end,
  })
  vim.api.nvim_create_autocmd('BufFilePost', {
    group = AUGROUP,
    buffer = bufnr,
    callback = function()
      local s = M.state[bufnr]
      if not s then return end
      local p = abspath(bufnr)
      if p then
        store.save(p, s.base)
        if s.staged then
          store.save_staged(p, s.staged)
        end
        s.path = p
        vim.notify('DiffBase persisted to disk', vim.log.levels.INFO)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = AUGROUP,
    buffer = bufnr,
    callback = function() M.detach(bufnr, { keep_disk = true }) end,
  })
end

function M.gitsigns_attached(bufnr)
  local ok, cache = pcall(require, 'gitsigns.cache')
  if not ok then return false end
  return cache.cache and cache.cache[bufnr] ~= nil
end

function M.activate(bufnr, base_lines, opts)
  opts = opts or {}
  local path = abspath(bufnr)
  local staged
  if path and store.exists_staged(path) then
    staged = store.load_staged(path)
  end
  M.state[bufnr] = {
    base = base_lines,
    staged = staged,
    hunks = {},
    staged_hunks = {},
    timer = nil,
    path = path,
  }
  keymaps.apply(bufnr)
  attach_buf(bufnr)
  attach_autocmds(bufnr)
  recompute(bufnr)
  if opts.message then
    vim.notify(opts.message, vim.log.levels.INFO)
  end
end

function M.update_base(bufnr, lines)
  local s = M.state[bufnr]
  if not s then return end
  s.base = vim.deepcopy(lines)
  if s.path then
    store.save(s.path, s.base)
  end
  recompute(bufnr)
end

function M.stage_lines(bufnr, lines)
  local s = M.state[bufnr]
  if not s then return end
  s.staged = vim.deepcopy(lines)
  if s.path then
    store.save_staged(s.path, s.staged)
  end
  recompute(bufnr)
end

function M.unstage(bufnr)
  local s = M.state[bufnr]
  if not s then return end
  s.staged = nil
  if s.path then
    store.delete_staged(s.path)
  end
  recompute(bufnr)
end

function M.detach(bufnr, opts)
  opts = opts or {}
  local s = M.state[bufnr]
  if not s then return end
  if s.timer then pcall(function() s.timer:stop(); s.timer:close() end) end
  M.state[bufnr] = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    signs.clear(bufnr)
    keymaps.clear(bufnr)
    vim.b[bufnr].diff_base_active = nil
    vim.b[bufnr].diff_base_status_dict = nil
  end
end

return M
