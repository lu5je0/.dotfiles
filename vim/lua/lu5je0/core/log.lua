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

function M.error(msg)
  init_log()
  
  print(msg)
  log:write(msg)
  log:flush()
end

function M.info(msg)
  init_log()
  
  print(msg)
  log:write(msg)
  log:flush()
end

function M.debug(msg)
  init_log()
  
  print(msg)
  log:write(msg)
  log:flush()
end

function M.set_level(level)
  M.level = level
end


return M
