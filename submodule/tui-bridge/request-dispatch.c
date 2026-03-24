#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bridge-status.h"
#include "clipboard-bridge.h"
#include "im.h"
#include "request-dispatch.h"

#define MAX_TEXT 32768

static void set_error(bridge_dispatch_result_t *result, const char *code,
                      const char *message) {
  result->kind = BRIDGE_DISPATCH_ERROR;
  result->error_code = code;
  snprintf(result->message, sizeof(result->message), "%s", message);
}

static void set_state(bridge_dispatch_result_t *result, const char *state) {
  result->kind = BRIDGE_DISPATCH_STATE;
  snprintf(result->state, sizeof(result->state), "%s", state ? state : "");
}

static void set_text(bridge_dispatch_result_t *result, char *text) {
  result->kind = BRIDGE_DISPATCH_TEXT;
  result->text = text;
}

static void set_empty(bridge_dispatch_result_t *result) {
  result->kind = BRIDGE_DISPATCH_EMPTY;
}

static void dispatch_ime(const char *method, cJSON *params,
                         bridge_dispatch_result_t *result) {
#ifdef __APPLE__
  if (strcmp(method, "normal") == 0) {
    set_state(result, im_normal());
    return;
  }

  if (strcmp(method, "insert") == 0) {
    set_state(result, im_insert());
    return;
  }

  if (strcmp(method, "watch") == 0) {
    cJSON *enable = params ? cJSON_GetObjectItemCaseSensitive(params, "enable") : NULL;
    if (!cJSON_IsBool(enable)) {
      set_error(result, "INVALID_PARAMS", "missing params.enable");
      return;
    }
    im_watch(cJSON_IsTrue(enable));
    set_empty(result);
    return;
  }

  set_error(result, "INVALID_METHOD", "unsupported ime method");
#else
  if (strcmp(method, "normal") == 0) {
    char state[16] = {0};
    int status = bridge_ime_normal(state, sizeof(state));
    if (status == BRIDGE_STATUS_OK) {
      set_state(result, state);
      return;
    }
    set_error(result, "IME_FAILED", "ime operation failed");
    return;
  }

  if (strcmp(method, "insert") == 0) {
    char state[16] = {0};
    int status = bridge_ime_insert(state, sizeof(state));
    if (status == BRIDGE_STATUS_OK) {
      set_state(result, state);
      return;
    }
    set_error(result, "IME_FAILED", "ime operation failed");
    return;
  }

  if (strcmp(method, "watch") == 0) {
    cJSON *enable = params ? cJSON_GetObjectItemCaseSensitive(params, "enable") : NULL;
    if (!cJSON_IsBool(enable)) {
      set_error(result, "INVALID_PARAMS", "missing params.enable");
      return;
    }
    int watch_status = bridge_ime_watch(cJSON_IsTrue(enable));
    if (watch_status == BRIDGE_STATUS_OK) {
      set_empty(result);
      return;
    }
    snprintf(result->message, sizeof(result->message),
             "ime watch failed at %s (0x%08lx)", bridge_ime_watch_error_step(),
             bridge_ime_watch_error());
    result->kind = BRIDGE_DISPATCH_ERROR;
    result->error_code = "IME_FAILED";
    return;
  }

  set_error(result, "INVALID_METHOD", "unsupported ime method");
#endif
}

static void dispatch_clipboard(const char *method, cJSON *params,
                               bridge_dispatch_result_t *result) {
  if (strcmp(method, "output") == 0) {
    const char *eol_ptr = NULL;
    cJSON *eol = params ? cJSON_GetObjectItemCaseSensitive(params, "eol") : NULL;
    if (cJSON_IsString(eol) && eol->valuestring) {
      eol_ptr = eol->valuestring;
    }

    char *text = NULL;
    int status = bridge_clipboard_output(eol_ptr, &text);
    if (status == BRIDGE_STATUS_INVALID_PARAMS) {
      set_error(result, "INVALID_PARAMS",
                "clipboard.output only supports eol=lf");
      return;
    }
    if (status != BRIDGE_STATUS_OK || !text) {
      free(text);
      set_error(result, "CLIPBOARD_FAILED", "clipboard output failed");
      return;
    }

    set_text(result, text);
    return;
  }

  if (strcmp(method, "input") == 0) {
    cJSON *text = params ? cJSON_GetObjectItemCaseSensitive(params, "text") : NULL;
    if (!cJSON_IsString(text) || !text->valuestring) {
      set_error(result, "INVALID_PARAMS", "missing params.text");
      return;
    }

    if (strlen(text->valuestring) >= MAX_TEXT) {
      set_error(result, "INVALID_PARAMS", "params.text too long");
      return;
    }

    int status = bridge_clipboard_input(text->valuestring);
    if (status == BRIDGE_STATUS_INVALID_PARAMS) {
      set_error(result, "INVALID_PARAMS", "missing params.text");
      return;
    }
    if (status != BRIDGE_STATUS_OK) {
      set_error(result, "CLIPBOARD_FAILED", "clipboard input failed");
      return;
    }

    set_empty(result);
    return;
  }

  set_error(result, "INVALID_METHOD", "unsupported clipboard method");
}

void bridge_dispatch_result_init(bridge_dispatch_result_t *result) {
  memset(result, 0, sizeof(*result));
}

void bridge_dispatch_result_free(bridge_dispatch_result_t *result) {
  if (result->text) {
    free(result->text);
    result->text = NULL;
  }
}

void bridge_dispatch_request(const char *module, const char *method, cJSON *params,
                             bridge_dispatch_result_t *result) {
  bridge_dispatch_result_init(result);

  if (strcmp(module, "ime") == 0) {
    dispatch_ime(method, params, result);
    return;
  }

  if (strcmp(module, "clipboard") == 0) {
    dispatch_clipboard(method, params, result);
    return;
  }

  set_error(result, "INVALID_MODULE", "unsupported module");
}
