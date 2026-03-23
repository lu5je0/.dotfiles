#ifndef TUI_BRIDGE_IM_H
#define TUI_BRIDGE_IM_H

#include <stdbool.h>
#include <stddef.h>

void bridge_emit_ime_changed(const char *source_id);
void bridge_emit_ime_changed_state(const char *state);

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
int bridge_ime_normal(char *state_out, size_t state_out_sz);
int bridge_ime_insert(char *state_out, size_t state_out_sz);
int bridge_ime_watch(bool enable);
unsigned long bridge_ime_watch_error(void);
const char *bridge_ime_watch_error_step(void);
void bridge_ime_shutdown(void);
#endif

#endif
