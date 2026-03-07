#ifndef TUI_BRIDGE_IM_H
#define TUI_BRIDGE_IM_H

#include <stddef.h>

int bridge_ime_call(const char *method, char *state_out, size_t state_out_sz);

#endif
