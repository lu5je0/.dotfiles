#!/usr/bin/env python3
"""读取 XSettings，并通过 SDL 和可选 GTK3 查询应用实际获得的缩放比例。"""

import ctypes
import json
import struct
import sys


def read_xsettings(library):
    x11 = ctypes.CDLL(library)
    pointer = ctypes.c_void_p
    ulong = ctypes.c_ulong
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = pointer
    x11.XInternAtom.argtypes = [pointer, ctypes.c_char_p, ctypes.c_int]
    x11.XInternAtom.restype = ulong
    x11.XGetSelectionOwner.argtypes = [pointer, ulong]
    x11.XGetSelectionOwner.restype = ulong
    x11.XGetWindowProperty.argtypes = [
        pointer, ulong, ulong, ctypes.c_long, ctypes.c_long, ctypes.c_int, ulong,
        ctypes.POINTER(ulong), ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ulong), ctypes.POINTER(ulong), ctypes.POINTER(pointer),
    ]
    x11.XFree.argtypes = [pointer]
    x11.XCloseDisplay.argtypes = [pointer]
    display = x11.XOpenDisplay(None)
    if not display:
        raise RuntimeError("Cannot open the test X11 display")
    data = pointer()
    try:
        owner = x11.XGetSelectionOwner(
            display, x11.XInternAtom(display, b"_XSETTINGS_S0", 0)
        )
        if not owner:
            raise RuntimeError("No XSettings owner")
        actual_type, count, remaining = ulong(), ulong(), ulong()
        actual_format = ctypes.c_int()
        status = x11.XGetWindowProperty(
            display, owner, x11.XInternAtom(display, b"_XSETTINGS_SETTINGS", 0),
            0, 65536, 0, 0, ctypes.byref(actual_type), ctypes.byref(actual_format),
            ctypes.byref(count), ctypes.byref(remaining), ctypes.byref(data),
        )
        if status or actual_format.value != 8 or remaining.value:
            raise RuntimeError("Invalid XSettings property")
        blob = ctypes.string_at(data, count.value)
    finally:
        if data.value:
            x11.XFree(data)
        x11.XCloseDisplay(display)

    endian = "<" if blob[0] == 0 else ">"
    length = struct.unpack_from(endian + "I", blob, 8)[0]
    offset = 12
    settings = {}
    for _ in range(length):
        kind, _, size = struct.unpack_from(endian + "BBH", blob, offset)
        offset += 4
        name = blob[offset:offset + size].decode()
        offset = (offset + size + 3) & ~3
        offset += 4  # last-change serial
        if kind == 0:
            value = struct.unpack_from(endian + "i", blob, offset)[0]
            offset += 4
        elif kind == 1:
            size = struct.unpack_from(endian + "I", blob, offset)[0]
            offset += 4
            value = blob[offset:offset + size].decode()
            offset = (offset + size + 3) & ~3
        elif kind == 2:
            value = struct.unpack_from(endian + "4H", blob, offset)
            offset += 8
        else:
            raise RuntimeError(f"Unknown XSettings type {kind}")
        settings[name] = value
    keys = ("Gdk/WindowScalingFactor", "Gdk/UnscaledDPI", "Xft/DPI", "Gtk/CursorThemeSize")
    return {key: settings[key] for key in keys}


def content_scale(library):
    sdl = ctypes.CDLL(library)
    sdl.SDL_Init.argtypes = [ctypes.c_uint32]
    sdl.SDL_Init.restype = ctypes.c_bool
    sdl.SDL_GetPrimaryDisplay.restype = ctypes.c_uint32
    sdl.SDL_GetDisplayContentScale.argtypes = [ctypes.c_uint32]
    sdl.SDL_GetDisplayContentScale.restype = ctypes.c_float
    sdl.SDL_GetError.restype = ctypes.c_char_p
    if not sdl.SDL_Init(0x20):  # SDL_INIT_VIDEO
        raise RuntimeError(sdl.SDL_GetError().decode())
    try:
        display = sdl.SDL_GetPrimaryDisplay()
        if not display:
            raise RuntimeError(sdl.SDL_GetError().decode())
        return sdl.SDL_GetDisplayContentScale(display)
    finally:
        sdl.SDL_Quit()


def gtk_scale(library):
    gtk = ctypes.CDLL(library)
    pointer = ctypes.c_void_p
    gtk.gtk_init_check.argtypes = [pointer, pointer]
    gtk.gtk_init_check.restype = ctypes.c_int
    gtk.gdk_screen_get_default.restype = pointer
    gtk.gdk_screen_get_resolution.argtypes = [pointer]
    gtk.gdk_screen_get_resolution.restype = ctypes.c_double
    gtk.gdk_display_get_default.restype = pointer
    gtk.gdk_display_get_monitor.argtypes = [pointer, ctypes.c_int]
    gtk.gdk_display_get_monitor.restype = pointer
    gtk.gdk_monitor_get_scale_factor.argtypes = [pointer]
    gtk.gdk_monitor_get_scale_factor.restype = ctypes.c_int
    if not gtk.gtk_init_check(None, None):
        raise RuntimeError("Cannot initialize GTK3 on the test X11 display")
    screen = gtk.gdk_screen_get_default()
    monitor = gtk.gdk_display_get_monitor(gtk.gdk_display_get_default(), 0)
    if not screen or not monitor:
        raise RuntimeError("No GTK3 screen or monitor")
    dpi = gtk.gdk_screen_get_resolution(screen)
    window_scale = gtk.gdk_monitor_get_scale_factor(monitor)
    return {
        "window_scale": window_scale,
        "font_dpi": dpi,
        # Chromium's GTK3 X11 path combines the monitor scale and font DPI.
        "content_scale": window_scale * dpi / 96,
    }


if __name__ == "__main__":
    result = {
        "xsettings": read_xsettings(sys.argv[1]),
        "sdl_scale": content_scale(sys.argv[2]),
    }
    if len(sys.argv) > 3:
        result["gtk"] = gtk_scale(sys.argv[3])
    print(json.dumps(result))
