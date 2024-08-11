local wezterm = require('wezterm');
local mux = wezterm.mux

local uname = (function()
  if string.find(wezterm.target_triple, 'apple') then
    return "mac"
  elseif string.find(wezterm.target_triple, 'windows') then
    return "win"
  end
end)()

-- "Thin"
-- "ExtraLight"
-- "Light"
-- "DemiLight"
-- "Book"
-- "Regular"
-- "Medium"
-- "DemiBold"
-- "Bold"
-- "ExtraBold"
-- "Black"
-- "ExtraBlack".
local font = (function()
  local r = {}
  if uname == 'win' then
    r.text_font = wezterm.font("JetBrainsMonoNL Nerd Font Mono",
      { weight = "Medium", stretch = "Normal", style = "Normal" })
    r.tab_bar_font_size = 10.0
  elseif uname == 'mac' then
    r.text_font = wezterm.font("JetBrainsMonoNL NF", { weight = "Medium", stretch = "Normal", style = "Normal" })
    r.tab_bar_font_size = 11.5
  end
  return r
end)()

local config = {
  -- initial_cols = 155,
  -- initial_rows = 50,
  default_prog = (function(args)
    if uname == 'win' then
      return { "wsl", "--cd", "~" }
    end
  end)(),
  color_scheme = "Gruvbox Dark (Gogh)",
  -- use_resize_increments = true,
  -- ./wezterm.exe ls-fonts --list-system
  font = font.text_font,
  window_frame = {
    font_size = font.tab_bar_font_size,
    active_titlebar_bg = "#2C2E34",
    inactive_titlebar_bg = "#2C2E34",
  },
  hide_tab_bar_if_only_one_tab = true,
  use_fancy_tab_bar = false,
  tab_bar_at_bottom = true,
  max_fps = 120,
  -- window_decorations = "RESIZE",
  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },
  -- window_background_opacity = 0.992,
  -- text_background_opacity = 0.9,
  colors = {
    tab_bar = {
      active_tab = {
        bg_color = "#2C2E34",
        fg_color = "#c0c0c0",
        intensity = "Normal",
        underline = "None",
        italic = false,
        strikethrough = false,
      },
      inactive_tab = {
        bg_color = "#2C2E34",
        fg_color = "#808080",
      },
      new_tab = {
        bg_color = "#2C2E34",
        fg_color = "#808080",
      },
    },
  },
  font_size = (function()
    if uname == 'mac' then
      return 15
    elseif uname == 'win' then
      return 11.5
    end
  end)(),
}

-- config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 2000 }
-- config.keys = {
--   { key = "h", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Left" } },
--   { key = "l", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Right" } },
--   { key = "k", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Up" } },
--   { key = "j", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Down" } },
--   { key = "o", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Prev" } },
--   ---@diagnostic disable-next-line: unused-local
--   {
--     key = "v",
--     mods = "LEADER",
--     action = wezterm.action_callback(function(win, pane)
--       wezterm.log_info(wezterm.target_triple)
--     end)
--   },
--   -- { key = "o", mods = "LEADER", action = "ActivateLastTab" },
--   { key = "x",  mods = "LEADER", action = wezterm.action { CloseCurrentPane = { confirm = true } } },
--   { key = "\"", mods = "LEADER", action = wezterm.action { SplitVertical = { domain = "CurrentPaneDomain" } } },
--   { key = "c",  mods = "LEADER", action = wezterm.action { SpawnTab = "DefaultDomain" } },
--   { key = "n",  mods = "LEADER", action = wezterm.action { ActivateTabRelative = 1 } },
--   { key = "t",  mods = "ALT",    action = wezterm.action { SpawnTab = "DefaultDomain" } },
-- }

config.keys = {
  { key = '%', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '"', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = "o", mods = "CTRL|SHIFT", action = wezterm.action { ActivatePaneDirection = "Prev" } },
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = 'l', mods = 'CTRL|SHIFT', action = wezterm.action { ActivatePaneDirection = "Right" } },
  { key = 'h', mods = 'CTRL|SHIFT', action = wezterm.action { ActivatePaneDirection = "Left" } },
  { key = 'k', mods = 'CTRL|SHIFT', action = wezterm.action { ActivatePaneDirection = "Up" } },
  { key = 'j', mods = 'CTRL|SHIFT', action = wezterm.action { ActivatePaneDirection = "Down" } },
  { key = 'x', mods = 'CTRL|SHIFT', action = wezterm.action { CloseCurrentPane = { confirm = true } } }
}

wezterm.on('gui-startup', function(cmd)
  if cmd then
    mux.spawn_window { width = 119, height = 45, args = { "wsl", "--cd", cmd.cwd } }
  else
    mux.spawn_window { width = 119, height = 45, args = { "wsl", "--cd", "~" } }
  end
end)

return config
