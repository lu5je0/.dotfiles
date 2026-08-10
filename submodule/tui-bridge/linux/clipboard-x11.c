// X11 clipboard fallback for compositors that do not expose data-control
// but run an XWayland server (e.g. GNOME on Wayland). This talks directly
// to the X server via Xlib and does not spawn external processes.
//
// input forks a small daemon that owns the CLIPBOARD selection and serves
// SelectionRequest events until it loses the selection. output opens a
// short-lived connection, converts the current selection and reads it back.
//
// Limitations:
// - Only UTF-8 text is supported.
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/types.h>
#include <unistd.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>

#include "clipboard-x11.h"
#include "../bridge-status.h"

#define X11_IO_TIMEOUT_MS 1000
#define MAX_X11_TEXT (64 * 1024 * 1024)

static bool x11_display_available(void) {
  if (!getenv("DISPLAY")) {
    return false;
  }
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) {
    return false;
  }
  XCloseDisplay(dpy);
  return true;
}

bool x11_clipboard_available(void) { return x11_display_available(); }

static Display *x11_open_display(void) {
  if (!getenv("DISPLAY")) {
    return NULL;
  }
  return XOpenDisplay(NULL);
}

static Window create_invisible_window(Display *dpy) {
  int screen = DefaultScreen(dpy);
  Window root = RootWindow(dpy, screen);
  Window win = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
  if (win != None) {
    XSelectInput(dpy, win, PropertyChangeMask);
  }
  return win;
}

static Atom get_atoms(Display *dpy, const char *name) {
  return XInternAtom(dpy, name, False);
}

static char *read_property(Display *dpy, Window win, Atom property) {
  Atom actual_type;
  int actual_format;
  unsigned long nitems;
  unsigned long bytes_after;
  unsigned char *data = NULL;

  int rc = XGetWindowProperty(dpy, win, property, 0, MAX_X11_TEXT / 4, True,
                              AnyPropertyType, &actual_type, &actual_format,
                              &nitems, &bytes_after, &data);
  if (rc != Success || !data) {
    return NULL;
  }

  size_t len = (size_t)nitems * (actual_format == 16 ? 2
                                 : actual_format == 32 ? 4
                                                       : 1);
  char *text = malloc(len + 1);
  if (text) {
    memcpy(text, data, len);
    text[len] = '\0';
  }
  XFree(data);
  return text;
}

static bool pump_selection_notify(Display *dpy, long timeout_ms,
                                  XEvent *out_event) {
  int fd = XConnectionNumber(dpy);
  long elapsed = 0;
  while (elapsed < timeout_ms) {
    while (XPending(dpy) > 0) {
      XEvent e;
      XNextEvent(dpy, &e);
      if (e.type == SelectionNotify) {
        *out_event = e;
        return true;
      }
    }
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    struct timeval tv = {0, 10 * 1000}; // 10ms
    int n = select(fd + 1, &fds, NULL, NULL, &tv);
    if (n < 0 && errno != EINTR) {
      return false;
    }
    elapsed += 10;
  }
  return false;
}

int x11_clipboard_output(char **text_out) {
  if (!text_out) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }
  *text_out = NULL;

  Display *dpy = x11_open_display();
  if (!dpy) {
    return BRIDGE_STATUS_FAILED;
  }

  Window win = create_invisible_window(dpy);
  if (win == None) {
    XCloseDisplay(dpy);
    return BRIDGE_STATUS_FAILED;
  }

  Atom clipboard = get_atoms(dpy, "CLIPBOARD");
  Atom utf8 = get_atoms(dpy, "UTF8_STRING");
  Atom string_atom = get_atoms(dpy, "STRING");
  Atom property = get_atoms(dpy, "TUI_BRIDGE_CLIP");

  Window owner = XGetSelectionOwner(dpy, clipboard);
  if (owner == None) {
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    *text_out = strdup("");
    return *text_out ? BRIDGE_STATUS_OK : BRIDGE_STATUS_FAILED;
  }

  XConvertSelection(dpy, clipboard, utf8, property, win, CurrentTime);
  XFlush(dpy);

  XEvent event;
  if (!pump_selection_notify(dpy, X11_IO_TIMEOUT_MS, &event)) {
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    return BRIDGE_STATUS_FAILED;
  }

  if (event.xselection.property == None) {
    XConvertSelection(dpy, clipboard, string_atom, property, win, CurrentTime);
    XFlush(dpy);
    if (!pump_selection_notify(dpy, X11_IO_TIMEOUT_MS, &event)) {
      XDestroyWindow(dpy, win);
      XCloseDisplay(dpy);
      return BRIDGE_STATUS_FAILED;
    }
    if (event.xselection.property == None) {
      XDestroyWindow(dpy, win);
      XCloseDisplay(dpy);
      *text_out = strdup("");
      return *text_out ? BRIDGE_STATUS_OK : BRIDGE_STATUS_FAILED;
    }
  }

  char *text = read_property(dpy, win, event.xselection.property);
  XDestroyWindow(dpy, win);
  XCloseDisplay(dpy);
  if (!text) {
    return BRIDGE_STATUS_FAILED;
  }

  *text_out = text;
  return BRIDGE_STATUS_OK;
}

static void send_selection_notify(Display *dpy,
                                  XSelectionRequestEvent *req, Atom property) {
  XSelectionEvent send;
  send.type = SelectionNotify;
  send.requestor = req->requestor;
  send.selection = req->selection;
  send.target = req->target;
  send.time = req->time;
  send.property = property;
  XSendEvent(dpy, req->requestor, True, 0, (XEvent *)&send);
}

static void serve_selection(Display *dpy, Window win, Atom clipboard,
                            const char *text) {
  Atom utf8 = get_atoms(dpy, "UTF8_STRING");
  Atom string_atom = get_atoms(dpy, "STRING");
  Atom text_atom = get_atoms(dpy, "TEXT");
  Atom targets_atom = get_atoms(dpy, "TARGETS");

  XSetSelectionOwner(dpy, clipboard, win, CurrentTime);
  XFlush(dpy);

  if (XGetSelectionOwner(dpy, clipboard) != win) {
    return;
  }

  size_t text_len = strlen(text);
  bool running = true;
  while (running) {
    int fd = XConnectionNumber(dpy);
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    struct timeval tv = {1, 0}; // 1s
    int n = select(fd + 1, &fds, NULL, NULL, &tv);
    if (n < 0 && errno != EINTR) {
      break;
    }

    while (XPending(dpy) > 0) {
      XEvent e;
      XNextEvent(dpy, &e);
      if (e.type == SelectionRequest) {
        XSelectionRequestEvent *req = &e.xselectionrequest;
        Atom target = req->target;
        Atom prop = req->property;
        Atom reply_prop = prop == None ? target : prop;

        if (target == targets_atom) {
          Atom targets[] = {targets_atom, utf8, string_atom, text_atom,
                            XA_STRING};
          XChangeProperty(dpy, req->requestor, reply_prop, XA_ATOM, 32,
                          PropModeReplace, (unsigned char *)targets,
                          sizeof(targets) / sizeof(targets[0]));
          send_selection_notify(dpy, req, reply_prop);
        } else if (target == utf8 || target == string_atom ||
                   target == text_atom || target == XA_STRING) {
          XChangeProperty(dpy, req->requestor, reply_prop, utf8, 8,
                          PropModeReplace, (unsigned char *)text,
                          (int)text_len);
          send_selection_notify(dpy, req, reply_prop);
        } else {
          send_selection_notify(dpy, req, None);
        }
        XFlush(dpy);
      } else if (e.type == SelectionClear) {
        running = false;
      }
    }
  }
}

int x11_clipboard_input(const char *text) {
  if (!text) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  char *copy = strdup(text);
  if (!copy) {
    return BRIDGE_STATUS_FAILED;
  }

  pid_t pid = fork();
  if (pid < 0) {
    free(copy);
    return BRIDGE_STATUS_FAILED;
  }

  if (pid > 0) {
    // Parent: selection daemon is running.
    free(copy);
    return BRIDGE_STATUS_OK;
  }

  // Child: become a daemon and serve the selection.
  signal(SIGHUP, SIG_IGN);
  if (setsid() < 0) {
    _exit(1);
  }

  Display *dpy = x11_open_display();
  if (!dpy) {
    _exit(1);
  }

  Window win = create_invisible_window(dpy);
  if (win == None) {
    XCloseDisplay(dpy);
    _exit(1);
  }

  Atom clipboard = get_atoms(dpy, "CLIPBOARD");
  serve_selection(dpy, win, clipboard, copy);

  XDestroyWindow(dpy, win);
  XCloseDisplay(dpy);
  free(copy);
  _exit(0);
}
