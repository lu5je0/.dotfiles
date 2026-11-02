-- Source hooks: enter(ctx, opts), leave(ctx), locate(ctx, target), dispose(ctx).
-- Hooks are optional; enter falls back to render. ctx owns one source visit
-- within a Neovim tabpage; leave invalidates it before releasing resources.
local state = require('lu5je0.ext.sidebar.state')
local config = require('lu5je0.ext.sidebar.config')

local M = {}

function M.source(idx, loaded_only)
  local tab = config.tabs[idx]
  if not tab then
    return
  end
  local name = 'lu5je0.ext.sidebar.sources.' .. tab.id
  if loaded_only then
    return package.loaded[name]
  end
  return require(name)
end

-- Capture ownership at the synchronous entry point, before scheduling work.
function M.capture(ts)
  ts = ts or state.tab()
  return { state = ts, tabpage = ts.tabpage, idx = ts.active_tab_idx, generation = ts.source_generation }
end

function M.is_current(ctx)
  local ts = ctx.state
  return not ts.disposed
    and vim.api.nvim_tabpage_is_valid(ctx.tabpage)
    and vim.api.nvim_get_current_tabpage() == ctx.tabpage
    and ts.source_generation == ctx.generation
    and ts.active_tab_idx == ctx.idx
    and ts.win ~= nil
    and vim.api.nvim_win_is_valid(ts.win)
end

-- Ensure the source is ready; focus/open_tab can re-enter the same visit.
-- Hooks must tolerate repeated calls with the same ctx until leave.
function M.enter(ts, opts)
  ts = ts or state.tab()
  local ctx = ts.source_context
  if not ctx then
    ctx = M.capture(ts)
    ts.source_context = ctx
  end
  local source = M.source(ctx.idx)
  if source.enter then
    source.enter(ctx, opts or {})
  elseif source.render then
    source.render()
  end
  return ctx
end

function M.locate(ts, target)
  local source = M.source(ts.active_tab_idx)
  if source.locate then
    source.locate(M.capture(ts), target)
  end
end

-- Invalidate callbacks first, then release preview UI and source-owned work.
function M.leave(ts)
  ts = ts or state.tab()
  local ctx = ts.source_context
  ts.source_context = nil
  ts.source_generation = ts.source_generation + 1
  require('lu5je0.ext.sidebar.actions.preview').stop_for(ts)
  local source = ctx and M.source(ctx.idx, true)
  if source and source.leave then
    source.leave(ctx)
  end
end

-- Finalize a successful close (WinClosed or the window.close fallback).
function M.close(ts)
  ts = ts or state.tab()
  ts.win = nil
  M.leave(ts)
  require('lu5je0.ext.sidebar.watcher').release(ts)
  require('lu5je0.ext.sidebar.git_status').release(ts)
  require('lu5je0.ext.sidebar.tabs').reset_transient(ts)
end

function M.dispose(ts)
  if ts.disposed then
    return
  end
  M.close(ts)
  ts.disposed = true
  for idx in ipairs(config.tabs) do
    local source = M.source(idx, true)
    if source and source.dispose then
      local ctx = M.capture(ts)
      ctx.idx = idx
      source.dispose(ctx)
    end
  end
end

return M
