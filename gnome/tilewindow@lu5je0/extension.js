import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Set in enable() to <extension dir>/layout.json; read on every keypress so
// sizes can be tuned live without reloading the shell
let configPath = null;

function loadFileConfig() {
    if (!configPath)
        return null;
    try {
        const [, contents] = Gio.File.new_for_path(configPath).load_contents(null);
        return JSON.parse(new TextDecoder().decode(contents));
    } catch {
        return null;
    }
}

// Built-in fallback layout; per-app sizes in layout.json (extension dir) take precedence
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

function getWorkArea(win) {
    return win.get_work_area_current_monitor();
}

function getWmClass(win) {
    return (win.get_wm_class() || '').toLowerCase();
}

function isNormal(win) {
    return win.window_type === Meta.WindowType.NORMAL;
}

function getCenterLayout(wmClass, position, sw, sh) {
    const fileConfig = loadFileConfig();
    const entry = fileConfig?.[wmClass]?.[position] ?? fileConfig?.['default']?.[position];
    if (entry?.width > 0 && entry.height > 0) {
        const w = entry.width;
        const h = entry.height;
        const x = entry.x ?? Math.round((sw - w) / 2);
        const y = entry.y ?? Math.round((sh - h) / 2);
        return {width: w, height: h, x, y};
    }

    const appMap = layoutConfig[wmClass] ?? layoutConfig['default'];
    if (!appMap[position])
        return null;
    return appMap[position](sw, sh);
}

function getSideRect(side, area) {
    const sideConfig = loadFileConfig()?.['side'];
    const w = sideConfig?.width ?? 1139;
    const h = sideConfig?.height ?? 1218;
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

function findFullscreenWindow(area, excludeWin) {
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
        if (w.is_fullscreen())
            return false;
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

function moveWindowTo(win, geo) {
    win.unmaximize();
    win.move_resize_frame(true, geo.x, geo.y, geo.width, geo.height);
}

function resizeWindow(position) {
    const client = global.display.get_focus_window();
    if (!client || !isNormal(client))
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
    const client = global.display.get_focus_window();
    if (!client || !isNormal(client))
        return;

    const area = getWorkArea(client);
    const otherSide = (side === 'left') ? 'right' : 'left';

    let occupier = findOtherWindowOnSide(side, area, client);
    if (!occupier)
        occupier = findFullscreenWindow(area, client);

    if (occupier)
        moveWindowTo(occupier, getSideRect(otherSide, area));

    resizeWindow(side);
}

export default class TileWindowExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._names = [];
        configPath = GLib.build_filenamev([this.path, 'layout.json']);

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
            const client = global.display.get_focus_window();
            if (!client || !isNormal(client))
                return;
            client.maximize();
        });
        bind('toggle-above', () => {
            const client = global.display.get_focus_window();
            if (!client || !isNormal(client))
                return;
            if (client.is_above())
                client.unmake_above();
            else
                client.make_above();
        });
        bind('window-info', () => {
            const client = global.display.get_focus_window();
            if (!client)
                return;
            const geo = client.get_frame_rect();
            const area = getWorkArea(client);
            console.log(`TileWindow: X:${geo.x} Y:${geo.y} W:${geo.width} H:${geo.height} | ${getWmClass(client)} | Area:${area.width}x${area.height}`);
        });
    }

    disable() {
        for (const name of this._names)
            Main.wm.removeKeybinding(name);
        this._names = [];
        this._settings = null;
    }
}
