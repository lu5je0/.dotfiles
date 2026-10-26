local M = {}

local installer = require('lu5je0.misc.tui-bridge.installer').default()
local awaiting_install = false

local state = {
  process_handle = nil,
  stdin_pipe = nil,
  stdout_pipe = nil,
  exe_path = nil,
  is_running = false,
  next_id = 1,
  pending = {},
  callbacks = {},
  stdout_buffer = '',
}

local function reset_state()
  state.process_handle = nil
  state.stdin_pipe = nil
  state.stdout_pipe = nil
  state.is_running = false
  state.pending = {}
  state.callbacks = {}
  state.stdout_buffer = ''
end

local function process_stdout_line(line)
  if line == '' then
    return
  end

  local ok, resp = pcall(vim.json.decode, line)
  if not ok or type(resp) ~= 'table' then
    return
  end

  if type(resp.id) == 'number' then
    local callback = state.callbacks[resp.id]
    if callback then
      state.callbacks[resp.id] = nil
      vim.schedule(function()
        if resp.ok ~= true then
          local err = resp.error or {}
          callback(nil, (err.code or 'unknown_error') .. ': ' .. (err.message or ''))
        else
          callback(resp.result)
        end
      end)
    else
      state.pending[resp.id] = resp
    end
    return
  end
end

local function on_stdout_data(data)
  state.stdout_buffer = state.stdout_buffer .. data
  while true do
    local idx = state.stdout_buffer:find('\n', 1, true)
    if not idx then
      break
    end
    local line = state.stdout_buffer:sub(1, idx - 1)
    state.stdout_buffer = state.stdout_buffer:sub(idx + 1)
    process_stdout_line(line)
  end
end

local function start_process()
  if state.is_running and state.process_handle then
    return true
  end

  if not state.exe_path or vim.fn.executable(state.exe_path) == 0 then
    return false
  end

  local stdin = vim.uv.new_pipe(false)
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)
  if not stdin or not stdout or not stderr then
    return false
  end

  local handle = vim.uv.spawn(state.exe_path, {
    args = { '-i' },
    stdio = { stdin, stdout, stderr },
  }, function()
    if stdin and not stdin:is_closing() then
      stdin:close()
    end
    if stdout and not stdout:is_closing() then
      stdout:close()
    end
    if stderr and not stderr:is_closing() then
      stderr:close()
    end

    reset_state()
  end)

  if not handle then
    if not stdin:is_closing() then
      stdin:close()
    end
    if not stdout:is_closing() then
      stdout:close()
    end
    if not stderr:is_closing() then
      stderr:close()
    end
    vim.notify('启动 TUI Bridge 进程失败', vim.log.levels.ERROR, { title = 'TUI Bridge' })
    return false
  end

  stderr:read_start(function(_, _) end)

  stdout:read_start(function(err, data)
    if err then
      return
    end
    if data then
      on_stdout_data(data)
    end
  end)

  state.process_handle = handle
  state.stdin_pipe = stdin
  state.stdout_pipe = stdout
  state.is_running = true
  return true
end

function M.on_ready(callback)
  installer.on_ready(function(path)
    state.exe_path = path
    if start_process() then callback() end
  end)
end

function M.singleton()
  return M
end

function M.call(module, method, params, opts)
  opts = opts or {}
  local wait_response = opts.wait_response == true
  local timeout = opts.timeout or 1500

  if not start_process() then
    if not awaiting_install then
      awaiting_install = true
      M.on_ready(function() awaiting_install = false end)
    end
    if opts.callback then
      vim.schedule(function() opts.callback(nil, 'process_not_running') end)
    end
    return nil, 'process_not_running'
  end

  local id = state.next_id
  state.next_id = state.next_id + 1

  local callback = opts.callback
  if callback then
    state.callbacks[id] = callback
  end

  local payload_params = params
  if payload_params == nil then
    payload_params = vim.empty_dict()
  elseif type(payload_params) == 'table' and next(payload_params) == nil then
    payload_params = vim.empty_dict()
  end

  local payload = vim.json.encode({
    id = id,
    module = module,
    method = method,
    params = payload_params,
  }) .. '\n'

  state.stdin_pipe:write(payload, function(err)
    if err then
      state.pending[id] = {
        id = id,
        ok = false,
        error = { code = 'WRITE_FAILED', message = err },
      }
    end
  end)

  if callback then
    return true
  end

  if not wait_response then
    return true
  end

  local done = vim.wait(timeout, function()
    return state.pending[id] ~= nil
  end, 1, false)

  local resp = state.pending[id]
  state.pending[id] = nil

  if not done or not resp then
    return nil, 'timeout'
  end
  if resp.ok ~= true then
    local err = resp.error or {}
    return nil, (err.code or 'unknown_error') .. ': ' .. (err.message or '')
  end
  return resp.result
end

--- One-shot request in a detached process.
---
--- For exit-time calls: the interactive helper is our child, so a write issued
--- while quitting may never flush, and on hosts where it is not already running
--- it would be cold-spawned only to die immediately. A detached one-shot lives
--- on past us.
function M.call_detached(module, method, params)
  local path = installer.installed_path()
  if not path then
    return false
  end
  local payload = vim.json.encode({
    id = 1,
    module = module,
    method = method,
    params = params or vim.empty_dict(),
  })
  vim.fn.jobstart({ path, '-j', payload }, { detach = true })
  return true
end

return M
