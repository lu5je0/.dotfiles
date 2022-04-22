local wezterm = require('wezterm');

return {
  initial_cols = 155,
  initial_rows = 45,
  -- default_prog = { "wsl" },
  color_scheme = "Gruvbox Dark",
  use_resize_increments = true,
  -- ./wezterm.exe ls-fonts --list-system
  font = wezterm.font("JetBrainsMono Nerd Font Mono", { weight = "Bold", stretch = "Normal", style = "Normal" }),
  hide_tab_bar_if_only_one_tab = true,
  window_frame = {
    -- The font used in the tab bar.
    -- Roboto Bold is the default; this font is bundled
    -- with wezterm.
    -- Whatever font is selected here, it will have the
    -- main font setting appended to it to pick up any
    -- fallback fonts you may have used there.
    -- font = wezterm.font({family="Roboto", weight="Bold"}),

    -- The size of the font in the tab bar.
    -- Default to 10. on Windows but 12.0 on other systems
    font_size = 8.0,
    -- The overall background color of the tab bar when
    -- the window is focused
    active_titlebar_bg = "#333333",
    -- The overall background color of the tab bar when
    -- the window is not focused
    inactive_titlebar_bg = "#333333",
  },
  font_size = 15,
  leader = { key = "b", mods = "CTRL", timeout_milliseconds = 2000 },
  keys = {
    { key = "%", mods = "LEADER", action = wezterm.action { SplitHorizontal = { domain = "CurrentPaneDomain" } } },
    { key = "h", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Left" } },
    { key = "l", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Right" } },
    { key = "k", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Up" } },
    { key = "j", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Down" } },
    { key = "o", mods = "LEADER", action = wezterm.action { ActivatePaneDirection = "Prev" } },
    -- { key = "o", mods = "LEADER", action = "ActivateLastTab" },
    { key = "x", mods = "LEADER", action = wezterm.action { CloseCurrentPane = { confirm = true } } },
    { key = "\"", mods = "LEADER", action = wezterm.action { SplitVertical = { domain = "CurrentPaneDomain" } } },
    { key = "c", mods = "LEADER", action = wezterm.action { SpawnTab = "DefaultDomain" } },
    { key = "n", mods = "LEADER", action = wezterm.action { ActivateTabRelative = 1 } },
    { key = "t", mods = "ALT", action = wezterm.action { SpawnTab = "DefaultDomain" } },
  },
  -- use_fancy_tab_bar = false,
  -- window_decorations = "RESIZE",
  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  }
}
