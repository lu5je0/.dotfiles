import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import vm from 'node:vm';

const directory = process.env.EXTENSION_DIR ??
    fileURLToPath(new URL('../show-desktop-corner@lu5je0/', import.meta.url));
const source = await readFile(path.join(directory, 'extension.js'), 'utf8');

class Signals {
    signals = new Map();
    nextId = 1;
    connect(name, callback) {
        const id = this.nextId++;
        this.signals.set(id, {name, callback});
        return id;
    }
    disconnect(id) {
        assert.ok(this.signals.delete(id), `Unknown signal ${id}`);
    }
    emit(name, ...args) {
        for (const signal of [...this.signals.values()]) {
            if (signal.name === name)
                signal.callback(this, ...args);
        }
    }
}

async function setup() {
    const operations = [];
    const windows = [];
    const manager = new Signals();
    const workspaces = [0, 1].map(id => ({
        id,
        list_windows: () => windows.filter(window => window.located_on_workspace(workspaces[id])),
    }));
    let current = workspaces[0];
    Object.assign(manager, {
        n_workspaces: 2,
        get_active_workspace: () => current,
        get_workspace_by_index: index => workspaces[index],
    });
    const layoutManager = new Signals();
    const primary = {x: 0, y: 0, width: 1920, height: 1080, inFullscreen: false};
    const secondary = {x: 1920, y: -100, width: 1280, height: 1024, inFullscreen: false};
    const parent = {set_child_above_sibling() {}};
    Object.assign(layoutManager, {
        primaryMonitor: primary,
        monitors: [primary, secondary],
        addChrome: (actor, options) => {
            assert.equal(options.affectsStruts, false);
            actor.parent = parent;
        },
        removeChrome: actor => { actor.parent = null; },
    });
    class Button extends Signals {
        constructor(properties) { super(); Object.assign(this, properties); }
        set_position(x, y) { this.x = x; this.y = y; }
        get_parent() { return this.parent; }
        set_style(style) { this.style = style; }
        destroy() { this.destroyed = true; this.signals.clear(); }
    }
    const overview = Object.assign(new Signals(), {visible: false});
    const sessionMode = Object.assign(new Signals(), {hasWindows: true, isLocked: false});
    const display = Object.assign(new Signals(), {
        focus_window: null,
        sort_windows_by_stacking: list => [...list].sort((a, b) => a.stack - b.stack),
    });
    class Window extends Signals {
        constructor(name, options) {
            super();
            Object.assign(this, {
                name, workspace: current, stack: windows.length,
                minimized: false, fullscreen: false, decorated: true, maximized: false,
                type: 0, skip_taskbar: false, minimizable: true, transient: null,
                rect: {x: 100, y: 100, width: 800, height: 600},
            }, options);
        }
        get_window_type() { return this.type; }
        can_minimize() { return this.minimizable; }
        is_fullscreen() { return this.fullscreen; }
        is_maximized() { return this.maximized; }
        get_frame_rect() { return this.rect; }
        get_transient_for() { return this.transient; }
        located_on_workspace(workspace) { return this.sticky || this.workspace === workspace; }
        showing_on_its_workspace() { return !this.minimized; }
        minimize() {
            operations.push(`minimize:${this.name}`);
            this.minimized = true;
            this.emit('notify::minimized');
        }
        unminimize() {
            operations.push(`restore:${this.name}`);
            this.minimized = false;
            this.emit('notify::minimized');
        }
        raise() { operations.push(`raise:${this.name}`); }
        activate() { operations.push(`focus:${this.name}`); display.focus_window = this; }
    }

    const context = vm.createContext({global: {
        display,
        workspace_manager: manager,
        get_window_actors: () => windows.map(meta_window => ({meta_window})),
        get_current_time: () => 123,
    }});
    const main = new vm.SyntheticModule(
        ['layoutManager', 'overview', 'sessionMode', 'actionMode'], function () {
            for (const [name, value] of Object.entries({layoutManager, overview, sessionMode, actionMode: 1}))
                this.setExport(name, value);
        }, {context});
    const modules = {
        'gi://Shell': {default: {ActionMode: {NORMAL: 1}}},
        'gi://St': {default: {Button, ButtonMask: {ONE: 1}}},
        'gi://Meta': {default: {WindowType: {NORMAL: 0, DIALOG: 1, MODAL_DIALOG: 2}}},
        'resource:///org/gnome/shell/extensions/extension.js': {Extension: class {}},
    };
    const module = new vm.SourceTextModule(source, {context});
    await module.link(specifier => {
        if (specifier === 'resource:///org/gnome/shell/ui/main.js')
            return main;
        assert.ok(modules[specifier], `Unexpected import: ${specifier}`);
        const exports = modules[specifier];
        return new vm.SyntheticModule(Object.keys(exports), function () {
            for (const [name, value] of Object.entries(exports))
                this.setExport(name, value);
        }, {context});
    });
    await module.evaluate();
    const extension = new module.namespace.default();
    const add = (name, options = {}) => {
        const window = new Window(name, options);
        windows.push(window);
        if (extension._windows)
            display.emit('window-created', window);
        return window;
    };
    return {
        extension, add, windows, operations, primary, secondary, display,
        manager, workspaces, layoutManager, overview, sessionMode,
        switchWorkspace(index) { current = workspaces[index]; manager.emit('active-workspace-changed'); },
        setMode(mode) { main.setExport('actionMode', mode); },
        click() { extension._corner.emit('clicked'); },
    };
}

test('restores only owned windows in stacking order and restores focus', async () => {
    const f = await setup();
    const top = f.add('top', {stack: 10});
    const bottom = f.add('bottom', {stack: 0});
    const minimized = f.add('old', {minimized: true});
    f.add('desktop', {type: 3});
    f.add('utility', {skip_taskbar: true});
    f.display.focus_window = top;
    f.extension.enable();
    f.click();
    assert.equal(bottom.minimized, true);
    assert.equal(top.minimized, true);
    f.click();
    assert.equal(minimized.minimized, true);
    assert.deepEqual(f.operations, [
        'minimize:bottom', 'minimize:top',
        'restore:bottom', 'raise:bottom', 'restore:top', 'raise:top', 'focus:top',
    ]);
    f.extension.disable();
});

test('hides newly opened windows before restoring all accumulated windows on an empty desktop', async () => {
    const f = await setup();
    const first = f.add('A');
    const old = f.add('old', {minimized: true});
    f.extension.enable();
    f.display.focus_window = first;
    f.click();
    const second = f.add('B');
    f.display.focus_window = second;
    f.click();
    assert.equal(first.minimized, true);
    assert.equal(second.minimized, true);
    assert.deepEqual(f.operations, ['minimize:A', 'minimize:B']);
    f.click();
    assert.equal(first.minimized, false);
    assert.equal(second.minimized, false);
    assert.equal(old.minimized, true);
    assert.deepEqual(f.operations, [
        'minimize:A', 'minimize:B',
        'restore:A', 'raise:A', 'restore:B', 'raise:B', 'focus:B',
    ]);
    f.extension.disable();
});

test('manually restored visible windows are hidden again instead of restoring the remaining batch', async () => {
    const f = await setup();
    const first = f.add('A');
    const second = f.add('B');
    f.extension.enable();
    f.click();
    first.unminimize();
    f.display.focus_window = first;
    f.operations.length = 0;
    f.click();
    assert.equal(first.minimized, true);
    assert.equal(second.minimized, true);
    assert.deepEqual(f.operations, ['minimize:A']);
    f.click();
    assert.equal(first.minimized, false);
    assert.equal(second.minimized, false);
    assert.deepEqual(f.operations, [
        'minimize:A', 'restore:B', 'raise:B', 'restore:A', 'raise:A', 'focus:A',
    ]);
    f.extension.disable();
});

test('a visible non-minimizable application prevents restoring windows behind it', async () => {
    const f = await setup();
    const hidden = f.add('hidden');
    f.extension.enable();
    f.click();
    const fixed = f.add('fixed', {minimizable: false});
    f.click();
    assert.equal(hidden.minimized, true);
    assert.deepEqual(f.operations, ['minimize:hidden']);
    fixed.emit('unmanaged');
    f.windows.splice(f.windows.indexOf(fixed), 1);
    f.click();
    assert.equal(hidden.minimized, false);
    f.extension.disable();
});

test('snapshots are independent across workspaces and skip moved or closed windows', async () => {
    const f = await setup();
    const moved = f.add('moved');
    const closed = f.add('closed');
    const stay = f.add('stay');
    const other = f.add('other', {workspace: f.workspaces[1]});
    f.extension.enable();
    f.click();
    moved.workspace = f.workspaces[1];
    moved.emit('workspace-changed');
    closed.emit('unmanaged');
    f.windows.splice(f.windows.indexOf(closed), 1);
    assert.equal(closed.signals.size, 0);
    f.switchWorkspace(1);
    f.click();
    f.click();
    assert.equal(other.minimized, false);
    assert.equal(stay.minimized, true);
    assert.equal(moved.minimized, true);
    f.switchWorkspace(0);
    f.click();
    assert.equal(stay.minimized, false);
    assert.ok(!f.operations.includes('restore:closed'));
    f.extension.disable();
});

test('manual restore relinquishes ownership even if the user minimizes it again', async () => {
    const f = await setup();
    const manual = f.add('manual');
    const owned = f.add('owned');
    f.extension.enable();
    f.click();
    manual.unminimize();
    manual.minimize();
    f.click();
    assert.equal(manual.minimized, true);
    assert.equal(owned.minimized, false);
    f.extension.disable();
});

test('fullscreen on either monitor removes the input target and blocks a pending click', async () => {
    const f = await setup();
    const window = f.add('app');
    f.extension.enable();
    for (const monitor of [f.primary, f.secondary]) {
        monitor.inFullscreen = true;
        f.display.emit('in-fullscreen-changed');
        assert.equal(f.extension._corner.visible, false);
        assert.equal(f.extension._corner.reactive, false);
        f.click();
        assert.equal(window.minimized, false);
        monitor.inFullscreen = false;
        f.display.emit('in-fullscreen-changed');
        assert.equal(f.extension._corner.visible, true);
    }
    window.fullscreen = true;
    window.emit('notify::fullscreen');
    assert.equal(f.extension._corner.reactive, false);
    f.extension.disable();
});

test('borderless fullscreen is protected, while ordinary maximization is usable', async () => {
    const f = await setup();
    const window = f.add('game', {decorated: false, rect: {...f.secondary}});
    f.extension.enable();
    assert.equal(f.extension._corner.visible, false);
    f.click();
    assert.equal(window.minimized, false);
    window.maximized = true;
    window.emit('size-changed');
    assert.equal(f.extension._corner.visible, true);
    f.click();
    assert.equal(window.minimized, true);
    f.extension.disable();
});

test('overview, lock screen and modal action modes block toggling', async () => {
    const f = await setup();
    const window = f.add('app');
    f.extension.enable();
    f.overview.visible = true;
    f.overview.emit('showing');
    assert.equal(f.extension._corner.visible, false);
    f.click();
    f.overview.visible = false;
    f.overview.emit('hidden');
    f.sessionMode.isLocked = true;
    f.sessionMode.emit('updated');
    assert.equal(f.extension._corner.reactive, false);
    f.click();
    f.sessionMode.isLocked = false;
    f.sessionMode.emit('updated');
    f.setMode(0);
    f.click();
    assert.equal(window.minimized, false);
    assert.equal(f.operations.length, 0);
    f.extension.disable();
});

test('primary monitor changes reposition the corner, including negative coordinates', async () => {
    const f = await setup();
    f.extension.enable();
    assert.equal(f.extension._corner.x, 1912);
    assert.equal(f.extension._corner.y, 1072);
    f.layoutManager.primaryMonitor = {...f.secondary, x: -1280};
    f.layoutManager.emit('monitors-changed');
    assert.equal(f.extension._corner.x, -8);
    assert.equal(f.extension._corner.y, 916);
    f.layoutManager.primaryMonitor = null;
    f.layoutManager.emit('monitors-changed');
    assert.equal(f.extension._corner.visible, false);
    f.extension.disable();
});

test('restores focus to a modal dialog hidden along with its parent', async () => {
    const f = await setup();
    const parent = f.add('parent');
    const dialog = f.add('dialog', {type: 2, skip_taskbar: true, minimizable: false, transient: parent});
    f.display.focus_window = dialog;
    f.extension.enable();
    f.click();
    f.click();
    assert.equal(f.operations.at(-1), 'focus:dialog');
    f.extension.disable();
});

test('workspace removal drops snapshots; disable restores without focus and releases signals', async () => {
    const f = await setup();
    const first = f.add('first');
    const removed = f.add('removed', {workspace: f.workspaces[1]});
    f.extension.enable();
    f.switchWorkspace(1);
    f.click();
    f.switchWorkspace(0);
    f.click();
    f.manager.n_workspaces = 1;
    f.manager.emit('workspace-removed', 1);
    const corner = f.extension._corner;
    f.extension.disable();
    assert.equal(first.minimized, false);
    assert.equal(removed.minimized, true);
    assert.equal(corner.destroyed, true);
    assert.ok(!f.operations.some(operation => operation.startsWith('focus:') || operation.startsWith('raise:')));
    for (const emitter of [f.manager, f.display, f.layoutManager, f.overview, f.sessionMode, ...f.windows])
        assert.equal(emitter.signals.size, 0);
    f.extension.enable();
    f.extension.disable();
});
