local M = {}

local STD_PATH = vim.fn.stdpath('config')
local state = {
    job_id = nil,
    exe_path = STD_PATH .. '/lib/ime_control.exe',
    is_running = false,
}

--- 向后台进程发送命令的内部函数
-- @param cmd (string) 要发送的命令 (例如 "normal" 或 "insert")
local function send_command(cmd)
    if not state.job_id or not state.is_running then
        -- 如果进程未运行，静默失败，避免在快速切换时弹出恼人的错误信息
        return
    end
    -- 通过 Neovim 的 channel 发送命令到子进程的 stdin
    -- 注意：必须在命令后加上换行符 '\n' 来模拟回车
    vim.fn.chansend(state.job_id, cmd .. "\n")
end

--- 启动后台进程
local function start_job()
    -- 如果已在运行，则无需操作
    if state.is_running and state.job_id then
        return
    end

    -- 检查可执行文件路径是否有效
    if not state.exe_path or vim.fn.executable(state.exe_path) == 0 then
        vim.notify("找不到 ime_control.exe，请检查配置路径", vim.log.levels.ERROR, { title = "IME Control" })
        return
    end

    -- 使用 jobstart 启动 C++ 程序，并使其进入交互模式 (-i)
    local job_id = vim.fn.jobstart({ state.exe_path, "-i" }, {
        -- 我们不需要处理 stdout/stderr，因为程序被设计为静默运行
        -- 只在进程退出时打印一个警告，以防意外关闭
        on_exit = function(_, code)
            -- 如果 job_id 仍然存在 (表示不是我们主动停止的)，说明是意外退出
            if state.job_id then
                vim.notify("IME 控制进程意外退出，退出码: " .. tostring(code), vim.log.levels.WARN, { title = "IME Control" })
                state.is_running = false
                state.job_id = nil
            end
        end,
        pty = false,
    })

    if job_id and job_id > 0 then
        state.job_id = job_id
        state.is_running = true
    else
        vim.notify("启动 IME 控制进程失败", vim.log.levels.ERROR, { title = "IME Control" })
    end
end

--- 公开的API ---

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

    -- 启动后台服务
    start_job()
    return M
end

return M
