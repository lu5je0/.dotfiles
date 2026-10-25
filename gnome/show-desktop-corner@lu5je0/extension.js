import Shell from 'gi://Shell';
import St from 'gi://St';
import Meta from 'gi://Meta';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const CORNER_SIZE = 8;
const APP_TYPES = new Set([
    Meta.WindowType.NORMAL,
    Meta.WindowType.DIALOG,
    Meta.WindowType.MODAL_DIALOG,
]);

export default class ShowDesktopCorner extends Extension {
    enable() {
        this._signals = [];
        this._windows = new Map();
        this._snapshots = new Map();
        this._corner = new St.Button({
            name: 'show-desktop-corner',
            accessible_name: '显示桌面 / 还原窗口',
            can_focus: false,
            reactive: true,
            opacity: 0,
            button_mask: St.ButtonMask.ONE,
            width: CORNER_SIZE,
            height: CORNER_SIZE,
            style: 'padding: 0; margin: 0; border: 0; border-radius: 0; background-color: transparent; box-shadow: none;',
        });
        this._corner.connect('clicked', () => this._toggle());
        // 不占 work area，不设置鼠标屏障，也不改变全屏合成策略。
        Main.layoutManager.addChrome(this._corner, {affectsStruts: false});

        const sync = () => this._syncCorner();
        this._connect(Main.layoutManager, 'startup-complete', sync);
        this._connect(Main.layoutManager, 'monitors-changed', sync);
        this._connect(global.display, 'in-fullscreen-changed', sync);
        this._connect(global.display, 'notify::focus-window', sync);
        this._connect(global.display, 'window-created', (_display, window) => {
            this._watchWindow(window);
            this._syncCorner();
        });
        this._connect(global.workspace_manager, 'active-workspace-changed', sync);
        this._connect(global.workspace_manager, 'workspace-removed', () => {
            const manager = global.workspace_manager;
            const workspaces = new Set(Array.from({length: manager.n_workspaces},
                (_, index) => manager.get_workspace_by_index(index)));
            for (const workspace of this._snapshots.keys()) {
                if (!workspaces.has(workspace))
                    this._snapshots.delete(workspace);
            }
            this._syncCorner();
        });
        this._connect(Main.overview, 'showing', sync);
        this._connect(Main.overview, 'hidden', sync);
        this._connect(Main.sessionMode, 'updated', sync);

        for (const actor of global.get_window_actors())
            this._watchWindow(actor.meta_window);
        this._syncCorner();
    }

    _connect(object, signal, callback) {
        this._signals.push([object, object.connect(signal, callback)]);
    }

    _watchWindow(window) {
        if (this._windows.has(window) || !APP_TYPES.has(window.get_window_type()))
            return;

        const ids = [];
        const connect = (signal, callback) => ids.push(window.connect(signal, callback));
        this._windows.set(window, ids);
        for (const signal of ['position-changed', 'size-changed', 'notify::fullscreen'])
            connect(signal, () => this._syncCorner());
        connect('notify::minimized', () => {
            // 手动还原后，后续最小化归用户所有，不再属于这次「显示桌面」。
            if (!window.minimized)
                this._forgetWindow(window);
            this._syncCorner();
        });
        connect('workspace-changed', () => {
            this._forgetWindow(window, workspace => !window.located_on_workspace(workspace));
            this._syncCorner();
        });
        connect('unmanaged', () => {
            this._forgetWindow(window);
            for (const id of ids)
                window.disconnect(id);
            this._windows.delete(window);
            this._syncCorner();
        });
    }

    _forgetWindow(window, matches = () => true) {
        for (const [workspace, snapshot] of this._snapshots) {
            if (!matches(workspace))
                continue;
            snapshot.windows.delete(window);
            if (snapshot.focus === window)
                snapshot.focus = null;
            if (snapshot.windows.size === 0)
                this._snapshots.delete(workspace);
        }
    }

    _hasFullscreen() {
        const monitors = Main.layoutManager.monitors;
        if (monitors.some(monitor => monitor.inFullscreen))
            return true;

        const workspace = global.workspace_manager.get_active_workspace();
        for (const window of this._windows.keys()) {
            if (window.minimized || !window.located_on_workspace(workspace) ||
                !window.showing_on_its_workspace())
                continue;
            if (window.is_fullscreen())
                return true;

            // 未声明 fullscreen 的无边框游戏也避让；普通最大化窗口仍可使用。
            if (window.decorated || window.is_maximized())
                continue;
            const rect = window.get_frame_rect();
            if (monitors.some(monitor =>
                rect.x <= monitor.x && rect.y <= monitor.y &&
                rect.x + rect.width >= monitor.x + monitor.width &&
                rect.y + rect.height >= monitor.y + monitor.height))
                return true;
        }
        return false;
    }

    _desktopAvailable() {
        return Main.sessionMode.hasWindows && !Main.sessionMode.isLocked &&
            !Main.overview.visible && !this._hasFullscreen();
    }

    _canToggle() {
        return Main.actionMode === Shell.ActionMode.NORMAL && this._desktopAvailable();
    }

    _syncCorner() {
        const monitor = Main.layoutManager.primaryMonitor;
        const available = Boolean(monitor) && this._desktopAvailable();
        // visible=false 和 reactive=false 一起撤掉命中区域，不能用 opacity=0 代替。
        this._corner.reactive = available;
        this._corner.visible = available;
        if (monitor) {
            this._corner.set_position(monitor.x + monitor.width - CORNER_SIZE,
                monitor.y + monitor.height - CORNER_SIZE);
        }
        // Dock 后加载或改变层级后，点击入口仍保持在它上方。
        const parent = this._corner.get_parent();
        parent.set_child_above_sibling(this._corner, null);
    }

    _toggle() {
        // 在按下与松开之间进入全屏、锁屏或 Overview 时也不能执行。
        if (!this._canToggle()) {
            this._syncCorner();
            return;
        }
        const workspace = global.workspace_manager.get_active_workspace();
        const snapshot = this._snapshots.get(workspace);
        const visible = workspace.list_windows().filter(window =>
            this._windows.has(window) && !window.skip_taskbar &&
            !window.minimized && window.showing_on_its_workspace());
        if (visible.length > 0) {
            const windows = global.display.sort_windows_by_stacking(
                visible.filter(window => window.can_minimize() && !window.is_fullscreen()));
            if (windows.length > 0) {
                // 桌面重新出现窗口时继续隐藏，将新的一批追加到原有还原记录。
                const pending = snapshot ?? {windows: new Set(), focus: null};
                for (const window of windows)
                    pending.windows.add(window);
                pending.focus = global.display.focus_window;
                this._snapshots.set(workspace, pending);
                for (const window of windows)
                    window.minimize();
            }
        } else if (snapshot) {
            this._snapshots.delete(workspace);
            const restored = this._restore(workspace, snapshot);
            // 对话框可能随父窗口隐藏，但自身没有 minimized 标志。
            let focus = snapshot.focus;
            let ancestor = focus;
            while (ancestor && !restored.includes(ancestor))
                ancestor = ancestor.get_transient_for();
            if (!ancestor || !this._windows.has(focus) || focus.minimized ||
                !focus.located_on_workspace(workspace))
                focus = restored.at(-1);
            focus?.activate(global.get_current_time());
        }
        this._syncCorner();
    }

    _restore(workspace, snapshot, raise = true) {
        const restored = [];
        for (const window of snapshot.windows) {
            if (!this._windows.has(window) || !window.minimized ||
                !window.located_on_workspace(workspace) || window.is_fullscreen())
                continue;
            window.unminimize();
            if (raise)
                window.raise();
            restored.push(window);
        }
        return restored;
    }

    disable() {
        for (const [object, id] of this._signals)
            object.disconnect(id);
        for (const [window, ids] of this._windows) {
            for (const id of ids)
                window.disconnect(id);
        }
        // 释放快照后再还原，避免还原通知改变正在遍历的记录；不抢焦点或抬高窗口。
        const snapshots = this._snapshots;
        this._snapshots = new Map();
        for (const [workspace, snapshot] of snapshots)
            this._restore(workspace, snapshot, false);
        this._windows.clear();
        Main.layoutManager.removeChrome(this._corner);
        this._corner.destroy();
        this._corner = null;
    }
}
