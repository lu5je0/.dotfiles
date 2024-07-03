local M = {}

local function detect_filetype()
  local lines = vim.api.nvim_buf_get_lines(0, 0, 100, false)
end

local uv = vim.uv

local function grepText(text, pattern)
  local stdin = uv.new_pipe()
  local stdout = uv.new_pipe()
  local stderr = uv.new_pipe()

  local handle, pid = uv.spawn("grep", {
    args = {'He'},
    stdio = { stdin, stdout, stderr }
  }, function(code, signal) -- on exit print("exit code", code) print("exit signal", signal)
  end)

  print("process opened", handle, pid)

  uv.write(stdin, "Hello World")

  uv.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then
      print("stdout chunk", stdout, data)
    end
  end)

  uv.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then
      print("stderr chunk", stderr, data)
    end
  end)

  uv.shutdown(stdin, function()
    print("stdin shutdown", stdin)
    uv.close(handle, function()
      print("process closed", handle, pid)
    end)
  end)
  print('end')
end

print(grepText('good\nhhh', 'g'))

return M
