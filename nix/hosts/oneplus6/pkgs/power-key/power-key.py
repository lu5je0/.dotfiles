"""Use the phone's power key to blank or wake GNOME without locking or suspending."""

import logging
from contextlib import closing
import fcntl
from pathlib import Path
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


def touchscreen_path(root=Path("/sys/class/input")):
    matches = []
    for node in root.glob("event*"):
        try:
            if (node / "device/name").read_text().strip() == "Synaptics S3706B":
                matches.append(Path("/dev/input") / node.name)
        except OSError:
            continue
    if len(matches) != 1:
        raise RuntimeError("Cannot uniquely identify the OP6 touchscreen")
    return matches[0]


class TouchGuard:
    """Suppress touch wakeups only while our power key has blanked the panel.

    Closing the evdev descriptor releases the grab automatically, including
    if this service dies. Never grab the volume keys or the power key here.
    """
    def __init__(self, factory=None, locate=touchscreen_path):
        self.factory, self.locate = factory, locate
        self.device = None

    def block(self):
        if self.device is not None:
            return
        if self.factory is None:
            from evdev import InputDevice
            self.factory = InputDevice
        device = self.factory(self.locate())
        try:
            device.grab()
        except BaseException:
            device.close()
            raise
        self.device = device
        logging.info("Touchscreen blocked while panel is off")

    def close(self):
        if self.device is not None:
            device, self.device = self.device, None
            device.close()
            logging.info("Touchscreen restored")


def toggle_screen(touch=None):
    target = 3 if display_mode() == 0 else 0
    greeter = command(
        "loginctl", "show-session", active_session(), "-p", "Class", "--value"
    ) == "greeter"
    locked = command(
        "loginctl", "show-session", active_session(), "-p", "LockedHint", "--value"
    ) == "yes"
    try:
        # Grab before GNOME starts blanking: touches must not dismiss the
        # shield or turn the panel back on during its animation.
        if target == 3 and touch is not None:
            touch.block()
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
        if target == 0 and touch is not None:
            touch.close()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        # A failed animation should leave a usable display, not a black screen.
        try:
            session_bus("set-property", *DISPLAY, "PowerSaveMode", "i", "0")
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            logging.exception("Could not restore display power")
        finally:
            if touch is not None:
                touch.close()
        raise
    logging.info("Display power %s", "off" if target else "on")


class PowerKey:
    def __init__(self, touch=None):
        self.accept_after = 0.0
        self.touch = touch

    def handle_release(self, timestamp):
        if timestamp < self.accept_after:
            return
        try:
            toggle_screen(self.touch)
        finally:
            # Discard presses queued during the transition, including after errors.
            self.accept_after = time.monotonic() + DEBOUNCE_SECONDS


def main():
    from evdev import InputDevice, ecodes

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    with closing(TouchGuard()) as touch, closing(InputDevice("/dev/input/oneplus6-power")) as device:
        handler = PowerKey(touch)
        fcntl.ioctl(device.fd, EVIOCSCLOCKID, struct.pack("i", time.CLOCK_MONOTONIC))
        # Keep the power key grabbed. Touch is grabbed only while blanked;
        # volume inputs remain unaffected.
        # This also prevents GNOME's tablet policy from requesting suspend.
        device.grab()
        try:
            if display_mode() != 0:
                touch.block()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            # At boot GDM may not have created a session yet. The first
            # power-key transition will initialise the guard in that case.
            logging.info("Display session not ready; waiting for the power key")
        logging.info("Power key ready: %s", device.name)
        for event in device.read_loop():
            if event.type == ecodes.EV_KEY and event.code == ecodes.KEY_POWER and event.value == 0:
                try:
                    handler.handle_release(event.timestamp())
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                    logging.exception("Could not toggle the screen")


if __name__ == "__main__":
    main()
