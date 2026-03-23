#ifndef TUI_BRIDGE_REQUEST_DISPATCH_H
#define TUI_BRIDGE_REQUEST_DISPATCH_H

#include "third_party/cjson/cJSON.h"

typedef enum {
  BRIDGE_DISPATCH_EMPTY = 0,
  BRIDGE_DISPATCH_STATE = 1,
  BRIDGE_DISPATCH_TEXT = 2,
  BRIDGE_DISPATCH_ERROR = 3,
} bridge_dispatch_kind_t;

typedef struct {
  bridge_dispatch_kind_t kind;
  const char *error_code;
  char message[128];
  char state[16];
  char *text;
} bridge_dispatch_result_t;

void bridge_dispatch_result_init(bridge_dispatch_result_t *result);
void bridge_dispatch_result_free(bridge_dispatch_result_t *result);

void bridge_dispatch_request(const char *module, const char *method, cJSON *params,
                             bridge_dispatch_result_t *result);

#endif
