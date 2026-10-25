# 关闭到托盘后窗口已 withdrawn，必须让微信自己重新显示；带参数调用仍交给上游。
if [[ $# -eq 0 ]] && tray_items="$(busctl --user --timeout=2 --auto-start=no --json=short get-property \
    org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
    org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null)"; then
    while IFS= read -r tray_item; do
        # 兼容仅总线名、总线名/对象路径及 GNOME AppIndicator 的总线名@/对象路径。
        case "$tray_item" in
            *@/*)
                tray_service="${tray_item%%@/*}"
                tray_path="/${tray_item#*@/}"
                ;;
            */*)
                tray_service="${tray_item%%/*}"
                tray_path="/${tray_item#*/}"
                ;;
            *)
                tray_service="$tray_item"
                tray_path=/StatusNotifierItem
                ;;
        esac

        tray_id="$(busctl --user --timeout=2 --auto-start=no --json=short get-property \
            "$tray_service" "$tray_path" org.kde.StatusNotifierItem Id 2>/dev/null)" || continue
        [[ "$(jq -r '.data' <<< "$tray_id")" == wechat ]] || continue

        if busctl --user --timeout=2 --auto-start=no call \
            "$tray_service" "$tray_path" org.kde.StatusNotifierItem Activate ii 0 0 >/dev/null 2>&1; then
            exit 0
        fi
    done < <(jq -r '.data[]' <<< "$tray_items")
fi
