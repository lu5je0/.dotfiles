"""Use the phone's power key to blank or wake GNOME without locking or suspending."""

import logging
from contextlib import closing
import fcntl
import pwd
import struct
import subprocess
import time


DISPLAY = (
    "org.gnome.Mutter.DisplayConfig",
    "/org/gnome/Mutter/DisplayConfig",
    "org.gnome.Mutter.DisplayConfig",
)
SCREENSAVER = (
    "org.gnome.ScreenSaver",
    "/org/gnome/ScreenSaver",
    "org.gnome.ScreenSaver",
)
TRANSITION_TIMEOUT = 3.0
DEBOUNCE_SECONDS = 0.35
# Linux input.h: _IOW('E', 0xa0, int). Keep queued event times monotonic too.
EVIOCSCLOCKID = 0x400445A0


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


def display_mode():
    mode = int(session_bus("get-property", *DISPLAY, "PowerSaveMode").split()[1])
    if mode < 0:
        raise RuntimeError("Display power management unavailable")
    return mode


def wait_until(predicate):
    deadline = time.monotonic() + TRANSITION_TIMEOUT
    while not predicate():
        if time.monotonic() >= deadline:
            raise RuntimeError("GNOME display transition timed out")
        time.sleep(0.05)


def toggle_screen():
    target = 3 if display_mode() == 0 else 0
    greeter = command(
        "loginctl", "show-session", active_session(), "-p", "Class", "--value"
    ) == "greeter"
    locked = command(
        "loginctl", "show-session", active_session(), "-p", "LockedHint", "--value"
    ) == "yes"
    try:
        # Complete GNOME's asynchronous shield animation before changing power.
        # Never deactivate a manually locked session on wake.
        # GDM's shield contains the login dialog: deactivating it slides the
        # dialog offscreen. Its already-modal UI only needs panel power changes.
        if not greeter and (target == 3 or not locked):
            active = "true" if target == 3 else "false"
            session_bus("call", *SCREENSAVER, "SetActive", "b", active)
            wait_until(lambda: session_bus("call", *SCREENSAVER, "GetActive") == f"b {active}")

        # SetActive(false) alone can leave the shield inactive but the panel off.
        session_bus("set-property", *DISPLAY, "PowerSaveMode", "i", str(target))
        wait_until(lambda: display_mode() == target)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        # A failed animation should leave a usable display, not a black screen.
        try:
            session_bus("set-property", *DISPLAY, "PowerSaveMode", "i", "0")
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            logging.exception("Could not restore display power")
        raise
    logging.info("Display power %s", "off" if target else "on")


class PowerKey:
    def __init__(self):
        self.accept_after = 0.0

    def handle_release(self, timestamp):
        if timestamp < self.accept_after:
            return
        try:
            toggle_screen()
        finally:
            # Discard presses queued during the transition, including after errors.
            self.accept_after = time.monotonic() + DEBOUNCE_SECONDS


def main():
    from evdev import InputDevice, ecodes

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    handler = PowerKey()
    with closing(InputDevice("/dev/input/oneplus6-power")) as device:
        fcntl.ioctl(device.fd, EVIOCSCLOCKID, struct.pack("i", time.CLOCK_MONOTONIC))
        # Only grab the dedicated power button, leaving touch/volume inputs alone.
        # This also prevents GNOME's tablet policy from requesting suspend.
        device.grab()
        logging.info("Power key ready: %s", device.name)
        for event in device.read_loop():
            if event.type == ecodes.EV_KEY and event.code == ecodes.KEY_POWER and event.value == 0:
                try:
                    handler.handle_release(event.timestamp())
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                    logging.exception("Could not toggle the screen")


if __name__ == "__main__":
    main()
