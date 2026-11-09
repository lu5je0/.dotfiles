import Gio from 'gi://Gio';
import GioUnix from 'gi://GioUnix';

// The desktop entry may be cached by Shell; this file is read on every launch.
const [filename, action, ...arguments_] = ARGV;
const uris = arguments_.map(argument => Gio.File.new_for_commandline_arg(argument).get_uri());
const info = GioUnix.DesktopAppInfo.new_from_filename(filename);
if (!info)
    throw new Error(`Application is no longer available: ${filename}`);

const context = new Gio.AppLaunchContext();
if (action === 'launch') {
    await new Promise((resolve, reject) => {
        info.launch_uris_async(uris, context, null, (app, result) => {
            try {
                resolve(app.launch_uris_finish(result));
            } catch (error) {
                reject(error);
            }
        });
    });
} else if (action.startsWith('action:')) {
    const name = action.slice('action:'.length);
    if (!info.list_actions().includes(name))
        throw new Error(`Desktop action is no longer available: ${name}`);
    info.launch_action(name, context);
    if (info.get_boolean('DBusActivatable'))
        Gio.bus_get_sync(Gio.BusType.SESSION, null).flush_sync(null);
} else {
    throw new Error(`Unknown launch operation: ${action}`);
}
