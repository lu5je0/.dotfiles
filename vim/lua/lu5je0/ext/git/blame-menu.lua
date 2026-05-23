local fn = vim.fn
local api = vim.api

local porcelain = require('lu5je0.ext.git.blame.porcelain')

local M = {}

local MENU_PATH = ']GitBlame'

local pending = nil

-- Vim menu names use '.' for submenus, '\' to escape, '&' for mnemonic,
-- '|' to terminate the command; spaces must be backslash-escaped.
local function esc_label(s)
  return (s:gsub('[\\%.&| ]', function(c)
    return '\\' .. c
  end))
end

-- ── actions ─────────────────────────────────────────────────

local function action_copy_full(commit)
  fn.setreg('+', commit.sha)
  fn.setreg('"', commit.sha)
  vim.notify('Copied commit hash: ' .. commit.sha:sub(1, 8), vim.log.levels.INFO)
end

local function action_show_commit(commit, bufnr)
  local file = api.nvim_buf_get_name(bufnr)
  local cwd = file ~= '' and vim.fs.dirname(file) or fn.getcwd()
  vim.system({ 'git', 'show', '--stat', '--patch', commit.sha }, {
    text = true,
    cwd = cwd,
  }, vim.schedule_wrap(function(out)
    if out.code ~= 0 then
      vim.notify('git show failed: ' .. (out.stderr or ''), vim.log.levels.ERROR)
      return
    end
    vim.cmd('tabnew')
    local b = api.nvim_get_current_buf()
    vim.bo[b].buftype = 'nofile'
    vim.bo[b].bufhidden = 'wipe'
    vim.bo[b].swapfile = false
    vim.bo[b].filetype = 'git'
    api.nvim_buf_set_lines(b, 0, -1, false, vim.split(out.stdout or '', '\n', { plain = true }))
    vim.bo[b].modifiable = false
    pcall(api.nvim_buf_set_name, b, 'git show ' .. commit.sha:sub(1, 8))
  end))
end

local function action_show_in_project_log(commit, bufnr)
  local ok, project_log = pcall(require, 'lu5je0.ext.git.project-log')
  if not ok then
    vim.notify('project-log not available', vim.log.levels.WARN)
    return
  end
  local file = bufnr and api.nvim_buf_get_name(bufnr) or ''
  project_log.show({
    jump_to_sha = commit.sha,
    jump_to_file = file ~= '' and file or nil,
  })
end

local function build_actions(commit, bufnr)
  return {
    { label = 'Copy commit hash',    fn = function() action_copy_full(commit) end },
    { label = 'Show commit',         fn = function() action_show_commit(commit, bufnr) end },
    { label = 'Show in project log', fn = function() action_show_in_project_log(commit, bufnr) end },
  }
end

-- ── menu build / popup ──────────────────────────────────────

local function clear_menu()
  pcall(vim.cmd, 'silent! aunmenu ' .. MENU_PATH)
end

local function build_menu(commit, actions)
  clear_menu()

  for idx, action in ipairs(actions) do
    local rhs = string.format(
      '<Cmd>lua require("lu5je0.ext.git.blame-menu").trigger(%d)<CR>',
      idx
    )
    vim.cmd(string.format(
      'anoremenu <silent> %s.%s %s',
      MENU_PATH, esc_label(action.label), rhs
    ))
  end
end

function M.trigger(idx)
  if pending then
    pending.chosen = idx
  end
end

local function dispatch_chosen()
  local p = pending
  pending = nil
  if not p or not p.chosen then return end
  local action = p.actions[p.chosen]
  if not action then return end
  vim.schedule(function()
    pcall(action.fn)
  end)
end

local function get_normal_bg()
  local hl = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }) or {}
  return hl.bg
end

local function hide_cursor()
  local bg = get_normal_bg()
  local color = bg and string.format('#%06x', bg) or 'NONE'
  vim.api.nvim_set_hl(0, 'Lu5je0HiddenCursor', { fg = color, bg = color, blend = 100 })
  local saved = vim.o.guicursor
  vim.o.guicursor = 'a:Lu5je0HiddenCursor/lCursor,a:blinkon0'
  return saved
end

local function restore_cursor(saved)
  if saved then
    vim.o.guicursor = saved
  end
end

local function show_menu_for(opts, commit)
  local actions = build_actions(commit, opts.bufnr)
  pending = { actions = actions, bufnr = opts.bufnr }

  build_menu(commit, actions)

  local blame = require('lu5je0.ext.git.blame')
  blame.set_selected_line(opts.bufnr, opts.lnum)

  local saved_guicursor = hide_cursor()

  -- :popup! uses the current mouse pointer position (not the cursor) and
  -- handles edge flipping the same way the native <RightMouse> menu does.
  local ok, err = pcall(vim.cmd, 'popup! ' .. MENU_PATH)
  clear_menu()

  restore_cursor(saved_guicursor)
  blame.clear_selected_line(opts.bufnr)

  if not ok then
    pending = nil
    vim.notify('Failed to open menu: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end

  dispatch_chosen()
end

-- ── public API ──────────────────────────────────────────────

function M.open(opts)
  if pending then
    clear_menu()
    pending = nil
  end

  local blame = require('lu5je0.ext.git.blame')

  local function with_commit(c)
    if not c or porcelain.is_zero_sha(c.sha) then
      vim.notify('Line is uncommitted', vim.log.levels.INFO)
      return
    end
    -- Defer one tick so the click handler's stack unwinds before :popup blocks.
    vim.schedule(function()
      show_menu_for(opts, c)
    end)
  end

  local commit = blame.get_blame_for_line(opts.bufnr, opts.lnum)
  if commit then
    with_commit(commit)
    return
  end

  vim.notify('Loading blame...', vim.log.levels.INFO)
  blame.ensure_blame_ready(opts.bufnr, function(ok)
    if not ok then
      vim.notify('Failed to load blame', vim.log.levels.WARN)
      return
    end
    with_commit(blame.get_blame_for_line(opts.bufnr, opts.lnum))
  end)
end

function M.close()
  clear_menu()
  pending = nil
end

return M
