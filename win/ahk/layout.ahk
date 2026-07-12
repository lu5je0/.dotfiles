; layout.ahk - 居中布局的统一配置 (center_i / center_j)
#Requires AutoHotkey v2.0

; 布局配置：以函数形式描述尺寸，输入屏幕宽高，返回 {width,height,x,y}
; 通过 processName -> position -> fn 的两级 Map 表查找；找不到走 "default"
global LayoutConfig := Map(
    "default", Map(
        "center_i", (sw, sh) => (
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb),
            margin := 23,
            w := sw * (11 / 16),
            h := (wb - wt) - margin * 2,
            { width: w, height: h, x: (sw - w) / 2, y: wt + margin }
        ),
        "center_j", (sw, sh) => (
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb),
            w := sw * 3 / 5,
            h := (wb - wt) * (17 / 20),
            { width: w, height: h, x: (sw - w) / 2, y: wt + ((wb - wt) - h) / 2 }
        ),
    ),
    "wezterm-gui.exe", Map(
        "center_i", (sw, sh) => (
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb),
            margin := 43,
            h := (wb - wt) - margin * 2,
            { width: 2710, height: h, x: (sw - 2713) / 2, y: wt + margin }
        ),
        "center_j", (sw, sh) => (
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb),
            w := 1999,
            h := 1689,
            { width: w, height: h, x: (sw - w) / 2, y: wt + ((wb - wt) - h) / 2 }
        ),
    ),
    "WindowsTerminal.exe", Map(
        "center_i", (sw, sh) => (
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb),
            margin := 23,
            h := (wb - wt) - margin * 2,
            { width: 2457, height: h, x: (sw - 2457) / 2, y: wt + margin }
        ),
        "center_j", (sw, sh) => (
            MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt, &wr, &wb),
            w := 1931,
            h := 1596,
            { width: w, height: h, x: (sw - w) / 2, y: wt + ((wb - wt) - h) / 2 }
        ),
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
