"""Use the phone's power key to blank or wake GNOME without locking or suspending."""

import logging
from contextlib import closing
import pwd
import subprocess

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
    if mode != 0 and command(
        "loginctl", "show-session", active_session(), "-p", "LockedHint", "--value"
    ) == "yes":
        # A manually locked session must still require authentication after wake.
        session_bus("set-property", *display, "PowerSaveMode", "i", "0")
    else:
        # Let GNOME prepare/clear its screen shield before changing panel power.
        # Directly powering off an unlocked desktop can crash Mutter on this phone.
        session_bus(
            "call", "org.gnome.ScreenSaver", "/org/gnome/ScreenSaver",
            "org.gnome.ScreenSaver", "SetActive", "b", "true" if mode == 0 else "false",
        )
    logging.info("Display power %s", "off" if mode == 0 else "on")


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
