#ifndef TUI_BRIDGE_IM_H
#define TUI_BRIDGE_IM_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __APPLE__
// Returns "eng"
const char *im_normal(void);
// Returns "chi" or "eng"
const char *im_insert(void);
// Enable/disable ime watch (emit events on input source change)
void im_watch(bool enable);
// Run interactive mode with RunLoop support (for notifications)
void im_run_interactive(void (*line_handler)(const char *line));
#else
int bridge_ime_call(const char *method, char *state_out, size_t state_out_sz);
#endif

#endif
