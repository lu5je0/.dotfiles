local M = {}

local STD_PATH = vim.fn.stdpath('config')

local exe_path
if vim.fn.has("mac") == 1 then
  exe_path = STD_PATH .. '/lib/tui_bridge_mac'
elseif vim.fn.has('wsl') == 1 then
  exe_path = STD_PATH .. '/lib/tui_bridge_win'
end

local state = {
  process_handle = nil,
  stdin_pipe = nil,
  stdout_pipe = nil,
  exe_path = exe_path,
  is_running = false,
  next_id = 1,
  pending = {},
  stdout_buffer = '',
  event_handlers = {},
}

local function reset_state()
  state.process_handle = nil
  state.stdin_pipe = nil
  state.stdout_pipe = nil
  state.is_running = false
  state.pending = {}
  state.stdout_buffer = ''
  state.event_handlers = {}
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
    state.pending[resp.id] = resp
    return
  end

  if type(resp.event) == 'string' then
    local handlers = state.event_handlers[resp.event]
    if handlers then
      vim.schedule(function()
        for _, handler in ipairs(handlers) do
          handler(resp)
        end
      end)
    end
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
    vim.notify('找不到 tui_bridge_win.exe，请检查配置路径', vim.log.levels.ERROR, { title = 'TUI Bridge' })
    return false
  end

  local stdin = vim.uv.new_pipe(false)
  local stdout = vim.uv.new_pipe(false)
  if not stdin or not stdout then
    return false
  end

  local handle = vim.uv.spawn(state.exe_path, {
    args = { '-i' },
    stdio = { stdin, stdout, nil },
  }, function()
    if stdin and not stdin:is_closing() then
      stdin:close()
    end
    if stdout and not stdout:is_closing() then
      stdout:close()
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
    vim.notify('启动 TUI Bridge 进程失败', vim.log.levels.ERROR, { title = 'TUI Bridge' })
    return false
  end

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

function M.setup(opts)
  opts = opts or {}
  if opts.exe_path then
    state.exe_path = opts.exe_path
  end
  start_process()
  return M
end

function M.call(module, method, params, opts)
  opts = opts or {}
  local wait_response = opts.wait_response == true
  local timeout = opts.timeout or 1500

  if not start_process() then
    return nil, 'process_not_running'
  end

  local id = state.next_id
  state.next_id = state.next_id + 1

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

function M.subscribe(event, handler)
  if not state.event_handlers[event] then
    state.event_handlers[event] = {}
  end
  table.insert(state.event_handlers[event], handler)
end

function M.unsubscribe(event, handler)
  local handlers = state.event_handlers[event]
  if not handlers then return end
  for i, h in ipairs(handlers) do
    if h == handler then
      table.remove(handlers, i)
      return
    end
  end
end

return M
