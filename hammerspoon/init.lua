---@diagnostic disable: undefined-global

hs.hotkey.bind({ "ctrl", "option" }, "R", function()
  hs.reload()
end)

local config_path = os.getenv("HOME") .. "/.dotfiles/wm/layout.jsonc"

-- 剥离 JSONC 注释（// 与 /* */），字符串字面量内的原样保留
local function strip_comments(text)
  local out = {}
  local i, n = 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c == '"' then
      local j = i
      i = i + 1
      while i <= n do
        local d = text:sub(i, i)
        if d == "\\" then
          i = i + 2
        elseif d == '"' then
          i = i + 1
          break
        else
          i = i + 1
        end
      end
      out[#out + 1] = text:sub(j, i - 1)
    elseif c == "/" and i < n and text:sub(i + 1, i + 1) == "/" then
      local e = text:find("\n", i + 2, true)
      i = e or (n + 1)
    elseif c == "/" and i < n and text:sub(i + 1, i + 1) == "*" then
      local e = text:find("*/", i + 2, true)
      i = e and (e + 2) or (n + 1)
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function read_config()
  local f = io.open(config_path, "r")
  if not f then
    return nil, "无法打开 " .. config_path
  end
  local text = f:read("*a")
  f:close()
  local ok, config, err = pcall(hs.json.decode, strip_comments(text))
  if not ok then
    return nil, tostring(config)
  end
  if not config then
    return nil, tostring(err)
  end
  return config
end

-- spec: 数字表示绝对像素; {ratio, offset} 表示 max_dim * ratio + offset
local function resolve_dim(spec, max_dim)
  if type(spec) == "number" then
    return spec
  end
  return max_dim * (spec.ratio or 1) + (spec.offset or 0)
end

-- spec: {align, offset}，返回相对可用区原点的坐标；align 缺省 center
local function align_pos(axis, spec, size, max_dim)
  local align = spec.align or "center"
  local offset = spec.offset or 0
  if axis == "x" then
    if align == "left" then
      return offset
    elseif align == "right" then
      return max_dim - size - offset
    end
  else
    if align == "top" then
      return offset
    elseif align == "bottom" then
      return max_dim - size - offset
    end
  end
  return (max_dim - size) / 2 + offset
end

-- 字段可为字符串或数组，缺省即通配
local function field_matches(spec, value)
  if spec == nil then
    return true
  end
  if type(spec) == "string" then
    return spec == value
  end
  for _, item in ipairs(spec) do
    if item == value then
      return true
    end
  end
  return false
end

local function rule_matches(rule, wm, app, screen)
  return field_matches(rule.wm, wm)
    and field_matches(rule.app, app)
    and field_matches(rule.screen, screen)
end

-- rules 数组从前往后，取第一条字段全匹配且提供该 mode 的规则
local function find_entry(config, wm, app, screen, mode)
  for _, rule in ipairs(config.rules or {}) do
    if rule_matches(rule, wm, app, screen) and rule.size and rule.size[mode] then
      return rule.size[mode]
    end
  end
  return nil
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
    f.x = max.x + (entry.x and align_pos("x", entry.x, f.w, max.w) or (max.w - f.w) / 2)
    f.y = max.y + (entry.y and align_pos("y", entry.y, f.h, max.h) or (max.h - f.h) / 2)
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

    local config, err = read_config()
    if not config then
      hs.alert.show("wm/layout.jsonc 解析失败: " .. tostring(err))
      return
    end

    local screen_type = screen:id() == 1 and "main" or "external"
    local entry = find_entry(config, "hammerspoon", app_name, screen_type, mode)
    if not entry then
      hs.alert.show("wm/layout.jsonc 中未找到 " .. app_name .. " / " .. mode .. " 的配置")
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
hs.hotkey.bind({ "ctrl", "option" }, "O", function()
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

local function adjacent_space(offset, screen)
  local screen_id = screen:getUUID()
  local active_space = hs.spaces.activeSpaces()[screen_id]
  local spaces = {}
  for _, space_id in ipairs(hs.spaces.spacesForScreen(screen_id) or {}) do
    if hs.spaces.spaceType(space_id) == "user" then
      spaces[#spaces + 1] = space_id
    end
  end

  for index, space_id in ipairs(spaces) do
    if space_id == active_space then
      return spaces[(index - 1 + offset) % #spaces + 1]
    end
  end
  return nil
end

local function switch_space(offset)
  local win = hs.window.focusedWindow()
  local screen = win and win:screen() or hs.screen.mainScreen()
  local target = adjacent_space(offset, screen)
  if target then
    hs.spaces.gotoSpace(target)
  end
end

local function move_window_to_space(offset)
  local win = hs.window.focusedWindow()
  if not win then
    return
  end
  local target = adjacent_space(offset, win:screen())
  if target then
    hs.spaces.moveWindowToSpace(win:id(), target)
    hs.spaces.gotoSpace(target)
  end
end

hs.hotkey.bind({ "ctrl", "option" }, "N", function()
  switch_space(1)
end)
hs.hotkey.bind({ "ctrl", "option" }, "P", function()
  switch_space(-1)
end)
hs.hotkey.bind({ "ctrl", "option", "shift" }, "N", function()
  move_window_to_space(1)
end)
hs.hotkey.bind({ "ctrl", "option", "shift" }, "P", function()
  move_window_to_space(-1)
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
