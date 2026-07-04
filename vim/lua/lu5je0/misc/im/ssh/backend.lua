-- SSH backend: proxies IME operations to the local tui-bridge daemon
-- via OSC 1337 SetUserVar escapes.
local M = {}

local function write(osc)
  if vim.fn.filewritable('/dev/fd/2') == 1 then
    return vim.fn.writefile({ osc }, '/dev/fd/2', 'b') == 0
  end
  return vim.fn.chansend(vim.v.stderr, osc) > 0
end

M.insert = function()
  write(string.format("\27]1337;SetUserVar=%s=%s\7", "tui_bridge", require('lu5je0.misc.base64').encode('{"id":1,"module":"ime","method":"insert","params":{}}')))
end

M.normal = function()
  write(string.format("\27]1337;SetUserVar=%s=%s\7", "tui_bridge", require('lu5je0.misc.base64').encode('{"id":1,"module":"ime","method":"normal","params":{}}')))
end

M.ascii_mode = function()
  M.normal()
end

M.setup = function()
  return M
end

return M
