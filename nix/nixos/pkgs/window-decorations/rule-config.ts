import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {parseRules, type AppRule} from './app-rules.js';
import {getWindowIdentifiers} from '../shell/window-filter.js';

let rules: AppRule[] = [];
let monitor: Gio.FileMonitor | null = null;
let timeoutId = 0;
let service: Gio.DBusExportedObject | null = null;

export function currentRules(): AppRule[] { return rules; }

/** Watch the rules directory so atomic saves also reload. */
export function startRuleConfig(onChanged: () => void): void {
    stopRuleConfig();
    service = Gio.DBusExportedObject.wrapJSObject(`<node>
      <interface name="org.gnome.Shell.Extensions.WindowDecorations">
        <method name="ListApps"><arg type="s" direction="out"/></method>
      </interface>
    </node>`, {
        ListApps: () => JSON.stringify(global.get_window_actors().flatMap(actor => {
            const win = actor.metaWindow;
            return win ? [{title: win.title, identifiers: getWindowIdentifiers(win)}] : [];
        })),
    });
    service.export(Gio.DBus.session, '/org/gnome/Shell/Extensions/WindowDecorations');
    const path = GLib.build_filenamev([
        GLib.get_home_dir(), '.dotfiles', 'nix', 'nixos', 'pkgs', 'window-decorations', 'config.json',
    ]);
    const file = Gio.File.new_for_path(path);
    const reload = () => {
        try {
            const [, contents] = file.load_contents(null);
            rules = parseRules(new TextDecoder().decode(contents));
            onChanged();
        } catch (error) {
            console.error(`[WindowDecorations] ${path}: ${String(error)}; keeping last valid rules`);
        }
    };
    reload();
    try {
        monitor = file.get_parent()!.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        monitor.connect('changed', (_monitor, changed, other) => {
            if (!changed.equal(file) && !other?.equal(file)) return;
            if (timeoutId) GLib.source_remove(timeoutId);
            timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
                timeoutId = 0;
                reload();
                return GLib.SOURCE_REMOVE;
            });
        });
    } catch (error) {
        console.error(`[WindowDecorations] Cannot watch ${path}: ${String(error)}`);
    }
}

export function stopRuleConfig(): void {
    service?.unexport();
    service = null;
    monitor?.cancel();
    monitor = null;
    if (timeoutId) GLib.source_remove(timeoutId);
    timeoutId = 0;
    rules = [];
}
