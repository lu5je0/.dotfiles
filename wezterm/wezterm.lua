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

local function basename(s)
  return string.gsub(s, '(.*[/\\])(.*)', '%2')
end

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
  { key = "o",      mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Prev" } },
  { key = "o",      mods = 'LEADER|CTRL',  action = wezterm.action { ActivatePaneDirection = "Prev" } },
  { key = 'c',      mods = 'LEADER',       action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = 'l',      mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Right" } },
  { key = 'n',      mods = 'LEADER',       action = wezterm.action { ActivateTabRelative = 1 } },
  { key = 'h',      mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Left" } },
  { key = 'j',      mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Down" } },
  { key = 'k',      mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Up" } },
  { key = 'l',      mods = 'LEADER',       action = wezterm.action { ActivatePaneDirection = "Right" } },
  { key = 'x',      mods = 'LEADER',       action = wezterm.action { CloseCurrentPane = { confirm = true } } },
  { key = 'g',      mods = 'LEADER',       action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' } },
  { key = ' ',      mods = 'LEADER',       action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|COMMANDS' } },
  {
    key = 'q',
    mods = 'LEADER',
    action = wezterm.action_callback(function(win, pane)
      local tab = pane:move_to_new_tab()
      tab:activate()
    end)
  },
  {
    key = 'u',
    mods = 'LEADER',
    action = wezterm.action { PaneSelect = { mode = "SwapWithActiveKeepFocus" } },
    -- action = wezterm.action_callback(function(win, pane)
    --   local tab = win:active_tab()
    --   local next_pane = tab:get_pane_direction("Right")
    --   if next_pane then
    --     tab.swap_active_with_index(next_pane, true)
    --   end
    -- end)
  },
  {
    key = 'm',
    mods = 'LEADER',
    action = wezterm.action_callback(function(win, cur_pane)
      local choices = {}
      local cur_tab_id = cur_pane:tab():tab_id()
      
      local tabs_with_info = win:mux_window():tabs_with_info()
      for _, tab_info in ipairs(tabs_with_info) do
        local tab = tab_info.tab
        if tab:tab_id() ~= cur_tab_id then
          local panes_with_info = tab:panes_with_info()
          for _, pane_info in ipairs(panes_with_info) do
            local pane = pane_info.pane
            table.insert(choices, { label = tostring(tab_info.index + 1) .. '-' .. tostring(pane_info.index + 1) .. ':' .. basename(pane:get_foreground_process_info().executable), id = tostring(pane:pane_id()) })
          end
        end
      end
      wezterm.log_info(choices)
      
      -- win:perform_action(
      --   wezterm.action.PaneSelect {
      --     alphabet = '1234567890',
      --     -- show_pane_ids = true
      --   },
      --   cur_pane
      -- )
      win:perform_action(
        wezterm.action.InputSelector {
          action = wezterm.action_callback(function(window, cur_pane, id, label, pane_id)
            if not id and not label then
              wezterm.log_info 'cancelled'
            else
              local wezterm_path
              if is_win then
                wezterm_path = 'wezterm.exe'
              else
                wezterm_path = '/opt/homebrew/bin/wezterm'
              end
              wezterm.run_child_process { wezterm_path, 'cli', 'split-pane', '--move-pane-id', id, '--horizontal' }
            end
          end),
          title = 'choose pane',
          choices = choices,
          alphabet = 'abcdefghijk',
        },
        cur_pane
      )
    end)
  },
  { key = 'Q',      mods = 'LEADER',       action = wezterm.action_callback(function(win, pane) pane:move_to_new_window() end) },
  { key = 'r',      mods = 'LEADER',       action = wezterm.action.ReloadConfiguration },
  { key = '0',      mods = 'LEADER',       action = wezterm.action.ShowDebugOverlay },
  { key = 't',      mods = 'ALT',          action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = 't',      mods = 'CMD',          action = wezterm.action { SpawnTab = "DefaultDomain" } },
  { key = '%',      mods = 'LEADER|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '"',      mods = 'LEADER|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'b',      mods = 'LEADER|CTRL',  action = wezterm.action.SendKey { key = 'b', mods = 'CTRL' } },
  { key = 'Escape', mods = 'LEADER',       action = wezterm.action.ActivateCopyMode },
  { key = 'i',      mods = 'CMD',          action = wezterm.action.SendKey { key = 'i', mods = 'ALT' } },
  { key = 'n',      mods = 'CMD',          action = wezterm.action.SendKey { key = 'n', mods = 'ALT' } },
}
for i = 1, 9 do
  table.insert(config.keys, { key = tostring(i), mods = 'LEADER', action = wezterm.action.ActivateTab(i - 1) })
end

local copy_mode = wezterm.gui.default_key_tables().copy_mode
table.insert(copy_mode, { key = 'L', mods = 'NONE', action = wezterm.action.CopyMode 'MoveToEndOfLineContent' })
table.insert(copy_mode, { key = 'H', mods = 'NONE', action = wezterm.action.CopyMode 'MoveToStartOfLineContent' })
config.key_tables = { copy_mode = copy_mode }

config.ssh_domains = {
  {
    name = 'raider',
    remote_address = 'raider.665665.xyz',
    multiplexing = 'None'
  },
}
config.ssh_backend = 'Ssh2'

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
    label = "raider-mux",
    domain = { DomainName = "raider" }
  },
  {
    label = 'raider-tssh',
    args = { tssh, 'raider.665665.xyz' },
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
--   'wsl.exe',
--   'wsl',
-- }
config.window_close_confirmation = 'NeverPrompt'

wezterm.on('gui-startup', function(cmd)
  if is_win then
    local function wsl_path(win_path)
      if not win_path then
        return win_path
      end

      -- 将反斜杠替换为斜杠
      local path = win_path:gsub("\\", "/")

      -- 提取驱动器号并转换为小写
      local drive, rest_of_path = path:match("^(%a):[/\\](.*)")
      if not drive then
        return win_path
      end

      -- 构建 WSL 路径
      return "/mnt/" .. drive:lower() .. "/" .. rest_of_path
    end
    
    local cwd = cmd and cmd.cwd or nil
    mux.spawn_window { width = 119, height = 43, cwd = wsl_path(cwd) }
    wezterm.sleep_ms(400)
    wezterm.run_child_process { "C:\\Program Files\\AutoHotkey\\AutoHotkey.exe", "C:\\Users\\lu5je0\\.dotfiles\\win\\ahk\\wezterm\\resize.ahk" }
  elseif is_mac then
    mux.spawn_window { width = 120, height = 42 }
  end
end)

if is_mac then
  config.set_environment_variables = {
    PATH = '/opt/homebrew/bin:' .. os.getenv('PATH')
  }
end

if is_win then
  config.set_environment_variables = {
    PATH = 'C:\\Program Files\\WezTerm:' .. os.getenv('PATH')
  }
  config.default_domain = "WSL:Debian"
end

-- -- This function returns the suggested title for a tab.
-- -- It prefers the title that was set via `tab:set_title()`
-- -- or `wezterm cli set-tab-title`, but falls back to the
-- -- title of the active pane in that tab.
-- local function tab_title(tab_info)
--   local title = tab_info.tab_title
--   -- if the tab title is explicitly set, take that
--   if title and #title > 0 then
--     return title
--   end
--   -- Otherwise, use the title from the active pane
--   -- in that tab
--   return tab_info.active_pane.title
-- end
--
-- local function basename(path)
-- 	return string.gsub(path, "(.*[/\\])(.*)", "%2")
-- end
--
-- wezterm.on(
--   'format-tab-title',
--   function(tab, tabs, panes, config, hover, max_width)
--     local title = tab_title(tab)
--     -- if tab.is_active then
--     --   return {
--     --     { Text = ' ' .. title .. ' ' },
--     --   }
--     -- end
--     return (tab.tab_index + 1) .. ": " .. title .. "(" .. basename(tab.active_pane.foreground_process_name) .. ")"
--   end
-- )

return config
