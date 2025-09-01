local M = {}

-- 抽象窗口调整 repeat 支持
local mappings = {
  -- 键名, 操作命令, repeat触发键标识
  { trigger = '<C-w><', repeat_key = '<', cmd = 'vertical resize -1' },
  { trigger = '<C-w>>', repeat_key = '>', cmd = 'vertical resize +1' },
  { trigger = '<C-w>+', repeat_key = '+', cmd = 'resize +1' },
  { trigger = '<C-w>-', repeat_key = '-', cmd = 'resize -1' },
}

-- 用于存储每个调整方向的状态和计时器
local resize_states = {
  active = false,
  timer = nil
}

local function delay_resize_window_timer()
    local timer = resize_states.timer
    if not timer then
      timer = vim.uv.new_timer()
      resize_states.timer = timer
    end

    timer:stop()
    timer:start(2000, 0, vim.schedule_wrap(function()
      resize_states.active = false
    end))
end

local function trigger_resize_window_mapping(cmd, repeat_key)
  return function()
    -- 执行窗口命令
    vim.cmd(cmd)
    resize_states.active = true
    delay_resize_window_timer()
  end
end

local function resize_window(cmd, repeat_key)
  return function()
    if resize_states.active then
      vim.cmd(cmd)
      delay_resize_window_timer()
    else
      require('lu5je0.core.keys').feedkey(repeat_key, 'n')
    end
  end
end

M.setup = function()
  -- 注册所有“方向”的 trigger和repeat mapping
  for _, mapping in ipairs(mappings) do
    -- 1. 第一次按下，比如 <C-w><
    vim.api.nvim_set_keymap('n', mapping.trigger, '', {
      noremap = true,
      callback = trigger_resize_window_mapping(mapping.cmd, mapping.repeat_key),
      desc = "Resize window with repeat: " .. mapping.cmd
    })
    -- 2. repeat键，比如 <, >, +, -，在持续期内触发
    vim.api.nvim_set_keymap('n', mapping.repeat_key, '', {
      noremap = true,
      callback = resize_window(mapping.cmd, mapping.repeat_key),
      desc = "Repeat window resize: " .. mapping.cmd
    })
  end
end

return M

