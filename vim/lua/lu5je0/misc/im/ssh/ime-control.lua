local M = {}

local function write(osc)
  local success = false
  if vim.fn.filewritable('/dev/fd/2') == 1 then
    success = vim.fn.writefile({osc}, '/dev/fd/2', 'b') == 0
  else
    success = vim.fn.chansend(vim.v.stderr, osc) > 0
  end
  return success
end

M.insert = function()
  write(string.format("\27]1337;SetUserVar=%s=%s\7", "ime", require('lu5je0.misc.base64').encode("insert")))
end

M.normal = function()
  write(string.format("\27]1337;SetUserVar=%s=%s\7", "ime", require('lu5je0.misc.base64').encode("normal")))
end

M.switch_en = function()
  M.normal()
end

M.setup = function()
  return M
end

return M
