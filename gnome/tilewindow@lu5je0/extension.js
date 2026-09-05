import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as WorkspaceSwitcherPopup from 'resource:///org/gnome/shell/ui/workspaceSwitcherPopup.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Set in enable() to <repo>/wm/layout.jsonc (unified across wms); read on every
// keypress so sizes can be tuned live without reloading the shell
let configPath = null;

// 剥离 JSONC 注释（// 与 /* */），字符串字面量内的原样保留
function stripComments(text) {
    let out = '';
    let i = 0;
    while (i < text.length) {
        const c = text[i];
        if (c === '"') {
            const start = i;
            i++;
            while (i < text.length) {
                if (text[i] === '\\')
                    i += 2;
                else if (text[i] === '"') {
                    i++;
                    break;
                } else {
                    i++;
                }
            }
            out += text.slice(start, i);
        } else if (c === '/' && text[i + 1] === '/') {
            while (i < text.length && text[i] !== '\n')
                i++;
        } else if (c === '/' && text[i + 1] === '*') {
            const end = text.indexOf('*/', i + 2);
            i = end < 0 ? text.length : end + 2;
        } else {
            out += c;
            i++;
        }
    }
    return out;
}

function loadFileConfig() {
    if (!configPath)
        return null;
    try {
        const [, contents] = Gio.File.new_for_path(configPath).load_contents(null);
        return JSON.parse(stripComments(new TextDecoder().decode(contents)));
    } catch {
        return null;
    }
}

// Built-in fallback layout; per-app sizes in wm/layout.jsonc take precedence
const layoutConfig = {
    'default': {
        'center_i': (sw, sh) => {
            const w = Math.round(sw * 11 / 16);
            const h = sh - 120;
            return {width: w, height: h, x: Math.round((sw - w) / 2), y: 23};
        },
        'center_j': (sw, sh) => {
            const w = Math.round(sw * 3 / 5);
            const h = Math.round(sh * 17 / 20);
            return {width: w, height: h, x: Math.round((sw - w) / 2), y: Math.round((sh - h) / 2)};
        },
    },
};

const DOCK_ACTOR_NAME = 'dashtodockContainer';

// Autohide docks (dash-to-dock with dock-fixed=false) set no struts, so mutter's
// work area still spans under them. dash-to-dock keeps the geometry the dock
// occupies when shown in `staticBox`, which stays valid while it is slid out.
function getDockRects() {
    const rects = [];
    for (const actor of Main.layoutManager.uiGroup.get_children()) {
        if (actor.name !== DOCK_ACTOR_NAME || !actor.visible)
            continue;
        const box = actor.staticBox ?? actor.get_allocation_box();
        const width = box.x2 - box.x1;
        const height = box.y2 - box.y1;
        if (width > 0 && height > 0)
            rects.push({x: box.x1, y: box.y1, width, height});
    }
    return rects;
}

// Push `area` out of `rect`, cutting only the edge the dock hugs. A fixed dock
// already sets struts, so its rect no longer overlaps and nothing is cut; same
// goes for a dock living on another monitor
function trimAreaByRect(area, rect) {
    const ax2 = area.x + area.width;
    const ay2 = area.y + area.height;
    const rx2 = rect.x + rect.width;
    const ry2 = rect.y + rect.height;
    const overlapX = Math.min(ax2, rx2) - Math.max(area.x, rect.x);
    const overlapY = Math.min(ay2, ry2) - Math.max(area.y, rect.y);
    if (overlapX <= 0 || overlapY <= 0)
        return area;

    // the dock's thin axis tells left/right apart from top/bottom
    if (overlapX <= overlapY) {
        if (rect.x - area.x <= ax2 - rx2)
            return {x: rx2, y: area.y, width: Math.max(1, ax2 - rx2), height: area.height};
        return {x: area.x, y: area.y, width: Math.max(1, rect.x - area.x), height: area.height};
    }
    if (rect.y - area.y <= ay2 - ry2)
        return {x: area.x, y: ry2, width: area.width, height: Math.max(1, ay2 - ry2)};
    return {x: area.x, y: area.y, width: area.width, height: Math.max(1, rect.y - area.y)};
}

function getWorkArea(win) {
    let area = win.get_work_area_current_monitor();
    for (const rect of getDockRects())
        area = trimAreaByRect(area, rect);

    // optional manual trim on top of the detected docks
    const insets = loadFileConfig()?.['insets'];
    if (!insets)
        return area;

    const top = insets.top ?? 0;
    const bottom = insets.bottom ?? 0;
    const left = insets.left ?? 0;
    const right = insets.right ?? 0;
    return {
        x: area.x + left,
        y: area.y + top,
        width: Math.max(1, area.width - left - right),
        height: Math.max(1, area.height - top - bottom),
    };
}

function getWmClass(win) {
    return (win.get_wm_class() || '').toLowerCase();
}

function isNormal(win) {
    return win.window_type === Meta.WindowType.NORMAL;
}

// Fullscreen clients (games etc.) are left alone entirely
function getTargetWindow() {
    const win = global.display.get_focus_window();
    if (!win || !isNormal(win) || win.is_fullscreen())
        return null;
    return win;
}

function resolveDim(spec, max) {
    if (typeof spec === 'number')
        return Math.round(spec);
    return Math.round(max * (spec.ratio ?? 1) + (spec.offset ?? 0));
}

function alignPos(axis, spec, size, max) {
    const align = spec.align ?? 'center';
    const offset = spec.offset ?? 0;
    if (axis === 'x') {
        if (align === 'left') return offset;
        if (align === 'right') return max - size - offset;
        return Math.round((max - size) / 2) + offset;
    }
    if (align === 'top') return offset;
    if (align === 'bottom') return max - size - offset;
    return Math.round((max - size) / 2) + offset;
}

// wm/layout.jsonc: rules 数组从前往后，取第一条字段全匹配且提供该 mode 的规则
// 字段可为字符串或数组，缺省即通配
function findEntry(config, wm, app, screen, mode) {
    const matchField = (spec, value) => {
        if (spec == null)
            return true;
        const list = Array.isArray(spec) ? spec : [spec];
        return list.includes(value);
    };
    for (const rule of config?.rules ?? []) {
        if (!matchField(rule.wm, wm) || !matchField(rule.app, app) || !matchField(rule.screen, screen))
            continue;
        if (rule.size && rule.size[mode])
            return rule.size[mode];
    }
    return null;
}

function getCenterLayout(wmClass, position, sw, sh) {
    const entry = findEntry(loadFileConfig(), 'gnome', wmClass, 'default', position);
    if (entry) {
        const w = resolveDim(entry.w, sw);
        const h = resolveDim(entry.h, sh);
        const x = entry.x != null ? alignPos('x', entry.x, w, sw) : Math.round((sw - w) / 2);
        const y = entry.y != null ? alignPos('y', entry.y, h, sh) : Math.round((sh - h) / 2);
        return {width: w, height: h, x, y};
    }

    // 内置兜底，与 wm/layout.jsonc 的全局 fallback 规则保持一致
    const appMap = layoutConfig[wmClass] ?? layoutConfig['default'];
    if (!appMap[position])
        return null;
    return appMap[position](sw, sh);
}

function getSideRect(side, area) {
    const sideConfig = loadFileConfig()?.side;
    const w = sideConfig?.width ?? 1139;
    const h = sideConfig?.height ?? 1218;
    // 与 kwin 一致：贴边窗口居中在各自半屏内
    const halfWidth = area.width / 2;
    const x = (side === 'left')
        ? area.x + Math.round((halfWidth - w) / 2)
        : area.x + Math.round(halfWidth) + Math.round((halfWidth - w) / 2);
    const y = area.y + Math.round((area.height - h) / 2);
    return {x, y, width: w, height: h};
}

function listCandidates(excludeWin) {
    return global.workspace_manager.get_active_workspace().list_windows()
        .filter(w => w !== excludeWin &&
            !w.minimized &&
            !w.is_fullscreen() &&
            isNormal(w) &&
            w.get_monitor() === excludeWin.get_monitor());
}

function isWindowSnappedTo(win, side, area) {
    const r = getSideRect(side, area);
    const geo = win.get_frame_rect();
    const tolerance = 16;
    return Math.abs(geo.x - r.x) <= tolerance && Math.abs(geo.width - r.width) <= tolerance;
}

function findOtherWindowOnSide(side, area, excludeWin) {
    return listCandidates(excludeWin).find(w => isWindowSnappedTo(w, side, area)) ?? null;
}

// Catches an already spread-out window (maximized or nearly so) that should be
// pushed aside; true fullscreen windows are filtered out by listCandidates()
function findCoveringWindow(area, excludeWin) {
    const waArea = area.width * area.height;
    if (waArea <= 0)
        return null;
    return listCandidates(excludeWin).find(w => {
        if (!w.get_title())
            return false;
        const geo = w.get_frame_rect();
        if (geo.width <= 0 || geo.height <= 0)
            return false;
        const ox = Math.max(0, Math.min(area.x + area.width, geo.x + geo.width) - Math.max(area.x, geo.x));
        const oy = Math.max(0, Math.min(area.y + area.height, geo.y + geo.height) - Math.max(area.y, geo.y));
        return (ox * oy) / waArea > 0.8;
    }) ?? null;
}

function findOtherWindowAtRect(rx, ry, rw, rh, excludeWin) {
    if (rw <= 0 || rh <= 0)
        return null;
    const targetCx = rx + rw / 2;
    const targetCy = ry + rh / 2;
    const centerTolerance = 30;
    return listCandidates(excludeWin).find(w => {
        const area = w.get_work_area_current_monitor();
        const geo = w.get_frame_rect();
        if (geo.width >= area.width && geo.height >= area.height)
            return false;
        if (geo.width <= 0 || geo.height <= 0)
            return false;
        const cx = geo.x + geo.width / 2;
        const cy = geo.y + geo.height / 2;
        return Math.abs(cx - targetCx) <= centerTolerance && Math.abs(cy - targetCy) <= centerTolerance;
    }) ?? null;
}

// A fullscreen window ignores move_resize_frame(), but those never reach here:
// getTargetWindow() and listCandidates() both filter them out
function moveWindowTo(win, geo) {
    win.unmaximize();
    win.move_resize_frame(true, geo.x, geo.y, geo.width, geo.height);
}

// 等效于系统 Ctrl+Alt+Left/Right（switch-to-workspace-left/right）：
// 新版 gnome-shell 移除了 Main.wm.actionMoveWorkspace*，直接用稳定的
// workspace_manager API 激活相邻工作区，并复刻 _showWorkspaceSwitcher
// 末尾的 WorkspaceSwitcherPopup 逻辑，保持虚拟桌面指示器显示
let workspaceSwitcherPopup = null;

function getAdjacentWorkspace(offset) {
    const wsManager = global.workspace_manager;
    const total = wsManager.get_n_workspaces();
    const count = Meta.prefs_get_dynamic_workspaces() && total > 2 ? total - 1 : total;
    if (count < 2)
        return null;

    const index = wsManager.get_active_workspace_index();
    if (index >= count)
        return wsManager.get_workspace_by_index(offset > 0 ? 0 : count - 1);
    return wsManager.get_workspace_by_index((index + offset + count) % count);
}

function activateWorkspace(target) {
    if (!target || target.active)
        return;

    target.activate(global.get_current_time());

    if (!Main.overview.visible) {
        if (!workspaceSwitcherPopup) {
            workspaceSwitcherPopup = new WorkspaceSwitcherPopup.WorkspaceSwitcherPopup();
            workspaceSwitcherPopup.connect('destroy', () => {
                Main.wm._workspaceTracker?.unblockUpdates();
                workspaceSwitcherPopup = null;
            });
        }
        // 弹窗期间阻止动态工作区回收，与 _showWorkspaceSwitcher 一致
        Main.wm._workspaceTracker?.blockUpdates();
        workspaceSwitcherPopup.display(target.index());
    }
}

function switchWorkspace(offset) {
    activateWorkspace(getAdjacentWorkspace(offset));
}

function moveFocusedWindowToWorkspace(offset) {
    const client = getTargetWindow();
    const target = getAdjacentWorkspace(offset);
    if (!client || !target)
        return;
    client.change_workspace(target);
    activateWorkspace(target);
}

function resizeWindow(position) {
    const client = getTargetWindow();
    if (!client)
        return;

    const area = getWorkArea(client);
    const wmClass = getWmClass(client);

    let newX, newY, newWidth, newHeight;

    if (position === 'left' || position === 'right') {
        const r = getSideRect(position, area);
        newX = r.x;
        newY = r.y;
        newWidth = r.width;
        newHeight = r.height;
    } else if (position === 'center_i' || position === 'center_j') {
        const layout = getCenterLayout(wmClass, position, area.width, area.height);
        if (!layout)
            return;
        newX = area.x + layout.x;
        newY = area.y + layout.y;
        newWidth = layout.width;
        newHeight = layout.height;
    } else {
        return;
    }

    if (position === 'center_i' || position === 'center_j') {
        const offsetStep = 20;
        const maxShifts = 6;
        let shifts = 0;
        while (shifts < maxShifts && findOtherWindowAtRect(newX, newY, newWidth, newHeight, client)) {
            newX += offsetStep;
            shifts++;
        }
    }

    if (newY + newHeight > area.y + area.height)
        newY = area.y + area.height - newHeight;
    if (newX + newWidth > area.x + area.width)
        newX = area.x + area.width - newWidth;

    moveWindowTo(client, {x: newX, y: newY, width: newWidth, height: newHeight});
}

function snapWithSwap(side) {
    const client = getTargetWindow();
    if (!client)
        return;

    const area = getWorkArea(client);
    const otherSide = (side === 'left') ? 'right' : 'left';

    let occupier = findOtherWindowOnSide(side, area, client);
    if (!occupier)
        occupier = findCoveringWindow(area, client);

    if (occupier)
        moveWindowTo(occupier, getSideRect(otherSide, area));

    resizeWindow(side);
}

export default class TileWindowExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._names = [];
        configPath = GLib.build_filenamev([GLib.get_home_dir(), '.dotfiles', 'wm', 'layout.jsonc']);

        const bind = (name, handler) => {
            Main.wm.addKeybinding(name, this._settings,
                Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
                Shell.ActionMode.NORMAL,
                handler);
            this._names.push(name);
        };

        bind('snap-left', () => snapWithSwap('left'));
        bind('snap-right', () => snapWithSwap('right'));
        bind('center-i', () => resizeWindow('center_i'));
        bind('center-j', () => resizeWindow('center_j'));
        bind('maximize-window', () => {
            const client = getTargetWindow();
            if (!client)
                return;
            client.maximize();
        });
        bind('minimize-window', () => {
            const client = getTargetWindow();
            if (!client)
                return;
            client.minimize();
        });
        bind('toggle-above', () => {
            const client = getTargetWindow();
            if (!client)
                return;
            if (client.is_above())
                client.unmake_above();
            else
                client.make_above();
        });
        bind('workspace-left', () => switchWorkspace(-1));
        bind('workspace-right', () => switchWorkspace(1));
        bind('workspace-next', () => switchWorkspace(1));
        bind('workspace-previous', () => switchWorkspace(-1));
        bind('move-window-next-workspace', () => moveFocusedWindowToWorkspace(1));
        bind('move-window-previous-workspace', () => moveFocusedWindowToWorkspace(-1));
        bind('window-info', () => {
            const client = global.display.get_focus_window();
            if (!client)
                return;
            const geo = client.get_frame_rect();
            const area = getWorkArea(client);
            const docks = getDockRects()
                .map(r => `${r.width}x${r.height}+${r.x}+${r.y}`)
                .join(' ') || 'none';
            console.log(`TileWindow: X:${geo.x} Y:${geo.y} W:${geo.width} H:${geo.height} | ${getWmClass(client)} | Area:${area.width}x${area.height}+${area.x}+${area.y} | Dock:${docks}`);
        });
    }

    disable() {
        for (const name of this._names)
            Main.wm.removeKeybinding(name);
        this._names = [];
        this._settings = null;
    }
}
