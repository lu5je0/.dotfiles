local M = {}

local uv = vim.uv

local close_handle = function(handle)
  if handle and not handle:is_closing() then handle:close() end
end

M.runProcessAsync = function(cmd, args, stdin_lines, handler)
  local output = ""
  local stderr_output = ""

  local handle_stdout = vim.schedule_wrap(function(err, chunk)
    if err then error("stdout error: " .. err) end

    if chunk then output = output .. chunk end
    if not chunk then
      handler(output, stderr_output ~= "" and stderr_output or nil)
    end
  end)

  local handle_stderr = function(err, chunk)
    if err then error("stderr error: " .. err) end
    if chunk then stderr_output = stderr_output .. chunk end
  end

  local stdin = uv.new_pipe(true)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local handle
  handle = uv.spawn(cmd, { args = args, stdio = { stdin, stdout, stderr } }, function()
    stdout:read_stop()
    stderr:read_stop()

    close_handle(stdin)
    close_handle(stdout)
    close_handle(stderr)
    close_handle(handle)
  end)

  uv.read_start(stdout, handle_stdout)
  uv.read_start(stderr, handle_stderr)
  
  stdin_lines = vim.tbl_map(function(line)
    return line .. '\n'
  end, stdin_lines)
  stdin:write(stdin_lines, function() stdin:close() end)
end

return M
