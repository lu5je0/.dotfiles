local M = {}

M.level = 'INFO'

local log = nil

local init = false
local function init_log()
  if init then
    return
  end
  log = io.open('/tmp/neovim.lu5je0.log', 'a')
  init = true
end

M.error = function(msg)
  init_log()
  
  print(msg)
  log:write(msg)
  log:flush()
end

M.info = function(msg)
  init_log()
  
  print(msg)
  log:write(msg)
  log:flush()
end

M.debug = function(msg)
  init_log()
  
  print(msg)
  log:write(msg)
  log:flush()
end

M.set_level = function(level)
  M.level = level
end


return M
