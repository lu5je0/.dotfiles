local M = {}

function M.create(render)
  local timer = vim.uv.new_timer()
  local idle_delay = 80
  local moving = false

  local function close()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end

  local function request()
    if not timer then
      return
    end

    if not moving then
      moving = true
      render()
    end

    timer:stop()
    timer:start(idle_delay, 0, vim.schedule_wrap(function()
      moving = false
      render()
    end))
  end

  return {
    request = request,
    close = close,
  }
end

return M
