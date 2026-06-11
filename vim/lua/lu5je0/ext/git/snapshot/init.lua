local M = {}

local core = require('lu5je0.ext.git.snapshot.core')
local store = require('lu5je0.ext.git.snapshot.store')

local function abspath_of(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then return nil end
  return vim.fn.fnamemodify(name, ':p')
end

local function diff_base()
  local bufnr = vim.api.nvim_get_current_buf()

  if core.gitsigns_attached(bufnr) then
    vim.notify('DiffBase: refusing — buffer is attached to gitsigns (git tracked)', vim.log.levels.ERROR)
    return
  end

  local removed = store.gc(10)
  if removed > 0 then
    vim.notify(('DiffBase: GC removed %d stale entries'):format(removed), vim.log.levels.INFO)
  end

  local path = abspath_of(bufnr)
  local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if core.state[bufnr] then
    vim.notify('DiffBase: already active on this buffer', vim.log.levels.WARN)
    return
  end

  if path and store.exists(path) then
    local lines = store.load(path)
    if lines then
      core.activate(bufnr, lines, { message = 'DiffBase restored from disk' })
      return
    end
  end

  if path then
    store.save(path, current)
    core.activate(bufnr, vim.deepcopy(current), { message = 'DiffBase created' })
  else
    core.activate(bufnr, vim.deepcopy(current), { message = 'DiffBase active (in-memory only, buffer has no filename)' })
  end
end

local function diff_base_reset()
  local bufnr = vim.api.nvim_get_current_buf()
  if not core.state[bufnr] then
    vim.notify('DiffBaseReset: no active diff base on this buffer', vim.log.levels.WARN)
    return
  end
  local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  core.update_base(bufnr, current)
  vim.notify('DiffBase reset to current buffer', vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command('DiffBase', diff_base, {})
  vim.api.nvim_create_user_command('DiffBaseReset', diff_base_reset, {})
end

return M
