local M = {}

local STD_PATH = vim.fn.stdpath('config')

-- 状态管理
local state = {
  process_handle = nil, -- 进程句柄
  stdin_pipe = nil,     -- 标准输入管道
  exe_path = STD_PATH .. '/lib/ime_control',
  is_running = false,
}

--- 向后台进程发送命令的内部函数
-- @param cmd (string) 要发送的命令 (例如 "normal" 或 "insert")
local function send_command(cmd)
  -- 检查进程和 stdin 管道是否都准备就绪
  if not state.is_running or not state.stdin_pipe or state.stdin_pipe:is_closing() then
    -- 如果进程未运行或管道已关闭，静默失败
    return
  end

  -- 通过 luv 的 pipe:write() 方法向子进程的 stdin 写入数据
  -- 注意：同样需要在命令后加上换行符 '\n'
  state.stdin_pipe:write(cmd .. "\n", function(err)
    if err then
      -- 写入失败时可以选择性地记录日志，但通常可以忽略
      -- vim.notify("向 IME 进程发送命令失败: " .. err, vim.log.levels.WARN)
    end
  end)
end

--- 启动后台进程
local function start_process()
  -- 如果已在运行，则无需操作
  if state.is_running and state.process_handle then
    return
  end

  -- 检查可执行文件路径是否有效
  if not state.exe_path or vim.fn.executable(state.exe_path) == 0 then
    vim.notify("找不到 ime_control，可执行文件路径无效", vim.log.levels.ERROR, { title = "IME Control" })
    return
  end

  -- 为子进程创建一个 stdin 管道
  local stdin = vim.uv.new_pipe(false) -- `false` 表示这不是一个 IPC 管道

  -- 使用 vim.uv.spawn 启动 C++ 程序
  local handle, pid = vim.uv.spawn(state.exe_path, {
    args = { "-i" }, -- 传递交互模式参数
    stdio = { stdin, nil, nil }, -- 将 stdin 重定向到我们创建的管道，stdout 和 stderr 忽略
  }, function(code, signal)
    -- on_exit 回调函数
    -- 清理资源
    if not stdin:is_closing() then
      stdin:close()
    end

    -- 如果 handle 仍然存在 (表示不是我们主动停止的)，说明是意外退出
    if state.process_handle then
      vim.schedule(function()
        vim.notify("IME 控制进程意外退出，退出码: " .. tostring(code) .. ", 信号: " .. tostring(signal), vim.log.levels.WARN, { title = "IME Control" })
      end)
    end

    -- 重置状态
    state.is_running = false
    state.process_handle = nil
    state.stdin_pipe = nil
  end)

  if handle and pid then
    -- 启动成功
    state.process_handle = handle
    state.stdin_pipe = stdin
    state.is_running = true
  else
    -- 启动失败
    vim.notify("启动 IME 控制进程失败", vim.log.levels.ERROR, { title = "IME Control" })
    -- 确保清理失败时创建的管道
    if not stdin:is_closing() then
      stdin:close()
    end
  end
end

-- 切换到 Normal 模式 (切换为英文并记住之前状态)
function M.normal()
  send_command("normal")
end

-- 切换到 Insert 模式 (恢复之前记住的状态)
function M.insert()
  send_command("insert")
end

--- 模块配置入口 ---
-- @param opts table | nil 配置选项，例如 { exe_path = "..." }
function M.setup(opts)
  opts = opts or {}
  if opts.exe_path and opts.exe_path ~= '' then
    state.exe_path = opts.exe_path
  end

  -- 启动后台服务
  start_process()
  return M
end

return M
