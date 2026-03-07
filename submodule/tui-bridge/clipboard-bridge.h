#ifndef TUI_BRIDGE_CLIPBOARD_H
#define TUI_BRIDGE_CLIPBOARD_H

int bridge_clipboard_output(const char *eol, char **text_out);
int bridge_clipboard_input(const char *text);

#endif
