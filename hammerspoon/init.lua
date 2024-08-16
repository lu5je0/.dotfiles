---@diagnostic disable: undefined-global

local win_win = require('win_win')

hs.hotkey.bind({ "ctrl", "option" }, "R", function()
  hs.reload()
end)

local window_special_cases = {
  kitty = {
    center = function(max)
      return {
        x = max.x,
        y = max.y,
        w = 1021,
        h = 843
      }
    end,
    ["43_center"] = function(max)
      return {
        x = max.x,
        y = max.y,
        w = max.w * (3 / 4) - 20,
        h = max.h - 8
      }
    end
  },
  WezTerm = {
    center = function(max)
      return {
        x = 190,
        y = -960,
        w = 1021,
        h = 843
      }
    end,
    ["43_center"] = function(max)
      return {
        x = max.x,
        y = max.y,
        w = max.w * (3 / 4) - 20,
        h = max.h - 8
      }
    end
  },
  -- 你可以在这里添加其他应用程序的特殊处理逻辑
  -- exampleApp = {
  --   center = function(max) return { x = 100, y = 100, w = 800, h = 600 } end,
  --   ["43_center"] = function(max) return { x = max.x, y = max.y, w = max.w * 0.75, h = max.h } end
  -- }
}

local function size_focused_window(mode)
  return function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()

    local app_name = win:application():name()
    local appCases = window_special_cases[app_name]

    if appCases and appCases[mode] then
      local case = appCases[mode]
      if type(case) == "function" then
        f = case(max)
      else
        f = case
      end
      win:setFrame(f, 0)
      hs.window.focusedWindow():centerOnScreen(0)
      return
    end

    if mode == "maximize" then
      f.x = max.x
      f.y = max.y
      f.w = max.w
      f.h = max.h
    elseif mode == "center" then
      f.w = max.w / 1.4
      f.h = max.h / 1.1
      hs.window.focusedWindow():centerOnScreen(0)
      win:setFrame(f, 0)   -- 0 取消动画
      hs.window.focusedWindow():centerOnScreen(0)
      return
    elseif mode == "43_center" then
      f.x = max.x
      f.y = max.y
      f.w = max.w * (3 / 4)
      f.h = max.h
      win:setFrame(f, 0)
      hs.window.focusedWindow():centerOnScreen(0)
      return
    elseif mode == "halfleft" then
      f.x = max.x
      f.y = max.y
      f.w = max.w / 2
      f.h = max.h
    elseif mode == "halfright" then
      f.x = max.x + max.w / 2
      f.y = max.y
      f.w = max.w / 2
      f.h = max.h
    end

    win:setFrame(f, 0)   -- 0 取消动画
  end
end

-- bind hotkey
hs.hotkey.bind({ "ctrl", "option" }, "J", size_focused_window('center'))

hs.hotkey.bind({ "ctrl", "option" }, "H", size_focused_window('halfleft'))
hs.hotkey.bind({ "ctrl", "option" }, "L", size_focused_window('halfright'))
hs.hotkey.bind({ "ctrl", "option" }, "I", size_focused_window('43_center'))
hs.hotkey.bind({ "ctrl", "option" }, "K", size_focused_window('maximize'))
hs.hotkey.bind({ "ctrl", "option" }, 'N', function()
  local win = hs.window.focusedWindow()
  local f = win:frame()
  local screen = win:screen()
  local max = screen:frame()

  local width_rate = f.w / max.w
  win_win:moveToScreen("next")

  if width_rate > 0.98 then
    size_focused_window('maximize')()
  end
end)

-- hs.hotkey.bind({ "ctrl", "option" }, "R", spoon.WinWin:redo)

-- 禁止粘贴
-- hs.hotkey.bind({ 'cmd', 'shift' }, 'v', function() hs.eventtap.keyStrokes(hs.pasteboard.getContents()) end)

hs.alert.show("配置文件已经重新加载！ ")
