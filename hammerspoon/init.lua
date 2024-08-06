---@diagnostic disable: undefined-global

hs.hotkey.bind({ "ctrl", "option" }, "R", function()
  hs.reload()
end)

-- 切换窗口最大化和恢复原始大小
local function toggleMaximized()
  local win = hs.window.focusedWindow()
  local frame = win:frame()
  local id = win:id()

  -- init table to save window state
  savedwin = savedwin or {}
  savedwin[id] = savedwin[id] or {}

  if (savedwin[id].maximized == nil or savedwin[id].maximized == false) then
    savedwin[id].frame = frame
    savedwin[id].maximized = true
    win:maximize()
  else
    savedwin[id].maximized = false
    win:setFrame(savedwin[id].frame)
  end
end

-- 设置当前窗口的大小
local function sizeFocusedWindow(mode)
  return function()
    local win = hs.window.focusedWindow()
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()
    
    -- hs.alert.show(table.concat({f.x, f.y, f.w, f.h}, ","))
    
    if mode == "Max" then
      f.x = max.x
      f.y = max.y
      f.w = max.w
      f.h = max.h
    elseif mode == "Center" then
      f.x = 190
      f.y = -960
      f.w = 1021
      f.h = 843
    elseif mode == "Half Left" then
      f.x = max.x
      f.y = max.y
      f.w = max.w / 2
      f.h = max.h
    elseif mode == "Half Right" then
      f.x = max.x + max.w / 2
      f.y = max.y
      f.w = max.w / 2
      f.h = max.h
    end

    win:setFrame(f, 0) -- 0 取消动画
  end
end

-- bind hotkey
hs.hotkey.bind({ "ctrl", "option" }, 'n', function()
  -- Get the focused window, its window frame dimensions, its screen frame dimensions,
  -- and the next screen's frame dimensions.
  local focusedWindow = hs.window.focusedWindow()
  local focusedScreenFrame = focusedWindow:screen():frame()
  local nextScreenFrame = focusedWindow:screen():next():frame()
  local windowFrame = focusedWindow:frame()

  -- Calculate the coordinates of the window frame in the next screen and retain aspect ratio
  windowFrame.x = ((((windowFrame.x - focusedScreenFrame.x) / focusedScreenFrame.w) * nextScreenFrame.w) + nextScreenFrame.x)
  windowFrame.y = ((((windowFrame.y - focusedScreenFrame.y) / focusedScreenFrame.h) * nextScreenFrame.h) + nextScreenFrame.y)
  windowFrame.h = ((windowFrame.h / focusedScreenFrame.h) * nextScreenFrame.h)
  windowFrame.w = ((windowFrame.w / focusedScreenFrame.w) * nextScreenFrame.w)

  -- Set the focused window's new frame dimensions
  focusedWindow:setFrame(windowFrame, 0)
  
  -- -- get the focused window
  -- local win = hs.window.focusedWindow()
  -- -- get the screen where the focused window is displayed, a.k.a. current screen
  -- local screen = win:screen()
  -- -- compute the unitRect of the focused window relative to the current screen
  -- -- and move the window to the next screen setting the same unitRect 
  -- win:move(win:frame():toUnitRect(screen:frame()), screen:next(), true, 0)
end)

hs.hotkey.bind({ "ctrl", "option" }, "H", sizeFocusedWindow('Half Left'))
hs.hotkey.bind({ "ctrl", "option" }, "J", sizeFocusedWindow('Center'))
-- hs.hotkey.bind({ "ctrl", "option" }, "J", toggleMaximized)
hs.hotkey.bind({ "ctrl", "option" }, "K", sizeFocusedWindow('Max'))
hs.hotkey.bind({ "ctrl", "option" }, "L", sizeFocusedWindow('Half Right'))

hs.alert.show("配置文件已经重新加载！ ")
