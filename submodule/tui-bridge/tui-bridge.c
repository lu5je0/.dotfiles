#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bridge-status.h"
#include "clipboard-bridge.h"
#include "im.h"
#include "platform.h"

#define MAX_LINE 32768
#define MAX_TEXT 32768

static const char *skip_ws(const char *p) {
  while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
    p++;
  }
  return p;
}

static int parse_json_string(const char **p, char *out, size_t out_sz) {
  const char *s = *p;
  size_t w = 0;

  if (*s != '"') {
    return -1;
  }
  s++;

  while (*s && *s != '"') {
    unsigned char ch = (unsigned char)*s;
    if (ch == '\\') {
      s++;
      if (*s == '\0') {
        return -1;
      }
      char esc = *s;
      if (esc == 'n') {
        ch = '\n';
      } else if (esc == 'r') {
        ch = '\r';
      } else if (esc == 't') {
        ch = '\t';
      } else if (esc == '"' || esc == '\\' || esc == '/') {
        ch = (unsigned char)esc;
      } else if (esc == 'b') {
        ch = '\b';
      } else if (esc == 'f') {
        ch = '\f';
      } else if (esc == 'u') {
        for (int i = 0; i < 4 && s[1] != '\0'; i++) {
          s++;
        }
        ch = '?';
      } else {
        ch = (unsigned char)esc;
      }
    }

    if (w + 1 < out_sz) {
      out[w++] = (char)ch;
    }
    s++;
  }

  if (*s != '"') {
    return -1;
  }

  if (out_sz > 0) {
    out[w] = '\0';
  }
  *p = s + 1;
  return 0;
}

static int skip_json_value(const char **p);

static int skip_json_compound(const char **p, char open, char close) {
  const char *s = *p;
  int depth = 0;

  while (*s) {
    if (*s == '"') {
      char tmp[2] = {0};
      if (parse_json_string(&s, tmp, sizeof(tmp)) != 0) {
        return -1;
      }
      continue;
    }
    if (*s == open) {
      depth++;
    } else if (*s == close) {
      depth--;
      if (depth == 0) {
        *p = s + 1;
        return 0;
      }
    }
    s++;
  }

  return -1;
}

static int skip_json_value(const char **p) {
  const char *s = skip_ws(*p);
  if (*s == '"') {
    char tmp[2] = {0};
    if (parse_json_string(&s, tmp, sizeof(tmp)) != 0) {
      return -1;
    }
    *p = s;
    return 0;
  }

  if (*s == '{') {
    if (skip_json_compound(&s, '{', '}') != 0) {
      return -1;
    }
    *p = s;
    return 0;
  }

  if (*s == '[') {
    if (skip_json_compound(&s, '[', ']') != 0) {
      return -1;
    }
    *p = s;
    return 0;
  }

  while (*s && *s != ',' && *s != '}' && *s != ']') {
    s++;
  }
  *p = s;
  return 0;
}

static int find_key_value(const char *json_obj, const char *target_key,
                          const char **value_start) {
  const char *p = skip_ws(json_obj);
  char key[128];

  if (*p != '{') {
    return -1;
  }
  p++;

  while (1) {
    p = skip_ws(p);
    if (*p == '}') {
      return -1;
    }

    if (parse_json_string(&p, key, sizeof(key)) != 0) {
      return -1;
    }

    p = skip_ws(p);
    if (*p != ':') {
      return -1;
    }
    p++;
    p = skip_ws(p);

    if (strcmp(key, target_key) == 0) {
      *value_start = p;
      return 0;
    }

    if (skip_json_value(&p) != 0) {
      return -1;
    }

    p = skip_ws(p);
    if (*p == ',') {
      p++;
      continue;
    }
    if (*p == '}') {
      return -1;
    }
    return -1;
  }
}

static int get_object_string_field(const char *obj, const char *key, char *out,
                                   size_t out_sz) {
  const char *value;
  if (find_key_value(obj, key, &value) != 0) {
    return -1;
  }
  value = skip_ws(value);
  return parse_json_string(&value, out, out_sz);
}

static int get_object_int_field(const char *obj, const char *key, int *out) {
  const char *value;
  if (find_key_value(obj, key, &value) != 0) {
    return -1;
  }
  value = skip_ws(value);
  char *end = NULL;
  long v = strtol(value, &end, 10);
  if (end == value) {
    return -1;
  }
  *out = (int)v;
  return 0;
}

static void print_json_string_escaped(const char *s) {
  putchar('"');
  while (*s) {
    unsigned char ch = (unsigned char)*s;
    if (ch == '"' || ch == '\\') {
      putchar('\\');
      putchar((char)ch);
    } else if (ch == '\n') {
      fputs("\\n", stdout);
    } else if (ch == '\r') {
      fputs("\\r", stdout);
    } else if (ch == '\t') {
      fputs("\\t", stdout);
    } else if (ch < 0x20) {
      fprintf(stdout, "\\u%04x", ch);
    } else {
      putchar((char)ch);
    }
    s++;
  }
  putchar('"');
}

static void respond_error(int id, const char *code, const char *message) {
  printf("{\"id\":%d,\"ok\":false,\"error\":{\"code\":", id);
  print_json_string_escaped(code);
  printf(",\"message\":");
  print_json_string_escaped(message);
  printf("}}\n");
  fflush(stdout);
}

static void respond_state(int id, const char *state) {
  printf("{\"id\":%d,\"ok\":true,\"result\":{\"state\":", id);
  print_json_string_escaped(state);
  printf("}}\n");
  fflush(stdout);
}

static void respond_text(int id, const char *text) {
  printf("{\"id\":%d,\"ok\":true,\"result\":{\"text\":", id);
  print_json_string_escaped(text);
  printf("}}\n");
  fflush(stdout);
}

static void respond_empty(int id) {
  printf("{\"id\":%d,\"ok\":true,\"result\":{}}\n", id);
  fflush(stdout);
}

static void handle_ime_method(int id, const char *method) {
  char state[16] = {0};
  int status = bridge_ime_call(method, state, sizeof(state));
  if (status == BRIDGE_STATUS_OK) {
    respond_state(id, state);
    return;
  }
  if (status == BRIDGE_STATUS_INVALID_METHOD) {
    respond_error(id, "INVALID_METHOD", "unsupported ime method");
    return;
  }
  respond_error(id, "IME_FAILED", "ime operation failed");
}

static void handle_clipboard_method(int id, const char *method,
                                    const char *params_obj) {
  if (strcmp(method, "output") == 0) {
    char eol[16] = {0};
    const char *eol_ptr = NULL;
    if (params_obj && get_object_string_field(params_obj, "eol", eol, sizeof(eol)) == 0) {
      eol_ptr = eol;
    }

    char *text = NULL;
    int status = bridge_clipboard_output(eol_ptr, &text);
    if (status == BRIDGE_STATUS_INVALID_PARAMS) {
      respond_error(id, "INVALID_PARAMS", "clipboard.output only supports eol=lf");
      return;
    }
    if (status != BRIDGE_STATUS_OK || !text) {
      respond_error(id, "CLIPBOARD_FAILED", "clipboard output failed");
      return;
    }

    respond_text(id, text);
    free(text);
    return;
  }

  if (strcmp(method, "input") == 0) {
    if (!params_obj) {
      respond_error(id, "INVALID_PARAMS", "missing params.text");
      return;
    }

    char text[MAX_TEXT];
    if (get_object_string_field(params_obj, "text", text, sizeof(text)) != 0) {
      respond_error(id, "INVALID_PARAMS", "missing params.text");
      return;
    }

    int status = bridge_clipboard_input(text);
    if (status != BRIDGE_STATUS_OK) {
      respond_error(id, "CLIPBOARD_FAILED", "clipboard input failed");
      return;
    }

    respond_empty(id);
    return;
  }

  respond_error(id, "INVALID_METHOD", "unsupported clipboard method");
}

typedef struct {
  int id;
  int has_id;
  char module[64];
  int has_module;
  char method[64];
  int has_method;
  const char *params_obj;
  int has_params;
  int params_is_object;
} request_fields_t;

static int parse_request_fields(const char *line, request_fields_t *req) {
  const char *p = skip_ws(line);
  char key[128];

  memset(req, 0, sizeof(*req));
  if (*p != '{') {
    return -1;
  }
  p++;

  while (1) {
    p = skip_ws(p);
    if (*p == '}') {
      return 0;
    }

    if (parse_json_string(&p, key, sizeof(key)) != 0) {
      return -1;
    }

    p = skip_ws(p);
    if (*p != ':') {
      return -1;
    }
    p++;

    const char *value = skip_ws(p);

    if (strcmp(key, "id") == 0) {
      char *end = NULL;
      long v = strtol(value, &end, 10);
      if (end == value) {
        return -1;
      }
      req->id = (int)v;
      req->has_id = 1;
    } else if (strcmp(key, "module") == 0) {
      const char *tmp = value;
      if (parse_json_string(&tmp, req->module, sizeof(req->module)) != 0) {
        return -1;
      }
      req->has_module = 1;
    } else if (strcmp(key, "method") == 0) {
      const char *tmp = value;
      if (parse_json_string(&tmp, req->method, sizeof(req->method)) != 0) {
        return -1;
      }
      req->has_method = 1;
    } else if (strcmp(key, "params") == 0) {
      req->params_obj = value;
      req->has_params = 1;
      req->params_is_object = (*value == '{');
    }

    if (skip_json_value(&p) != 0) {
      return -1;
    }

    p = skip_ws(p);
    if (*p == ',') {
      p++;
      continue;
    }
    if (*p == '}') {
      return 0;
    }
    return -1;
  }
}

static void process_json_line(const char *line) {
  request_fields_t req;

  if (parse_request_fields(line, &req) != 0 || !req.has_id) {
    respond_error(0, "INVALID_REQUEST", "missing id");
    return;
  }
  if (!req.has_module || !req.has_method) {
    respond_error(req.id, "INVALID_REQUEST", "missing module/method");
    return;
  }
  if (req.has_params && !req.params_is_object) {
    respond_error(req.id, "INVALID_REQUEST", "params must be an object");
    return;
  }

  if (strcmp(req.module, "ime") == 0) {
    handle_ime_method(req.id, req.method);
    return;
  }
  if (strcmp(req.module, "clipboard") == 0) {
    handle_clipboard_method(req.id, req.method,
                            req.has_params ? req.params_obj : NULL);
    return;
  }
  respond_error(req.id, "INVALID_MODULE", "unsupported module");
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
    return run_interactive_mode();
  }

  print_usage(argv[0]);
  return 1;
}
