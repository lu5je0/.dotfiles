import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Pointer travel per unit of touchpad swipe delta. Touchpad deltas already
// arrive in roughly pixel-sized units, so this only trims the speed.
const DRAG_SPEED = 1.0;

// A drag with no swipe activity at all for this long is cut loose, so a lost
// end-of-gesture event can never strand the button in the pressed state.
const STUCK_DRAG_TIMEOUT_MS = 2000;

// Lifting the fingers holds the drag open this long instead of dropping it
// straight away, so the fingers can be repositioned and the same drag carried
// on — the trackpad equivalent of lifting and re-placing a mouse. Putting
// three fingers back down inside the window resumes; letting it lapse commits.
const GRACE_PERIOD_MS = 300;

const MIN_WINDOW_SIZE = 50;

// Meta.GrabOp packs the resize edges into bit flags above the op id.
const EDGE_W = 0x1000;
const EDGE_E = 0x2000;
const EDGE_S = 0x4000;
const EDGE_N = 0x8000;
const EDGE_MASK = EDGE_W | EDGE_E | EDGE_S | EDGE_N;

// GNOME's overview and workspace-switch touchpad swipes are both driven by
// TouchpadSwipeGesture objects that accept 3- and 4-finger swipes alike, which
// is why the two finger counts behave identically by default. To reclaim 3
// fingers we mute those gestures for the duration of a 3-finger swipe and
// unmute them when it ends, leaving other finger counts on GNOME's own code.
//
// Muting via the `enabled` property rather than patching their handler: those
// handlers are connected as pre-bound methods at shell startup, so replacing
// the method afterwards would not affect the live connection, and our own
// captured-event handler is connected later and therefore runs after theirs.
function getTouchpadGestures() {
    return [
        Main.overview._swipeTracker?._touchpadGesture,
        Main.wm._workspaceAnimation?._swipeTracker?._touchpadGesture,
    ].filter(gesture => gesture);
}

function grabOpKind(op) {
    if (op === Meta.GrabOp.MOVING ||
        op === Meta.GrabOp.MOVING_UNCONSTRAINED ||
        op === Meta.GrabOp.KEYBOARD_MOVING)
        return 'move';
    if (op & EDGE_MASK)
        return 'resize';
    return null;
}

export default class ThreeFingerDragExtension extends Extension {
    enable() {
        this._active = false;
        this._buttonDown = false;
        this._windowDrag = null;
        this._graceId = null;
        this._watchdogId = null;

        const seat = Clutter.get_default_backend().get_default_seat();
        this._virtualDevice = seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE);

        this._nativeGestures = getTouchpadGestures();

        this._capturedEventId = global.stage.connect(
            'captured-event', this._onCapturedEvent.bind(this));
        this._grabBeginId = global.display.connect(
            'grab-op-begin', this._onGrabOpBegin.bind(this));
    }

    disable() {
        if (this._capturedEventId) {
            global.stage.disconnect(this._capturedEventId);
            this._capturedEventId = null;
        }
        if (this._grabBeginId) {
            global.display.disconnect(this._grabBeginId);
            this._grabBeginId = null;
        }

        this._endDrag();
        this._nativeGestures = null;
        this._virtualDevice = null;
    }

    _muteNativeGestures(muted) {
        for (const gesture of this._nativeGestures)
            gesture.enabled = !muted;
    }

    _onCapturedEvent(actor, event) {
        if (event.type() !== Clutter.EventType.TOUCHPAD_SWIPE ||
            event.get_touchpad_gesture_finger_count() !== 3)
            return Clutter.EVENT_PROPAGATE;

        switch (event.get_gesture_phase()) {
        case Clutter.TouchpadGesturePhase.BEGIN:
            this._beginDrag(event.get_time());
            break;
        case Clutter.TouchpadGesturePhase.UPDATE:
            this._updateDrag(event);
            break;
        default:
            this._beginGracePeriod();
            break;
        }

        // Deliberately propagates: swallowing the swipe leaves mutter's own
        // gesture bookkeeping without a begin, and it then discards the
        // matching end event, stranding the button in the pressed state.
        return Clutter.EVENT_PROPAGATE;
    }

    // A window move/resize grab starves the shell of input events entirely —
    // no swipes, no motion — so the drag would freeze a few milliseconds in
    // and never see its own end. Take the window over instead: dropping the
    // button ends mutter's grab, which restores the event stream, and the
    // window then follows the swipe deltas directly.
    _onGrabOpBegin(display, window, op) {
        if (!this._active || this._windowDrag || !window)
            return;

        const kind = grabOpKind(op);
        if (!kind ||
            (kind === 'move' && !window.allows_move()) ||
            (kind === 'resize' && !window.allows_resize()))
            return;

        this._windowDrag = {
            window,
            op,
            kind,
            rect: window.get_frame_rect(),
            dx: 0,
            dy: 0,
        };

        // Deferred so mutter finishes emitting grab-op-begin before the
        // release that tears the grab back down.
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._releaseButton();
            return GLib.SOURCE_REMOVE;
        });
    }

    _beginDrag(time) {
        if (this._graceId) {
            this._resumeDrag();
            return;
        }
        if (this._active)
            return;

        this._active = true;
        this._buttonDown = true;
        this._muteNativeGestures(true);
        this._virtualDevice.notify_button(time, Clutter.BUTTON_PRIMARY, Clutter.ButtonState.PRESSED);
        this._resetWatchdog();
    }

    _beginGracePeriod() {
        if (!this._active || this._graceId)
            return;

        this._clearWatchdog();
        this._graceId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, GRACE_PERIOD_MS, () => {
                this._graceId = null;
                this._endDrag();
                return GLib.SOURCE_REMOVE;
            });
    }

    _resumeDrag() {
        this._clearGracePeriod();

        // The window kept moving under the old anchor, so re-anchor to where
        // it sits now; otherwise it would snap back by the accumulated delta.
        if (this._windowDrag) {
            this._windowDrag.rect = this._windowDrag.window.get_frame_rect();
            this._windowDrag.dx = 0;
            this._windowDrag.dy = 0;
        }

        this._resetWatchdog();
    }

    _clearGracePeriod() {
        if (this._graceId) {
            GLib.source_remove(this._graceId);
            this._graceId = null;
        }
    }

    _updateDrag(event) {
        if (!this._active)
            return;

        this._resetWatchdog();

        const [rawDx, rawDy] = event.get_gesture_motion_delta();
        const dx = rawDx * DRAG_SPEED;
        const dy = rawDy * DRAG_SPEED;

        if (this._windowDrag)
            this._applyWindowDrag(dx, dy);

        this._virtualDevice.notify_relative_motion(event.get_time(), dx, dy);
    }

    _applyWindowDrag(dx, dy) {
        const drag = this._windowDrag;
        drag.dx += dx;
        drag.dy += dy;

        const { x, y, width, height } = drag.rect;

        if (drag.kind === 'move') {
            drag.window.move_frame(true, Math.round(x + drag.dx), Math.round(y + drag.dy));
            return;
        }

        let newX = x, newY = y, newWidth = width, newHeight = height;
        if (drag.op & EDGE_E)
            newWidth = width + drag.dx;
        if (drag.op & EDGE_W) {
            newX = x + drag.dx;
            newWidth = width - drag.dx;
        }
        if (drag.op & EDGE_S)
            newHeight = height + drag.dy;
        if (drag.op & EDGE_N) {
            newY = y + drag.dy;
            newHeight = height - drag.dy;
        }

        drag.window.move_resize_frame(true,
            Math.round(newX), Math.round(newY),
            Math.round(Math.max(newWidth, MIN_WINDOW_SIZE)),
            Math.round(Math.max(newHeight, MIN_WINDOW_SIZE)));
    }

    _releaseButton() {
        if (!this._buttonDown)
            return;

        this._buttonDown = false;
        this._virtualDevice.notify_button(
            global.get_current_time(), Clutter.BUTTON_PRIMARY, Clutter.ButtonState.RELEASED);
    }

    _endDrag() {
        if (!this._active)
            return;

        this._active = false;
        this._windowDrag = null;
        this._clearGracePeriod();
        this._clearWatchdog();
        this._releaseButton();
        this._muteNativeGestures(false);
    }

    _resetWatchdog() {
        this._clearWatchdog();
        this._watchdogId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, STUCK_DRAG_TIMEOUT_MS, () => {
                this._watchdogId = null;
                this._endDrag();
                return GLib.SOURCE_REMOVE;
            });
    }

    _clearWatchdog() {
        if (this._watchdogId) {
            GLib.source_remove(this._watchdogId);
            this._watchdogId = null;
        }
    }
}
