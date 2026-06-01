local state = require('lu5je0.ext.tree-sidebar.state')

local M = {}

local function save_root()
  if state.files.root then
    state.files._root_cache = state.files._root_cache or {}
    state.files._root_cache[vim.fn.getcwd()] = state.files.root
  end
end

local function restore_root(target)
  local cache = state.files._root_cache
  if cache and cache[target] then
    state.files.root = cache[target]
  else
    state.files.root = nil
  end
end

local function save_cursor()
  if state:is_open() then
    state.files._cursor_cache = state.files._cursor_cache or {}
    state.files._cursor_cache[vim.fn.getcwd()] = vim.api.nvim_win_get_cursor(state.win)
  end
end

local function restore_cursor()
  local cache = state.files._cursor_cache
  local cursor = cache and cache[vim.fn.getcwd()]
  local files = require('lu5je0.ext.tree-sidebar.sources.files')
  files.render()
  if cursor then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    pcall(vim.api.nvim_win_set_cursor, state.win, { math.min(cursor[1], line_count), cursor[2] })
  end
end

function M.back()
  if state.pwd_stack:count() >= 2 then
    save_cursor()
    save_root()
    state._is_jumping = true
    state.pwd_forward_stack:push(state.pwd_stack:pop())
    local target = state.pwd_stack:peek()
    vim.cmd('cd ' .. vim.fn.fnameescape(target))
    state._last_pushed_cwd = target
    state._is_jumping = false
    restore_root(target)
    restore_cursor()
  end
end

function M.forward()
  if state.pwd_forward_stack:count() >= 1 then
    save_cursor()
    save_root()
    state._is_jumping = true
    local target = state.pwd_forward_stack:pop()
    state.pwd_stack:push(target)
    vim.cmd('cd ' .. vim.fn.fnameescape(target))
    state._last_pushed_cwd = target
    state._is_jumping = false
    restore_root(target)
    restore_cursor()
  end
end

return M
