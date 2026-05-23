local api = vim.api
local fn = vim.fn

local cache = require('lu5je0.ext.git.blame.cache')
local colors = require('lu5je0.ext.git.blame.colors')
local git = require('lu5je0.ext.git.blame.git')
local render = require('lu5je0.ext.git.blame.render')
local selection = require('lu5je0.ext.git.blame.selection')

local M = {}

local AUGROUP_NAME = 'git_blame'

local is_setup = false
local attached = {}

-- ── view helpers ────────────────────────────────────────────

local function visible_range(winid, bufnr)
  if not api.nvim_win_is_valid(winid) then return end
  if api.nvim_win_get_buf(winid) ~= bufnr then return end
  local range = api.nvim_win_call(winid, function()
    return { fn.line('w0'), fn.line('w$') }
  end)
  return range[1], range[2]
end

local function current_view()
  local winid = api.nvim_get_current_win()
  local bufnr = api.nvim_win_get_buf(winid)
  local topline, botline = visible_range(winid, bufnr)
  if not topline then return end
  return { winid = winid, bufnr = bufnr, topline = topline, botline = botline }
end

local function is_enabled(bufnr)
  return api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].git_blame == true
end

-- ── refresh ─────────────────────────────────────────────────

local function on_blame_loaded(bufnr, ok)
  if not ok or not api.nvim_buf_is_valid(bufnr) or not is_enabled(bufnr) then
    return
  end
  local view = current_view()
  if view and view.bufnr == bufnr then
    render.redraw(bufnr, view.topline, view.botline)
  else
    render.redraw(bufnr)
  end
end

local function load_blame(bufnr, on_ready)
  git.run(bufnr, function(ok, result)
    if ok then
      cache.set(bufnr, result)
    end
    if on_ready then on_ready(ok) end
  end)
end

local function refresh(bufnr)
  if not is_enabled(bufnr) then return end
  if cache.has_fresh(bufnr) then
    local view = current_view()
    if view and view.bufnr == bufnr then
      render.redraw(bufnr, view.topline, view.botline)
    end
    return
  end
  load_blame(bufnr, function(ok)
    on_blame_loaded(bufnr, ok)
  end)
end

local refresh_after_edit_debounced = require('lu5je0.lang.function-utils').debounce(function()
  local view = current_view()
  if not view or not is_enabled(view.bufnr) then return end
  load_blame(view.bufnr, function(ok)
    on_blame_loaded(view.bufnr, ok)
  end)
end, 200)

-- ── buffer hooks ────────────────────────────────────────────

local function ensure_attached(bufnr)
  if attached[bufnr] then return end
  attached[bufnr] = true

  api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, b, _changedtick, firstline, lastline, new_lastline)
      if not cache.get(b) then return end
      cache.shift_lines(b, firstline, lastline, new_lastline)
      vim.schedule(function()
        if not is_enabled(b) then return end
        local view = current_view()
        if view and view.bufnr == b then
          render.redraw(b, view.topline, view.botline)
        end
        refresh_after_edit_debounced()
      end)
    end,
    on_reload = function(_, b)
      cache.clear(b)
      vim.schedule(function()
        if is_enabled(b) then refresh(b) end
      end)
    end,
    on_detach = function(_, b)
      attached[b] = nil
    end,
  })
end

-- ── public API ──────────────────────────────────────────────

function M.component(args)
  return render.component(args)
end

function M.set_selected_line(bufnr, lnum)
  if not api.nvim_buf_is_valid(bufnr) then return end
  local previous = selection.get(bufnr)
  selection.set(bufnr, lnum)
  if previous and previous ~= lnum then
    render.redraw(bufnr, previous, previous)
  end
  if lnum then
    render.redraw(bufnr, lnum, lnum)
  end
end

function M.clear_selected_line(bufnr)
  M.set_selected_line(bufnr, nil)
end

function M.get_blame_for_line(bufnr, lnum)
  return cache.commit_for_line(bufnr, lnum)
end

function M.ensure_blame_ready(bufnr, callback)
  if cache.has_fresh(bufnr) then
    callback(true)
    return
  end
  load_blame(bufnr, callback)
end

function M.toggle()
  local bufnr = api.nvim_get_current_buf()
  vim.b.git_blame = not vim.b.git_blame

  if vim.b.git_blame then
    ensure_attached(bufnr)
    if cache.has_fresh(bufnr) then
      vim.b[bufnr].max_blame_length = cache.max_width(bufnr)
      local view = current_view()
      if view and view.bufnr == bufnr then
        render.redraw(bufnr, view.topline, view.botline)
      end
      return
    end

    local resolved = false
    load_blame(bufnr, function(ok)
      if resolved then
        on_blame_loaded(bufnr, ok)
        return
      end
      resolved = true
      on_blame_loaded(bufnr, ok)
    end)

    local timer = vim.uv.new_timer()
    timer:start(100, 0, vim.schedule_wrap(function()
      timer:close()
      if resolved then return end
      resolved = true
      if not is_enabled(bufnr) then return end
      vim.b[bufnr].max_blame_length = vim.b[bufnr].max_blame_length or cache.max_width(bufnr)
      local view = current_view()
      if view and view.bufnr == bufnr then
        render.redraw(bufnr, view.topline, view.botline)
      end
    end))
    return
  end

  cache.clear(bufnr)
  selection.clear(bufnr)
  local view = current_view()
  if view and view.bufnr == bufnr then
    render.redraw(bufnr, view.topline, view.botline)
  else
    vim.cmd('redraw')
  end
end

function M.on_click(_minwid, _clicks, button, _mods)
  if button ~= 'r' then return end

  local pos = fn.getmousepos() or {}
  local lnum = pos.line
  local winid = pos.winid
  if not lnum or lnum < 1 or not winid or not api.nvim_win_is_valid(winid) then
    return
  end
  local bufnr = api.nvim_win_get_buf(winid)
  if not is_enabled(bufnr) then return end

  ensure_attached(bufnr)
  require('lu5je0.ext.git.blame-menu').open({
    bufnr = bufnr,
    winid = winid,
    lnum = lnum,
  })
end

function M.setup()
  if is_setup then return end
  is_setup = true

  colors.define()

  local group = api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = colors.define,
  })

  api.nvim_create_autocmd('WinScrolled', {
    group = group,
    callback = function()
      local view = current_view()
      if view and is_enabled(view.bufnr) then
        refresh(view.bufnr)
      end
    end,
  })

  api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      cache.clear(args.buf)
      selection.on_buf_gone(args.buf)
      git.cancel(args.buf)
      attached[args.buf] = nil
    end,
  })
end

return M
