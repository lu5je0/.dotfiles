"""Use the phone's power key to lock/blank or wake GNOME without suspending."""

import logging
from contextlib import closing
import pwd
import subprocess
import time

from evdev import InputDevice, ecodes


def command(*args):
    return subprocess.check_output(args, text=True, timeout=5).strip()


def active_session():
    session = command("loginctl", "show-seat", "seat0", "-p", "ActiveSession", "--value")
    if not session:
        raise RuntimeError("No active graphical session")
    return session


def session_bus(*args):
    session = active_session()
    uid = int(command("loginctl", "show-session", session, "-p", "User", "--value"))
    user = pwd.getpwuid(uid).pw_name
    return command(
        "runuser", "-u", user, "--", "env",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus",
        "busctl", "--user", *args,
    )


def toggle_screen():
    display = (
        "org.gnome.Mutter.DisplayConfig",
        "/org/gnome/Mutter/DisplayConfig",
        "org.gnome.Mutter.DisplayConfig",
    )
    mode = int(session_bus("get-property", *display, "PowerSaveMode").split()[1])
    if mode < 0:
        raise RuntimeError("Display power management unavailable")
    if mode == 0:
        # logind's lock signal returns immediately even if GNOME is already
        # locked; ScreenSaver.Lock may leave its D-Bus invocation pending.
        command("loginctl", "lock-session", active_session())
        # Let the lock screen become visible before powering down the panel.
        time.sleep(0.2)
    target = 3 if mode == 0 else 0
    session_bus("set-property", *display, "PowerSaveMode", "i", str(target))
    logging.info("Display power %s", "off (locked)" if target else "on")


logging.basicConfig(level=logging.INFO, format="%(message)s")
with closing(InputDevice("/dev/input/oneplus6-power")) as device:
    # Only grab the dedicated power button, leaving touch/volume inputs alone.
    # This also prevents GNOME's tablet policy from requesting suspend.
    device.grab()
    logging.info("Power key ready: %s", device.name)
    for event in device.read_loop():
        if event.type == ecodes.EV_KEY and event.code == ecodes.KEY_POWER and event.value == 0:
            try:
                toggle_screen()
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                logging.exception("Could not toggle the screen")
