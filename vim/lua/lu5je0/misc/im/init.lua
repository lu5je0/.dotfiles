local M = {}

local env_keeper = require('lu5je0.misc.env-keeper')

local state = {
  keeper_enabled = false,
  backend = nil,
}

local rate_limiter
local profile_timer = nil

-- ── config helpers ────────────────────────────────────────────

local function save_last_ime_enabled()
  return env_keeper.get('save_last_ime', true)
end

local function toggle_save_last_ime()
  local next_v = not save_last_ime_enabled()
  env_keeper.set('save_last_ime', next_v)
  print(next_v and 'keep last ime enabled' or 'keep last ime disabled')
end

--- keeper is meaningless in these hosts because they intercept IME
--- state changes themselves (Apple Terminal, JetBrains embedded term)
--- or run inside another nvim (:!nvim spawns).
local function keeper_disabled_here()
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then return true end
  if vim.env.TERMINAL_EMULATOR == 'JetBrains-JediTerm' then return true end
  if vim.env.NVIM ~= nil and vim.env.NVIM ~= '' then return true end
  return false
end

local function select_backend_module()
  if vim.fn.has('wsl') == 1 then
    return 'lu5je0.misc.im.win.backend'
  end
  if vim.fn.has('mac') == 1 then
    return 'lu5je0.misc.im.mac.backend'
  end
  if vim.fn.has('linux') == 1 and not vim.env.SSH_TTY then
    return 'lu5je0.misc.im.linux.backend'
  end
  return 'lu5je0.misc.im.ssh.backend'
end

-- ── public API ────────────────────────────────────────────────

function M.normal()
  if not state.backend then return end
  if not rate_limiter:get() then return end
  if profile_timer then profile_timer.begin_timer() end
  state.backend.normal()
  if profile_timer then profile_timer.end_timer() end
end

function M.insert()
  if not state.backend then return end
  if not save_last_ime_enabled() then return end
  if not rate_limiter:get() then return end
  if profile_timer then profile_timer.begin_timer() end
  state.backend.insert()
  if profile_timer then profile_timer.end_timer() end
end

local function set_keeper(enable)
  state.keeper_enabled = enable
  ---@diagnostic disable-next-line: need-check-nil
  state.backend.keeper(enable)
end

-- ── autocmds ──────────────────────────────────────────────────

local function wire_status_autocmds()
  local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'CmdlineLeave' }, {
    group = group,
    callback = M.normal,
  })
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    callback = M.insert,
  })
end

local function wire_keeper_signal(backend)
  backend.on_change(function()
    -- backend.keeper(false) may not have flushed pending events yet;
    -- keeper_enabled acts as the last-line filter for that race.
    if state.keeper_enabled then
      backend.ascii_mode()
    end
  end)
end

local function wire_keeper_autocmds()
  local group = vim.api.nvim_create_augroup('ime-keeper-common', { clear = true })

  vim.api.nvim_create_autocmd({ 'InsertLeave', 'CmdlineLeave', 'TermLeave' }, {
    group = group,
    callback = function() set_keeper(true) end,
  })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'FocusLost', 'TermEnter', 'CmdlineEnter' }, {
    group = group,
    callback = function() set_keeper(false) end,
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      if vim.api.nvim_get_mode().mode == 'n' then
        M.normal()
        set_keeper(true)
      end
    end,
  })
end

local function config_keeper(backend)
  if keeper_disabled_here() then return end
  if not backend.on_change or not backend.keeper then return end
  wire_keeper_signal(backend)
  wire_keeper_autocmds()

  if vim.api.nvim_get_mode().mode == 'n' then
    M.normal()
    set_keeper(true)
  end
end

-- ── entry ─────────────────────────────────────────────────────

function M.setup()
  if #vim.api.nvim_list_uis() == 0 then return end

  state.backend = require(select_backend_module()).setup()
  rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)

  vim.keymap.set('n', '<leader>vi', toggle_save_last_ime)
  vim.api.nvim_create_user_command('ImProfile', function(opts)
    local arg = opts.args
    local enable
    if arg == 'on' then
      enable = true
    elseif arg == 'off' then
      enable = false
    else
      enable = profile_timer == nil
    end
    profile_timer = enable and require('lu5je0.lang.timer') or nil
    print('ImProfile: ' .. (enable and 'on' or 'off'))
  end, { nargs = '?', complete = function() return { 'on', 'off' } end })

  wire_status_autocmds()
  config_keeper(state.backend)
end

return M
