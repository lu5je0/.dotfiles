local wezterm = require('wezterm');
local mux = wezterm.mux

local is_win = string.find(wezterm.target_triple, 'windows')
local is_mac = string.find(wezterm.target_triple, 'apple')

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
  if is_win then
    r.text_font = wezterm.font_with_fallback {
      { family = "JetBrainsMonoNL Nerd Font Mono", weight = "Medium", stretch = "Normal", style = "Normal" },
    }
    r.tab_bar_font_size = 10
  elseif is_mac then
    r.text_font = wezterm.font_with_fallback {
      { family = "JetBrainsMonoNL Nerd Font Mono", weight = "DemiBold", stretch = "Normal", style = "Normal" },
      { family = "PingFang SC",                    weight = "Medium",   stretch = "Normal", style = "Normal" }
    }
    r.tab_bar_font_size = 11.5
  end
  return r
end)()

local config = {
  color_scheme = "Gruvbox Dark (Gogh)",
  -- ./wezterm.exe ls-fonts --list-system
  font = font.text_font,
  window_frame = {
    -- The font used in the tab bar.
    -- Roboto Bold is the default; this font is bundled
    -- with wezterm.
    -- Whatever font is selected here, it will have the
    -- main font setting appended to it to pick up any
    -- fallback fonts you may have used there.
    font_size = font.tab_bar_font_size,
    -- The size of the font in the tab bar.
    -- Default to 10.0 on Windows but 12.0 on other systems
    -- The overall background color of the tab bar when
    -- the window is focused
    active_titlebar_bg = '#3C3C3C',
    -- The overall background color of the tab bar when
    -- the window is not focused
    inactive_titlebar_bg = '#3C3C3C',
  },
  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },
  max_fps = 120,
  -- window_background_opacity = 0.992,
  -- text_background_opacity = 0.9,
  colors = {
    tab_bar = {
      active_tab = {
        bg_color = "#3C3C3C",
        fg_color = "#c0c0c0",
        intensity = "Normal",
        underline = "None",
        italic = false,
        strikethrough = false,
      },
      inactive_tab = {
        bg_color = "#3C3C3C",
        fg_color = "#808080",
      },
      new_tab = {
        bg_color = "#3C3C3C",
        fg_color = "#aaaaaa",
      },
    },
  },
  font_size = (function()
    if is_mac then
      return 14.5
    elseif is_win then
      return 11.5
    end
  end)(),
}

if is_mac then
  -- tab bar在上面
  config.hide_tab_bar_if_only_one_tab = false
  config.use_fancy_tab_bar = true
  config.tab_bar_at_bottom = false
  config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
  config.integrated_title_button_style = "MacOsNative"
  -- config.integrated_title_button_style = "Windows"
  config.integrated_title_button_color = "auto"
  config.integrated_title_button_alignment = "Right"
end
if is_win then
  -- tab bar在下面
  -- config.hide_tab_bar_if_only_one_tab = true
  -- config.use_fancy_tab_bar = false
  -- config.tab_bar_at_bottom = true
  -- config.use_resize_increments = true

  config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
  config.integrated_title_button_style = "Windows"
  config.integrated_title_button_color = "auto"
  config.integrated_title_button_alignment = "Right"
end

config.cursor_thickness = '0.06cell'

config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 10000 }
config.keys = {
  { key = "o", mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Prev" } },
  { key = "o", mods = 'LEADER|CTRL',  action = wezterm.action { ActivatePaneDirection = "Prev" } },
  { key = 'c', mods = 'LEADER',       action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = 'l', mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Right" } },
  { key = 'n', mods = 'LEADER',       action = wezterm.action { ActivateTabRelative = 1 } },
  { key = 'h', mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Left" } },
  { key = 'j', mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Down" } },
  { key = 'k', mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Up" } },
  { key = 'l', mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Right" } },
  { key = 'x', mods = 'LEADER',       action = wezterm.action { CloseCurrentPane = { confirm = true } } },
  { key = 'g', mods = 'LEADER',       action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' } },
  { key = ' ', mods = 'LEADER',       action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|COMMANDS' } },
  { key = 'q', mods = 'LEADER',       action = wezterm.action_callback(function(win, pane) pane:move_to_new_tab() end) },
  { key = 'Q', mods = 'LEADER',       action = wezterm.action_callback(function(win, pane) pane:move_to_new_window() end) },
  { key = 'r', mods = 'LEADER',       action = wezterm.action.ReloadConfiguration },
  { key = '0', mods = 'LEADER',       action = wezterm.action.ShowDebugOverlay },
  { key = 't', mods = 'ALT',          action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = 't', mods = 'CMD',          action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = '%', mods = 'LEADER|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '"', mods = 'LEADER|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'b', mods = 'LEADER|CTRL',  action = wezterm.action.SendKey { key = 'b', mods = 'CTRL' } },

  { key = 'i', mods = 'CMD',          action = wezterm.action.SendKey { key = 'i', mods = 'ALT' } },
  { key = 'n', mods = 'CMD',          action = wezterm.action.SendKey { key = 'n', mods = 'ALT' } },
}

local tssh = (function()
  if is_mac then
    return 'tssh'
  elseif is_win then
    return '/mnt/c/Users/lu5je0/scoop/shims/tssh.exe'
  end
end)()
config.launch_menu = {}
local launch_menu = {
  {
    label = 'raider',
    args = { tssh, 'raider.665665.xyz' },
  },
  {
    label = 'sh-ubuntu',
    args = { tssh, 'sh.665665.xyz' },
  },
  {
    args = { 'wsl' },
    type = 'win',
  },
  {
    args = { '/mnt/c/Windows/System32/cmd.exe' },
    label = 'cmd',
    type = 'win',
  },
  {
    args = { '/mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe' },
    label = 'powershell',
    type = 'win',
  }
}
for _, launch in ipairs(launch_menu) do
  if not launch.type then
    table.insert(config.launch_menu, launch)
  elseif launch.type == 'win' and is_win then
    table.insert(config.launch_menu, launch)
  elseif launch.type == 'mac' and is_win then
    table.insert(config.launch_menu, launch)
  end
  launch.type = nil
end

-- config.skip_close_confirmation_for_processes_named = {
--   'bash',
--   'sh',
--   'zsh',
--   'fish',
--   'tmux',
--   'nu',
--   'cmd.exe',
--   'pwsh.exe',
--   'powershell.exe',
-- }
-- config.window_close_confirmation = 'NeverPrompt'

wezterm.on('gui-startup', function(cmd)
  if is_win then
    mux.spawn_window { width = 119, height = 45, cwd = cmd and cmd.cwd or nil }
  elseif is_mac then
    mux.spawn_window { width = 120, height = 42 }
  end
end)

if is_mac then
  local set_environment_variables = {
    PATH = '/opt/homebrew/bin:' .. os.getenv('PATH')
  }
  config.set_environment_variables = set_environment_variables
end

if is_win then
  config.default_domain = "WSL:Debian"
end

return config
