#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/time.h>
#endif

#include "bridge-status.h"
#include "im.h"
#include "platform.h"
#include "request-dispatch.h"
#include "third_party/cjson/cJSON.h"

#define MAX_LINE 32768
#ifdef _WIN32
static double get_time_ms(void) {
  static LARGE_INTEGER freq = {0};
  if (freq.QuadPart == 0) {
    QueryPerformanceFrequency(&freq);
  }
  LARGE_INTEGER counter;
  QueryPerformanceCounter(&counter);
  return (double)counter.QuadPart * 1000.0 / (double)freq.QuadPart;
}
#else
static double get_time_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (double)tv.tv_sec * 1000.0 + (double)tv.tv_usec / 1000.0;
}
#endif

static void output_begin(void) {
#ifdef _WIN32
  _lock_file(stdout);
#endif
}

static void output_end(void) {
  fflush(stdout);
#ifdef _WIN32
  _unlock_file(stdout);
#endif
}

static void print_json_message(cJSON *json) {
  char *out = cJSON_PrintUnformatted(json);
  if (!out) {
    return;
  }
  output_begin();
  fputs(out, stdout);
  fputc('\n', stdout);
  output_end();
  cJSON_free(out);
}

static void add_rt_field(cJSON *json, double rt_ms) {
  char rt_text[32];
  snprintf(rt_text, sizeof(rt_text), "%.3f", rt_ms);
  cJSON_AddStringToObject(json, "rt", rt_text);
}

void bridge_emit_ime_changed(const char *source_id) {
  cJSON *json = cJSON_CreateObject();
  if (!json) {
    return;
  }
  cJSON_AddStringToObject(json, "event", "ime_changed");
  cJSON_AddStringToObject(json, "source_id", source_id ? source_id : "");
  print_json_message(json);
  cJSON_Delete(json);
}

void bridge_emit_ime_changed_state(const char *state) {
  cJSON *json = cJSON_CreateObject();
  if (!json) {
    return;
  }
  cJSON_AddStringToObject(json, "event", "ime_changed");
  cJSON_AddStringToObject(json, "source_id", state ? state : "");
  cJSON_AddStringToObject(json, "state", state ? state : "");
  print_json_message(json);
  cJSON_Delete(json);
}

static void respond_error(int id, const char *code, const char *message) {
  cJSON *json = cJSON_CreateObject();
  cJSON *error = cJSON_CreateObject();
  if (!json || !error) {
    cJSON_Delete(json);
    cJSON_Delete(error);
    return;
  }
  cJSON_AddNumberToObject(json, "id", id);
  cJSON_AddBoolToObject(json, "ok", 0);
  cJSON_AddStringToObject(error, "code", code);
  cJSON_AddStringToObject(error, "message", message);
  cJSON_AddItemToObject(json, "error", error);
  print_json_message(json);
  cJSON_Delete(json);
}

static void respond_state(int id, const char *state, double rt_ms) {
  cJSON *json = cJSON_CreateObject();
  cJSON *result = cJSON_CreateObject();
  if (!json || !result) {
    cJSON_Delete(json);
    cJSON_Delete(result);
    return;
  }
  cJSON_AddNumberToObject(json, "id", id);
  cJSON_AddBoolToObject(json, "ok", 1);
  cJSON_AddStringToObject(result, "state", state ? state : "");
  cJSON_AddItemToObject(json, "result", result);
  add_rt_field(json, rt_ms);
  print_json_message(json);
  cJSON_Delete(json);
}

static void respond_text(int id, const char *text, double rt_ms) {
  cJSON *json = cJSON_CreateObject();
  cJSON *result = cJSON_CreateObject();
  if (!json || !result) {
    cJSON_Delete(json);
    cJSON_Delete(result);
    return;
  }
  cJSON_AddNumberToObject(json, "id", id);
  cJSON_AddBoolToObject(json, "ok", 1);
  cJSON_AddStringToObject(result, "text", text ? text : "");
  cJSON_AddItemToObject(json, "result", result);
  add_rt_field(json, rt_ms);
  print_json_message(json);
  cJSON_Delete(json);
}

static void respond_empty(int id, double rt_ms) {
  cJSON *json = cJSON_CreateObject();
  cJSON *result = cJSON_CreateObject();
  if (!json || !result) {
    cJSON_Delete(json);
    cJSON_Delete(result);
    return;
  }
  cJSON_AddNumberToObject(json, "id", id);
  cJSON_AddBoolToObject(json, "ok", 1);
  cJSON_AddItemToObject(json, "result", result);
  add_rt_field(json, rt_ms);
  print_json_message(json);
  cJSON_Delete(json);
}

typedef struct {
  int id;
  int has_id;
  const char *module;
  const char *method;
  cJSON *root;
  cJSON *params;
  int has_params;
} request_fields_t;

static int parse_request_fields(const char *line, request_fields_t *req) {
  memset(req, 0, sizeof(*req));
  req->root = cJSON_ParseWithOpts(line, NULL, 1);
  if (!req->root || !cJSON_IsObject(req->root)) {
    cJSON_Delete(req->root);
    req->root = NULL;
    return -1;
  }

  cJSON *id = cJSON_GetObjectItemCaseSensitive(req->root, "id");
  if (cJSON_IsNumber(id)) {
    double value = id->valuedouble;
    int int_value = id->valueint;
    if ((double)int_value == value) {
      req->id = int_value;
      req->has_id = 1;
    }
  }

  cJSON *module = cJSON_GetObjectItemCaseSensitive(req->root, "module");
  if (cJSON_IsString(module) && module->valuestring) {
    req->module = module->valuestring;
  }

  cJSON *method = cJSON_GetObjectItemCaseSensitive(req->root, "method");
  if (cJSON_IsString(method) && method->valuestring) {
    req->method = method->valuestring;
  }

  req->params = cJSON_GetObjectItemCaseSensitive(req->root, "params");
  if (req->params) {
    req->has_params = 1;
  }

  return 0;
}

static void free_request_fields(request_fields_t *req) {
  if (req->root) {
    cJSON_Delete(req->root);
    req->root = NULL;
  }
}

static void process_json_line(const char *line) {
  request_fields_t req;

  if (parse_request_fields(line, &req) != 0 || !req.has_id) {
    respond_error(0, "INVALID_REQUEST", "missing id");
    free_request_fields(&req);
    return;
  }
  if (!req.module || !req.method) {
    respond_error(req.id, "INVALID_REQUEST", "missing module/method");
    free_request_fields(&req);
    return;
  }
  if (req.has_params && !cJSON_IsObject(req.params)) {
    respond_error(req.id, "INVALID_REQUEST", "params must be an object");
    free_request_fields(&req);
    return;
  }

  double start_time = get_time_ms();
  bridge_dispatch_result_t result;

  bridge_dispatch_request(req.module, req.method,
                          req.has_params ? req.params : NULL, &result);

  if (result.kind == BRIDGE_DISPATCH_STATE) {
    respond_state(req.id, result.state, get_time_ms() - start_time);
  } else if (result.kind == BRIDGE_DISPATCH_TEXT) {
    respond_text(req.id, result.text, get_time_ms() - start_time);
  } else if (result.kind == BRIDGE_DISPATCH_EMPTY) {
    respond_empty(req.id, get_time_ms() - start_time);
  } else {
    respond_error(req.id, result.error_code, result.message);
  }

  bridge_dispatch_result_free(&result);
  free_request_fields(&req);
}

static void print_usage(const char *prog_name) {
  fprintf(stderr,
          "Usage: %s [-i|--interactive] [-j|--json <request>] [-h|--help]\n",
          prog_name);
}

static int run_interactive_mode(void) {
  char line[MAX_LINE];
  while (fgets(line, sizeof(line), stdin)) {
    size_t len = strlen(line);
    if (len > 0 && line[len - 1] == '\n') {
      line[len - 1] = '\0';
      len--;
    }
    if (len == 0) {
      continue;
    }
    if (strcmp(line, "exit") == 0) {
      break;
    }
    process_json_line(line);
  }
  return 0;
}

int main(int argc, char *argv[]) {
  bridge_platform_init();
#ifndef __APPLE__
  atexit(bridge_ime_shutdown);
#endif

  bool interactive_mode = false;
  bool show_help = false;
  const char *json_request = NULL;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
      show_help = true;
      break;
    }
    if (strcmp(argv[i], "-i") == 0 || strcmp(argv[i], "--interactive") == 0) {
      interactive_mode = true;
      continue;
    }
    if ((strcmp(argv[i], "-j") == 0 || strcmp(argv[i], "--json") == 0) &&
        i + 1 < argc) {
      json_request = argv[i + 1];
      i++;
      continue;
    }
  }

  if (show_help) {
    print_usage(argv[0]);
    return 0;
  }

  if (json_request) {
    process_json_line(json_request);
    return 0;
  }

  if (interactive_mode) {
#ifdef __APPLE__
    im_run_interactive(process_json_line);
    return 0;
#else
    return run_interactive_mode();
#endif
  }

  print_usage(argv[0]);
  return 1;
}
