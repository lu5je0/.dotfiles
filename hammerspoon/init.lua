---@diagnostic disable: undefined-global

local win_win = require('win_win')

hs.hotkey.bind({ "ctrl", "option" }, "R", function()
  hs.reload()
end)

-- 设置当前窗口的大小
local function sizeFocusedWindow(mode)
  return function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    if mode == "Center" then
      if tostring(win:application()):find('kitty') then
        f.x = 190
        f.y = -960
        f.w = 1021
        f.h = 843
      else
        f.w = max.w / 1.4
        f.h = max.h / 1.2
        hs.window.focusedWindow():centerOnScreen(0)
        win:setFrame(f, 0) -- 0 取消动画
        hs.window.focusedWindow():centerOnScreen(0)
        return
      end
    end

    win:setFrame(f, 0) -- 0 取消动画
  end
end

-- bind hotkey
hs.hotkey.bind({ "ctrl", "option" }, "J", sizeFocusedWindow('Center'))

hs.hotkey.bind({ "ctrl", "option" }, "H", function() win_win:moveAndResize('halfleft') end)
hs.hotkey.bind({ "ctrl", "option" }, "L", function() win_win:moveAndResize('halfright') end)
hs.hotkey.bind({ "ctrl", "option" }, "K", function() win_win:moveAndResize('maximize') end)
hs.hotkey.bind({ "ctrl", "option" }, "U", function() win_win:undo() end)
hs.hotkey.bind({ "ctrl", "option" }, 'N', function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()
  
  local width_rate = f.w / max.w
  win_win:moveToScreen("next")
  
  if width_rate > 0.98 then
    win_win:moveAndResize('maximize')
  end
end)

-- hs.hotkey.bind({ "ctrl", "option" }, "R", spoon.WinWin:redo)

-- 禁止粘贴
-- hs.hotkey.bind({ 'cmd', 'shift' }, 'v', function() hs.eventtap.keyStrokes(hs.pasteboard.getContents()) end)

hs.alert.show("配置文件已经重新加载！ ")
