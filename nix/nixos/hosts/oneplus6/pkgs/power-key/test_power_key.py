"""Regression tests for delayed GNOME transitions and queued power-key presses."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("power_key", Path(__file__).with_name("power-key.py"))
power_key = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power_key)


class Clock:
    def __init__(self):
        self.now = 10.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class Gnome:
    def __init__(self, clock, mode=0, active=False, locked=False):
        self.clock = clock
        self.mode = mode
        self.active = active
        self.locked = locked
        self.pending = None
        self.calls = []
        self.stuck = False
        self.session_class = "user"

    def bus(self, *args):
        self.calls.append(args)
        if self.pending and self.clock.now >= self.pending[0]:
            self.active = self.pending[1]
            self.pending = None
        if args[0] == "get-property":
            return f"i {self.mode}"
        if args[0] == "set-property":
            self.mode = int(args[-1])
            if self.mode == 3 and self.session_class != "greeter":
                assert self.active, "Panel turned off before the shield was ready"
            return ""
        if "SetActive" in args:
            assert self.session_class != "greeter", "ScreenSaver must not move GDM's login dialog"
            if not self.stuck:
                self.pending = (self.clock.now + 0.3, args[-1] == "true")
            return ""
        if args[-1] == "GetActive":
            return f"b {str(self.active).lower()}"
        raise AssertionError(args)


class PowerKeyTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.gnome = Gnome(self.clock)
        for target, replacement in (
            ("session_bus", self.gnome.bus),
            ("active_session", lambda: "test-session"),
            ("command", self.session_property),
        ):
            patcher = patch.object(power_key, target, replacement)
            patcher.start()
            self.addCleanup(patcher.stop)
        for name in ("monotonic", "sleep"):
            patcher = patch.object(power_key.time, name, getattr(self.clock, name))
            patcher.start()
            self.addCleanup(patcher.stop)

    def session_property(self, *args):
        if "Class" in args:
            return self.gnome.session_class
        if "LockedHint" in args:
            return "yes" if self.gnome.locked else "no"
        raise AssertionError(args)

    def test_greeter_blank_wake_cycles_preserve_login_dialog(self):
        self.gnome.session_class = "greeter"
        for _ in range(3):
            power_key.toggle_screen()
            self.assertEqual(self.gnome.mode, 3)
            power_key.toggle_screen()
            self.assertEqual(self.gnome.mode, 0)
        self.assertFalse(any("SetActive" in call for call in self.gnome.calls))

    def test_greeter_wake_keeps_existing_shield_state(self):
        self.gnome.session_class = "greeter"
        self.gnome.mode = 3
        self.gnome.active = True
        power_key.toggle_screen()
        self.assertEqual(self.gnome.mode, 0)
        self.assertTrue(self.gnome.active)

    def test_inactive_shield_with_dark_panel_is_recovered(self):
        self.gnome.mode = 3
        power_key.toggle_screen()
        self.assertEqual(self.gnome.mode, 0)
        self.assertFalse(self.gnome.active)

    def test_delayed_animation_finishes_before_panel_is_switched(self):
        power_key.toggle_screen()
        self.assertEqual(self.gnome.mode, 3)
        self.assertTrue(self.gnome.active)
        power_key.toggle_screen()
        self.assertEqual(self.gnome.mode, 0)
        self.assertFalse(self.gnome.active)
        self.assertIsNone(self.gnome.pending)

    def test_queued_presses_are_dropped_and_next_fresh_press_wakes(self):
        handler = power_key.PowerKey()
        handler.handle_release(self.clock.now)
        self.assertEqual(self.gnome.mode, 3)
        calls = len(self.gnome.calls)
        for timestamp in (10.05, 10.1, 10.2, 10.3, 10.4):
            handler.handle_release(timestamp)
        self.assertEqual(len(self.gnome.calls), calls)
        self.clock.now = handler.accept_after + 0.01
        handler.handle_release(self.clock.now)
        self.assertEqual(self.gnome.mode, 0)

    def test_manual_lock_is_preserved_when_waking(self):
        self.gnome.mode = 3
        self.gnome.active = self.gnome.locked = True
        power_key.toggle_screen()
        self.assertEqual(self.gnome.mode, 0)
        self.assertTrue(self.gnome.active)
        self.assertFalse(any("SetActive" in call for call in self.gnome.calls))

    def test_animation_timeout_restores_panel_and_allows_retry(self):
        self.gnome.stuck = True
        handler = power_key.PowerKey()
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            handler.handle_release(self.clock.now)
        self.assertEqual(self.gnome.mode, 0)
        self.gnome.stuck = False
        self.clock.now = handler.accept_after + 0.01
        handler.handle_release(self.clock.now)
        self.assertEqual(self.gnome.mode, 3)

    def test_touch_is_blocked_before_blank_and_restored_after_wake(self):
        events = []

        class Touch:
            def block(touch):
                events.append(("block", self.gnome.mode, self.gnome.active))

            def close(touch):
                events.append(("restore", self.gnome.mode, self.gnome.active))

        power_key.toggle_screen(Touch())
        self.assertEqual(events, [("block", 0, False)])
        power_key.toggle_screen(Touch())
        self.assertEqual(events[-1], ("restore", 0, False))

    def test_failed_transition_restores_touch_along_with_panel(self):
        from unittest.mock import Mock
        touch = Mock()
        self.gnome.stuck = True
        with self.assertRaises(RuntimeError):
            power_key.toggle_screen(touch)
        touch.block.assert_called_once()
        touch.close.assert_called_once()
        self.assertEqual(self.gnome.mode, 0)

    def test_cannot_blank_if_touch_grab_fails(self):
        from unittest.mock import Mock
        touch = Mock()
        touch.block.side_effect = OSError("Touch device busy")
        with self.assertRaises(OSError):
            power_key.toggle_screen(touch)
        self.assertEqual(self.gnome.mode, 0)
        self.assertFalse(self.gnome.active)
        touch.close.assert_called_once()


class TouchGuardTests(unittest.TestCase):
    def test_grab_is_idempotent_and_descriptor_is_closed_on_wake(self):
        from unittest.mock import Mock
        device = Mock()
        factory = Mock(return_value=device)
        guard = power_key.TouchGuard(factory, lambda: "/dev/input/test-touch")
        guard.block()
        guard.block()
        factory.assert_called_once_with("/dev/input/test-touch")
        device.grab.assert_called_once()
        guard.close()
        guard.close()
        device.close.assert_called_once()
        self.assertIsNone(guard.device)

    def test_failed_grab_does_not_leak_descriptor(self):
        from unittest.mock import Mock
        device = Mock()
        device.grab.side_effect = OSError("Busy")
        guard = power_key.TouchGuard(lambda path: device, lambda: "/dev/input/test-touch")
        with self.assertRaises(OSError):
            guard.block()
        device.close.assert_called_once()
        self.assertIsNone(guard.device)

    def test_find_touchscreen_without_assuming_input_number(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for node, name in (("event2", "pm8941_pwrkey"), ("event8", "Synaptics S3706B")):
                (root / node / "device").mkdir(parents=True)
                (root / node / "device/name").write_text(name)
            self.assertEqual(power_key.touchscreen_path(root), Path("/dev/input/event8"))
            (root / "event9/device").mkdir(parents=True)
            (root / "event9/device/name").write_text("Synaptics S3706B")
            with self.assertRaises(RuntimeError):
                power_key.touchscreen_path(root)


if __name__ == "__main__":
    unittest.main()
