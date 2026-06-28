; layout.ahk - 居中布局的统一配置 (center_i / center_j)
#Requires AutoHotkey v2.0

; 布局配置：以函数形式描述尺寸，输入屏幕宽高，返回 {width,height,x,y}
; 通过 processName -> position -> fn 的两级 Map 表查找；找不到走 "default"
global LayoutConfig := Map(
    "default", Map(
        "center_i", (sw, sh) => (
            w := sw * (11 / 16),
            h := sh - 120,
            { width: w, height: h, x: (sw - w) / 2, y: 23 }
        ),
        "center_j", (sw, sh) => (
            w := sw * 3 / 5,
            h := sh * (17 / 20),
            { width: w, height: h, x: (sw - w) / 2, y: (sh - h) / 2 }
        ),
    ),
    "wezterm-gui.exe", Map(
        "center_i", (sw, sh) => { width: 2710, height: 2023, x: (sw - 2713) / 2, y: 43 },
        "center_j", (sw, sh) => { width: 1999, height: 1689, x: (sw - 1999) / 2, y: (sh - 1596) / 2 - 100 },
    ),
    "WindowsTerminal.exe", Map(
        "center_i", (sw, sh) => { width: 2457, height: 2038, x: (sw - 2457) / 2, y: 23 },
        "center_j", (sw, sh) => { width: 1931, height: 1596, x: (sw - 1931) / 2, y: (sh - 1596) / 2 - 100 },
    ),
)

GetCenterLayout(processName, position, screenWidth, screenHeight) {
    global LayoutConfig
    key := LayoutConfig.Has(processName) ? processName : "default"
    appMap := LayoutConfig[key]
    if (!appMap.Has(position))
        return 0
    return appMap[position].Call(screenWidth, screenHeight)
}
