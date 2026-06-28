--[[ local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "wofi --show drun"
local mainMod     = "SUPER"

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaybg -i ~/4.png -m fill")
end)

------------------
---- MONITORS ----
------------------

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.67,
})

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },

    general = {
        gaps_in     = 2,
        gaps_out    = 5,
        border_size = 1,
        layout      = "dwindle",
    },

    decoration = {
        rounding = 12,

        blur = {
            enabled   = true,
            size      = 8,
            passes    = 3,
            noise     = 0.02,
            vibrancy  = 0.2,
        },
    },

    dwindle = {
        preserve_split = true,
    },

    input = {
        kb_options   = "caps:escape",
        sensitivity  = 0.5,
        accel_profile = "flat",
    },
})

------------------
---- LAYERRULE ---
------------------

-- 毛玻璃效果
hl.layer_rule({ match = { namespace = "waybar" }, blur = true, ignore_alpha = 0.3 })

---------------------
---- KEYBINDINGS ----
---------------------

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("flatpak run com.google.Chrome"))
hl.bind(mainMod .. " + N", hl.dsp.focus({ workspace = "empty" }))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.window.move({ workspace = "empty" }))

-- 工作区切换
hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))

hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))

-- 前一个/后一个工作区
hl.bind(mainMod .. " + LEFT",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + RIGHT", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- 窗口焦点移动
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Alt+Tab 切换窗口
hl.bind("ALT + TAB",         hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ prev = true }))

-- 上下窗口平均分割
hl.bind(mainMod .. " + equal",       hl.dsp.layout("splitratio 1.0 exact"))
-- 左右窗口平均分割
hl.bind(mainMod .. " + SHIFT + 5",   hl.dsp.layout("splitratio 1.0 exact"))

-- 鼠标操作
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }) ]]
