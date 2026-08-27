---@diagnostic disable: undefined-global

hs.hotkey.bind({ "ctrl", "option" }, "R", function()
  hs.reload()
end)

local config_path = hs.configdir .. "/window_sizes.json"

-- spec: 数字表示绝对像素; {ratio, offset} 表示 max_dim * ratio + offset
local function resolve_dim(spec, max_dim)
  if type(spec) == "number" then
    return spec
  end
  return max_dim * (spec.ratio or 1) + (spec.offset or 0)
end

local function apply_size(win, entry, max, mode)
  local f = win:frame()
  f.w = resolve_dim(entry.w, max.w)
  f.h = resolve_dim(entry.h, max.h)

  if mode == "maximize" then
    f.x, f.y = max.x, max.y
  elseif mode == "halfleft" then
    f.x, f.y = max.x, max.y
  elseif mode == "halfright" then
    f.x, f.y = max.x + max.w / 2, max.y
  else
    f.x = max.x + (max.w - f.w) / 2
    f.y = max.y + (max.h - f.h) / 2
  end

  win:setFrame(f, 0)   -- 0 取消动画
end

local function size_focused_window(mode)
  return function()
    local win = hs.window.focusedWindow()
    local screen = win:screen()
    local max = screen:frame()

    local app_name = win:application():name()
    print(app_name)

    local config, err = hs.json.read(config_path)
    if not config then
      hs.alert.show("window_sizes.json 解析失败: " .. tostring(err))
      return
    end

    local entry
    local profile_name = config.apps and config.apps[app_name]
    local profile = profile_name and config.profiles and config.profiles[profile_name]
    if profile and profile[mode] then
      local screen_type = screen:id() == 1 and "main" or "external"
      entry = profile[mode][screen_type]
    end
    if not entry then
      entry = config.defaults and config.defaults[mode]
    end
    if not entry then
      hs.alert.show("window_sizes.json 中未找到 " .. app_name .. " / " .. mode .. " 的配置")
      return
    end

    apply_size(win, entry, max, mode)
  end
end

-- bind hotkey
hs.hotkey.bind({ "ctrl", "option" }, "J", size_focused_window('center_j'))

hs.hotkey.bind({ "ctrl", "option" }, "H", size_focused_window('halfleft'))
hs.hotkey.bind({ "ctrl", "option" }, "L", size_focused_window('halfright'))
hs.hotkey.bind({ "ctrl", "option" }, "I", size_focused_window('center_i'))
hs.hotkey.bind({ "ctrl", "option" }, "K", size_focused_window('maximize'))
hs.hotkey.bind({ "ctrl", "option" }, "M", function()
  local win = hs.window.focusedWindow()
  win:minimize()
end)
hs.hotkey.bind({ "ctrl", "option" }, 'N', function()
  local win_win = require('win_win')
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

-- 切换虚拟桌面：模拟系统默认的 Ctrl+Left/Right
hs.hotkey.bind({ "ctrl", "option" }, "Left", function()
  hs.eventtap.keyStroke({ "ctrl" }, "left")
end)
hs.hotkey.bind({ "ctrl", "option" }, "Right", function()
  hs.eventtap.keyStroke({ "ctrl" }, "right")
end)

-- 禁止粘贴
-- hs.hotkey.bind({ 'cmd', 'shift' }, 'v', function() hs.eventtap.keyStrokes(hs.pasteboard.getContents()) end)

hs.alert.show("配置文件已经重新加载！ ")
