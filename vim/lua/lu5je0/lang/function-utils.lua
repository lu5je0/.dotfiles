local M = {}

M.debounce = function(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(function()
      fn(unpack(args))
    end))
  end
end

M.throttle = function(fn, ms)
    local timer = vim.uv.new_timer()
    local running = false
    return function(...)
        if running then
            return
        end
        running = true
        local args = {...}
        fn(unpack(args))
        timer:start(ms, 0, vim.schedule_wrap(function()
            running = false
        end))
    end
end

return M
