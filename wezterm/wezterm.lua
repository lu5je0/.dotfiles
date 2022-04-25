local wezterm = require('wezterm');

local uname = (function()
  if string.find(wezterm.target_triple, 'apple') then
    return "mac"
  elseif string.find(wezterm.target_triple, 'windows') then
    return "win"
  end
end)()

local font = (function()
  local r = {}
  if uname == 'win' then
    r.text_font = wezterm.font("JetBrainsMonoNL NF", { weight = "Medium", stretch = "Normal", style = "Normal" })
    r.tab_bar_font_size = 10.0
  elseif uname == 'mac' then
    r.text_font = wezterm.font("JetBrainsMono Nerd Font Mono", { weight = "Bold", stretch = "Normal", style = "Normal" })
    r.tab_bar_font_size = 11.5
  end
  return r
end)()

local config = {
  initial_cols = 155,
  initial_rows = 50,
  default_prog = (function()
    if uname == 'win' then
      return { "wsl" }
    end
  end)(),
  color_scheme = "Gruvbox Dark",
  use_resize_increments = true,
  -- ./wezterm.exe ls-fonts --list-system
  font = font.text_font,
  -- hide_tab_bar_if_only_one_tab = true,
  window_frame = {
    font_size = font.tab_bar_font_size,
    active_titlebar_bg = "#2C2E34",
    inactive_titlebar_bg = "#2C2E34",
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
      return 10.5
    end
  end)(),
  leader = { key = "a", mods = "CTRL", timeout_milliseconds = 2000 },
  keys = {
    { key = "%", mods = "LEADER", action = wezterm.action { SplitHorizontal = { domain = "CurrentPaneDomain" } } },
    { key = "h", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Left" } },
    { key = "l", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Right" } },
    { key = "k", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Up" } },
    { key = "j", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Down" } },
    { key = "o", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Prev" } },
    ---@diagnostic disable-next-line: unused-local
    { key = "v", mods = "LEADER", action = wezterm.action_callback(function(win, pane)
      wezterm.log_info(wezterm.target_triple)
    end) },
    -- { key = "o", mods = "LEADER", action = "ActivateLastTab" },
    { key = "x", mods = "LEADER", action = wezterm.action { CloseCurrentPane = { confirm = true } } },
    { key = "\"", mods = "LEADER", action = wezterm.action { SplitVertical = { domain = "CurrentPaneDomain" } } },
    { key = "c", mods = "LEADER", action = wezterm.action { SpawnTab = "DefaultDomain" } },
    { key = "n", mods = "LEADER", action = wezterm.action { ActivateTabRelative = 1 } },
    { key = "t", mods = "ALT", action = wezterm.action { SpawnTab = "DefaultDomain" } },
  },
  -- use_fancy_tab_bar = false,
  window_decorations = "RESIZE",
  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },
}

return config
