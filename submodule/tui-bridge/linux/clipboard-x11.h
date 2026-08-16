#ifndef TUI_BRIDGE_CLIPBOARD_X11_H
#define TUI_BRIDGE_CLIPBOARD_X11_H

#include <stdbool.h>

bool x11_clipboard_available(void);
int x11_clipboard_input(const char *text, bool primary);
int x11_clipboard_output(bool primary, char **text_out);

#endif
