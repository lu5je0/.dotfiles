local M = {}

local env_keeper = require('lu5je0.misc.env-keeper')

local state = {
  keeper_enabled = false,
  backend = nil,
  applied = nil,
  typing_contexts = {},
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
  if vim.env.TERM == 'xterm-kitty' then
    return 'lu5je0.misc.ime.osc.backend'
  end
  if vim.fn.has('wsl') == 1 then
    return 'lu5je0.misc.ime.tui-bridge.backend'
  end
  if vim.fn.has('mac') == 1 then
    -- return 'lu5je0.misc.ime.tui-bridge.backend'
    return 'lu5je0.misc.ime.mac.backend'
  end
  if vim.fn.has('linux') == 1 and not vim.env.SSH_TTY then
    return 'lu5je0.misc.ime.tui-bridge.backend'
  end
  return 'lu5je0.misc.ime.osc.backend'
end

-- ── public API ────────────────────────────────────────────────

--- Which IME state a Neovim mode wants. Insert / replace / select / cmdline /
--- terminal are all "typing" modes; everything else is a command mode.
local function wanted_for_mode(mode)
  local m = mode:sub(1, 1)
  if m == 'i' or m == 'R' or m == 's' or m == 'c' or m == 't' then
    return 'insert'
  end
  return 'normal'
end

--- Mode transitions are never throttled: dropping the final transition can leave
--- the terminal IME disabled. Same-mode triggers only re-assert external state;
--- normal re-assertions must not overwrite the input source saved on transition.
local function apply(want)
  if not state.backend then return end
  if want == 'insert' and not save_last_ime_enabled() then return end

  local changed = state.applied ~= want
  if not changed and not rate_limiter:get() then return end

  if profile_timer then profile_timer.begin_timer() end
  if not changed and want == 'normal' then
    state.backend.ascii_mode()
  else
    state.backend[want]()
  end
  state.applied = want
  if profile_timer then profile_timer.end_timer() end
end

local function wanted_for_context()
  if next(state.typing_contexts) then return 'insert' end
  return wanted_for_mode(vim.api.nvim_get_mode().mode)
end

local function sync()
  apply(wanted_for_context())
end

--- Leaving is backend specific: one that switches the input source wants ASCII,
--- while one that bypasses the IME outright has to restore it first. Every
--- backend declares its own on_exit.
--- Deliberately skips apply(): if a throttled exit update were dropped there is
--- no later event to recover from and the terminal would stay stranded.
local function exit_now()
  if not state.backend then return end
  state.backend.on_exit()
end

function M.normal()
  apply('normal')
end

local function set_keeper(enable)
  state.keeper_enabled = enable
end

local function sync_keeper()
  set_keeper(wanted_for_context() == 'normal')
end

function M.set_typing_context(name, active)
  state.typing_contexts[name] = active and true or nil
  sync()
  sync_keeper()
end

-- ── autocmds ──────────────────────────────────────────────────

local function wire_status_autocmds()
  local group = vim.api.nvim_create_augroup('ime-status', { clear = true })

  -- One authoritative event: ModeChanged cannot miss a pairing the way
  -- InsertEnter/InsertLeave, CmdlineEnter/Leave and TermEnter/Leave can, and it
  -- also covers modes those six never reported.
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    pattern = '*:*',
    callback = function() sync() end,
  })

  -- Self-healing: re-assert whenever we (re)gain control of the window, since a
  -- shell in :terminal may have moved the state while we were not looking.
  vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function() sync() end,
  })

  -- Quitting or suspending hands the terminal back to the shell, so never leave
  -- it in a state the user cannot type in.
  vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimSuspend' }, {
    group = group,
    callback = function() exit_now() end,
  })

  vim.api.nvim_create_autocmd('VimResume', {
    group = group,
    callback = function() sync() end,
  })
end

local function wire_keeper_signal(backend)
  backend.on_change(function()
    -- Watch runs while Neovim is focused; keeper_enabled gates whether a change
    -- snaps back to ASCII (true in normal mode, false in insert/cmdline).
    if state.keeper_enabled then
      backend.ascii_mode()
    end
  end)
end

local function wire_keeper_autocmds(backend)
  local group = vim.api.nvim_create_augroup('ime-keeper-common', { clear = true })

  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    pattern = '*:*',
    callback = function() sync_keeper() end,
  })

  -- Native watch follows focus: only subscribe while Neovim is focused so the
  -- keeper never fights the IME of another app.
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function() backend.keeper(false) end,
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      backend.keeper(true)
      sync_keeper()
    end,
  })
end

--- Push the current mode down to the backend. Must run for every backend, so it
--- deliberately lives outside config_keeper, which bails out early for backends
--- that do not implement the keeper.
local function sync_initial_state()
  sync()
  sync_keeper()
end

local function config_keeper(backend)
  if keeper_disabled_here() then return end
  if not backend.on_change or not backend.keeper then return end
  wire_keeper_signal(backend)
  wire_keeper_autocmds(backend)

  -- Assume focused at startup; watch is toggled by FocusLost/FocusGained.
  backend.keeper(true)
end

-- ── entry ─────────────────────────────────────────────────────

function M.setup()
  if #vim.api.nvim_list_uis() == 0 then return end

  state.backend = require(select_backend_module()).setup()
  rate_limiter = require('lu5je0.lang.ratelimiter'):create(20, 0.5)

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
  -- deferred so a backend that writes escapes does not race the TUI startup
  vim.schedule(sync_initial_state)
end

return M
