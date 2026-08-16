#ifndef TUI_BRIDGE_CLIPBOARD_H
#define TUI_BRIDGE_CLIPBOARD_H

// Which selection a request targets. Only X11/Wayland have two of them;
// platforms with a single system clipboard (Windows, macOS) serve both from
// the same pasteboard and ignore this.
typedef enum {
  BRIDGE_SELECTION_REGULAR = 0,
  BRIDGE_SELECTION_PRIMARY = 1,
} bridge_selection_t;

int bridge_clipboard_output(const char *eol, bridge_selection_t selection,
                           char **text_out);
int bridge_clipboard_input(const char *text, bridge_selection_t selection);

#endif
