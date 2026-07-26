// Linux clipboard backend: talks the Wayland data-control protocol through
// libwayland-client, supporting both ext_data_control_v1 (preferred, the
// standardized protocol; the only one KWin 6.4+ advertises) and
// zwlr_data_control_unstable_v1 (fallback for wlroots compositors). The two
// protocols are structurally identical, so shared handlers sit behind a tiny
// vtable. A dedicated thread owns the Wayland connection, keeps serving our
// selection (send events) while the process lives, and executes input/output
// commands posted from the protocol thread via a wakeup pipe.
//
// Limitation: a selection written with `-j` dies with the process; clipboard
// writes need the interactive (`-i`) long-lived process on Linux.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "ext-data-control-v1-client-protocol.h"
#include "wlr-data-control-unstable-v1-client-protocol.h"

#include "../bridge-status.h"
#include "../clipboard-bridge.h"

#define MAX_CLIP_TEXT (64 * 1024 * 1024)
#define IO_TIMEOUT_MS 3000

static const char *OFFER_MIMES[] = {
    "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT",
};
static const char *PREF_MIMES[] = {
    "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT",
};

typedef struct {
  char **items;
  size_t count;
  size_t cap;
} mime_list_t;

typedef struct {
  void *(*create_data_source)(void *manager);
  void *(*get_data_device)(void *manager, struct wl_seat *seat);
  void (*add_device_listener)(void *device);
  void (*add_source_listener)(void *source, char *text);
  void (*add_offer_listener)(void *offer, mime_list_t *list);
  void (*set_selection)(void *device, void *source);
  void (*source_offer)(void *source, const char *mime);
  void (*offer_receive)(void *offer, const char *mime, int fd);
  void (*offer_destroy)(void *offer);
  void (*source_destroy)(void *source);
  void (*device_destroy)(void *device);
  void (*manager_destroy)(void *manager);
} dc_backend_t;

static const dc_backend_t *dc = NULL;

static struct wl_display *display = NULL;
static struct wl_registry *registry = NULL;
static struct wl_seat *seat = NULL;
static void *manager = NULL;
static void *device = NULL;

static uint32_t ext_name = 0;
static bool ext_found = false;
static uint32_t zwlr_name = 0;
static uint32_t zwlr_version = 0;
static bool zwlr_found = false;

static void *current_offer = NULL;
static void *own_source = NULL;
static char *own_text = NULL;
static bool own_active = false;
static bool clip_fatal = false;

static bool clip_initialized = false;
static int wake_r = -1;
static int wake_w = -1;
static pthread_t clip_thread;

enum { CMD_NONE, CMD_INPUT, CMD_OUTPUT };
static struct {
  int type;
  const char *in_text;
  char *out_text;
  int status;
  bool done;
} cmd = {CMD_NONE, NULL, NULL, BRIDGE_STATUS_FAILED, false};
static pthread_mutex_t cmd_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cmd_cond = PTHREAD_COND_INITIALIZER;

// ── mime list helpers ─────────────────────────────────────────

static void mime_list_free(mime_list_t *list) {
  if (!list) {
    return;
  }
  for (size_t i = 0; i < list->count; i++) {
    free(list->items[i]);
  }
  free(list->items);
  free(list);
}

static void mime_list_add(mime_list_t *list, const char *mime) {
  if (list->count == list->cap) {
    size_t new_cap = list->cap ? list->cap * 2 : 8;
    char **grown = realloc(list->items, new_cap * sizeof(char *));
    if (!grown) {
      return;
    }
    list->items = grown;
    list->cap = new_cap;
  }
  char *copy = strdup(mime);
  if (copy) {
    list->items[list->count++] = copy;
  }
}

static bool mime_list_has(const mime_list_t *list, const char *mime) {
  for (size_t i = 0; i < list->count; i++) {
    if (strcmp(list->items[i], mime) == 0) {
      return true;
    }
  }
  return false;
}

static void destroy_offer(void *offer) {
  if (!offer) {
    return;
  }
  mime_list_free(wl_proxy_get_user_data((struct wl_proxy *)offer));
  dc->offer_destroy(offer);
}

// ── blocking pipe I/O with timeouts ───────────────────────────

static void write_all(int fd, const char *buf, size_t len) {
  size_t off = 0;
  while (off < len) {
    struct pollfd pfd = {fd, POLLOUT, 0};
    int n = poll(&pfd, 1, IO_TIMEOUT_MS);
    if (n <= 0) {
      break;
    }
    ssize_t w = write(fd, buf + off, len - off);
    if (w < 0) {
      if (errno == EINTR || errno == EAGAIN) {
        continue;
      }
      break;
    }
    off += (size_t)w;
  }
}

static char *read_all(int fd) {
  size_t cap = 64 * 1024;
  size_t len = 0;
  char *buf = malloc(cap);
  if (!buf) {
    return NULL;
  }

  for (;;) {
    struct pollfd pfd = {fd, POLLIN, 0};
    int n = poll(&pfd, 1, IO_TIMEOUT_MS);
    if (n <= 0) {
      free(buf);
      return NULL;
    }
    if (len + 1 >= cap) {
      if (cap >= MAX_CLIP_TEXT) {
        free(buf);
        return NULL;
      }
      size_t new_cap = cap * 2;
      char *grown = realloc(buf, new_cap);
      if (!grown) {
        free(buf);
        return NULL;
      }
      buf = grown;
      cap = new_cap;
    }
    ssize_t r = read(fd, buf + len, cap - len - 1);
    if (r < 0) {
      if (errno == EINTR) {
        continue;
      }
      free(buf);
      return NULL;
    }
    if (r == 0) {
      break;
    }
    len += (size_t)r;
  }

  buf[len] = '\0';
  return buf;
}

// ── shared protocol handlers (wayland thread) ─────────────────

static void handle_offer_mime(void *data, const char *mime) {
  mime_list_add(data, mime);
}

static void handle_data_offer(void *offer) {
  mime_list_t *list = calloc(1, sizeof(mime_list_t));
  if (!list) {
    dc->offer_destroy(offer);
    return;
  }
  dc->add_offer_listener(offer, list);
}

static void handle_selection(void *offer) {
  if (current_offer && current_offer != offer) {
    destroy_offer(current_offer);
  }
  current_offer = offer;
}

static void handle_finished(void) {
  clip_fatal = true;
}

static void handle_primary_selection(void *offer) {
  if (offer && offer != current_offer) {
    destroy_offer(offer);
  }
}

static void handle_send(void *data, int fd) {
  const char *text = data;
  write_all(fd, text, strlen(text));
  close(fd);
}

static void handle_cancelled(void *data, void *source) {
  if (source == own_source) {
    own_source = NULL;
    own_text = NULL;
    own_active = false;
  }
  dc->source_destroy(source);
  free(data);
}

// ── zwlr backend ──────────────────────────────────────────────

static void zwlr_offer_mime_cb(void *data,
                               struct zwlr_data_control_offer_v1 *offer,
                               const char *mime) {
  (void)offer;
  handle_offer_mime(data, mime);
}

static const struct zwlr_data_control_offer_v1_listener zwlr_offer_listener = {
    .offer = zwlr_offer_mime_cb,
};

static void zwlr_send_cb(void *data, struct zwlr_data_control_source_v1 *src,
                         const char *mime, int32_t fd) {
  (void)src;
  (void)mime;
  handle_send(data, fd);
}

static void zwlr_cancelled_cb(void *data,
                              struct zwlr_data_control_source_v1 *src) {
  handle_cancelled(data, src);
}

static const struct zwlr_data_control_source_v1_listener zwlr_source_listener = {
    .send = zwlr_send_cb,
    .cancelled = zwlr_cancelled_cb,
};

static void zwlr_data_offer_cb(void *data,
                               struct zwlr_data_control_device_v1 *dev,
                               struct zwlr_data_control_offer_v1 *offer) {
  (void)data;
  (void)dev;
  handle_data_offer(offer);
}

static void zwlr_selection_cb(void *data,
                              struct zwlr_data_control_device_v1 *dev,
                              struct zwlr_data_control_offer_v1 *offer) {
  (void)data;
  (void)dev;
  handle_selection(offer);
}

static void zwlr_finished_cb(void *data,
                             struct zwlr_data_control_device_v1 *dev) {
  (void)data;
  (void)dev;
  handle_finished();
}

static void zwlr_primary_cb(void *data,
                            struct zwlr_data_control_device_v1 *dev,
                            struct zwlr_data_control_offer_v1 *offer) {
  (void)data;
  (void)dev;
  handle_primary_selection(offer);
}

static const struct zwlr_data_control_device_v1_listener zwlr_device_listener = {
    .data_offer = zwlr_data_offer_cb,
    .selection = zwlr_selection_cb,
    .finished = zwlr_finished_cb,
    .primary_selection = zwlr_primary_cb,
};

static void *zwlr_create_data_source(void *m) {
  return zwlr_data_control_manager_v1_create_data_source(m);
}
static void *zwlr_get_data_device(void *m, struct wl_seat *s) {
  return zwlr_data_control_manager_v1_get_data_device(m, s);
}
static void zwlr_add_device_listener(void *dev) {
  zwlr_data_control_device_v1_add_listener(dev, &zwlr_device_listener, NULL);
}
static void zwlr_add_source_listener(void *src, char *text) {
  zwlr_data_control_source_v1_add_listener(src, &zwlr_source_listener, text);
}
static void zwlr_add_offer_listener(void *offer, mime_list_t *list) {
  zwlr_data_control_offer_v1_add_listener(offer, &zwlr_offer_listener, list);
}
static void zwlr_set_selection(void *dev, void *src) {
  zwlr_data_control_device_v1_set_selection(dev, src);
}
static void zwlr_source_offer(void *src, const char *mime) {
  zwlr_data_control_source_v1_offer(src, mime);
}
static void zwlr_offer_receive(void *offer, const char *mime, int fd) {
  zwlr_data_control_offer_v1_receive(offer, mime, fd);
}
static void zwlr_offer_destroy(void *offer) {
  zwlr_data_control_offer_v1_destroy(offer);
}
static void zwlr_source_destroy(void *src) {
  zwlr_data_control_source_v1_destroy(src);
}
static void zwlr_device_destroy(void *dev) {
  zwlr_data_control_device_v1_destroy(dev);
}
static void zwlr_manager_destroy(void *m) {
  zwlr_data_control_manager_v1_destroy(m);
}

static const dc_backend_t zwlr_backend = {
    .create_data_source = zwlr_create_data_source,
    .get_data_device = zwlr_get_data_device,
    .add_device_listener = zwlr_add_device_listener,
    .add_source_listener = zwlr_add_source_listener,
    .add_offer_listener = zwlr_add_offer_listener,
    .set_selection = zwlr_set_selection,
    .source_offer = zwlr_source_offer,
    .offer_receive = zwlr_offer_receive,
    .offer_destroy = zwlr_offer_destroy,
    .source_destroy = zwlr_source_destroy,
    .device_destroy = zwlr_device_destroy,
    .manager_destroy = zwlr_manager_destroy,
};

// ── ext backend ───────────────────────────────────────────────

static void ext_offer_mime_cb(void *data, struct ext_data_control_offer_v1 *offer,
                              const char *mime) {
  (void)offer;
  handle_offer_mime(data, mime);
}

static const struct ext_data_control_offer_v1_listener ext_offer_listener = {
    .offer = ext_offer_mime_cb,
};

static void ext_send_cb(void *data, struct ext_data_control_source_v1 *src,
                        const char *mime, int32_t fd) {
  (void)src;
  (void)mime;
  handle_send(data, fd);
}

static void ext_cancelled_cb(void *data,
                             struct ext_data_control_source_v1 *src) {
  handle_cancelled(data, src);
}

static const struct ext_data_control_source_v1_listener ext_source_listener = {
    .send = ext_send_cb,
    .cancelled = ext_cancelled_cb,
};

static void ext_data_offer_cb(void *data,
                              struct ext_data_control_device_v1 *dev,
                              struct ext_data_control_offer_v1 *offer) {
  (void)data;
  (void)dev;
  handle_data_offer(offer);
}

static void ext_selection_cb(void *data,
                             struct ext_data_control_device_v1 *dev,
                             struct ext_data_control_offer_v1 *offer) {
  (void)data;
  (void)dev;
  handle_selection(offer);
}

static void ext_finished_cb(void *data,
                            struct ext_data_control_device_v1 *dev) {
  (void)data;
  (void)dev;
  handle_finished();
}

static void ext_primary_cb(void *data,
                           struct ext_data_control_device_v1 *dev,
                           struct ext_data_control_offer_v1 *offer) {
  (void)data;
  (void)dev;
  handle_primary_selection(offer);
}

static const struct ext_data_control_device_v1_listener ext_device_listener = {
    .data_offer = ext_data_offer_cb,
    .selection = ext_selection_cb,
    .finished = ext_finished_cb,
    .primary_selection = ext_primary_cb,
};

static void *ext_create_data_source(void *m) {
  return ext_data_control_manager_v1_create_data_source(m);
}
static void *ext_get_data_device(void *m, struct wl_seat *s) {
  return ext_data_control_manager_v1_get_data_device(m, s);
}
static void ext_add_device_listener(void *dev) {
  ext_data_control_device_v1_add_listener(dev, &ext_device_listener, NULL);
}
static void ext_add_source_listener(void *src, char *text) {
  ext_data_control_source_v1_add_listener(src, &ext_source_listener, text);
}
static void ext_add_offer_listener(void *offer, mime_list_t *list) {
  ext_data_control_offer_v1_add_listener(offer, &ext_offer_listener, list);
}
static void ext_set_selection(void *dev, void *src) {
  ext_data_control_device_v1_set_selection(dev, src);
}
static void ext_source_offer(void *src, const char *mime) {
  ext_data_control_source_v1_offer(src, mime);
}
static void ext_offer_receive(void *offer, const char *mime, int fd) {
  ext_data_control_offer_v1_receive(offer, mime, fd);
}
static void ext_offer_destroy(void *offer) {
  ext_data_control_offer_v1_destroy(offer);
}
static void ext_source_destroy(void *src) {
  ext_data_control_source_v1_destroy(src);
}
static void ext_device_destroy(void *dev) {
  ext_data_control_device_v1_destroy(dev);
}
static void ext_manager_destroy(void *m) {
  ext_data_control_manager_v1_destroy(m);
}

static const dc_backend_t ext_backend = {
    .create_data_source = ext_create_data_source,
    .get_data_device = ext_get_data_device,
    .add_device_listener = ext_add_device_listener,
    .add_source_listener = ext_add_source_listener,
    .add_offer_listener = ext_add_offer_listener,
    .set_selection = ext_set_selection,
    .source_offer = ext_source_offer,
    .offer_receive = ext_offer_receive,
    .offer_destroy = ext_offer_destroy,
    .source_destroy = ext_source_destroy,
    .device_destroy = ext_device_destroy,
    .manager_destroy = ext_manager_destroy,
};

// ── registry ──────────────────────────────────────────────────

static void registry_global(void *data, struct wl_registry *reg, uint32_t name,
                            const char *interface, uint32_t version) {
  (void)data;
  (void)reg;
  if (strcmp(interface, ext_data_control_manager_v1_interface.name) == 0) {
    ext_name = name;
    ext_found = true;
  } else if (strcmp(interface,
                    zwlr_data_control_manager_v1_interface.name) == 0) {
    zwlr_name = name;
    zwlr_version = version;
    zwlr_found = true;
  } else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
    seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
  }
}

static void registry_global_remove(void *data, struct wl_registry *reg,
                                   uint32_t name) {
  (void)data;
  (void)reg;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// ── command execution (wayland thread) ────────────────────────

static const char *pick_mime(const mime_list_t *list) {
  if (!list || list->count == 0) {
    return NULL;
  }
  for (size_t i = 0; i < sizeof(PREF_MIMES) / sizeof(PREF_MIMES[0]); i++) {
    if (mime_list_has(list, PREF_MIMES[i])) {
      return PREF_MIMES[i];
    }
  }
  return list->items[0];
}

static int do_input(const char *text) {
  if (clip_fatal) {
    return BRIDGE_STATUS_FAILED;
  }

  char *copy = strdup(text);
  if (!copy) {
    return BRIDGE_STATUS_FAILED;
  }

  void *source = dc->create_data_source(manager);
  if (!source) {
    free(copy);
    return BRIDGE_STATUS_FAILED;
  }

  dc->add_source_listener(source, copy);
  for (size_t i = 0; i < sizeof(OFFER_MIMES) / sizeof(OFFER_MIMES[0]); i++) {
    dc->source_offer(source, OFFER_MIMES[i]);
  }
  dc->set_selection(device, source);

  // The previous own_source (if any) gets a cancelled event which frees it.
  own_source = source;
  own_text = copy;
  own_active = true;

  wl_display_flush(display);
  return BRIDGE_STATUS_OK;
}

static int do_output(char **out_text) {
  if (clip_fatal) {
    return BRIDGE_STATUS_FAILED;
  }

  if (own_active && own_text) {
    // Receiving our own offer would deadlock (this thread is also the
    // sender), so answer from the local copy.
    *out_text = strdup(own_text);
    return *out_text ? BRIDGE_STATUS_OK : BRIDGE_STATUS_FAILED;
  }

  if (!current_offer) {
    *out_text = strdup("");
    return *out_text ? BRIDGE_STATUS_OK : BRIDGE_STATUS_FAILED;
  }

  const char *mime =
      pick_mime(wl_proxy_get_user_data((struct wl_proxy *)current_offer));
  if (!mime) {
    *out_text = strdup("");
    return *out_text ? BRIDGE_STATUS_OK : BRIDGE_STATUS_FAILED;
  }

  int fds[2];
  if (pipe2(fds, O_CLOEXEC) != 0) {
    return BRIDGE_STATUS_FAILED;
  }
  dc->offer_receive(current_offer, mime, fds[1]);
  wl_display_flush(display);
  close(fds[1]);

  char *text = read_all(fds[0]);
  close(fds[0]);
  if (!text) {
    return BRIDGE_STATUS_FAILED;
  }
  *out_text = text;
  return BRIDGE_STATUS_OK;
}

static void handle_pending_command(void) {
  pthread_mutex_lock(&cmd_lock);
  int type = cmd.type;
  const char *in_text = cmd.in_text;
  bool done = cmd.done;
  pthread_mutex_unlock(&cmd_lock);

  if (done || type == CMD_NONE) {
    return;
  }

  char *out_text = NULL;
  int status = BRIDGE_STATUS_FAILED;
  if (type == CMD_INPUT) {
    status = do_input(in_text);
  } else if (type == CMD_OUTPUT) {
    status = do_output(&out_text);
  }

  pthread_mutex_lock(&cmd_lock);
  cmd.status = status;
  cmd.out_text = out_text;
  cmd.done = true;
  pthread_cond_signal(&cmd_cond);
  pthread_mutex_unlock(&cmd_lock);
}

// ── wayland event thread ──────────────────────────────────────

static void *clip_thread_main(void *unused) {
  (void)unused;

  for (;;) {
    bool can_read = false;
    if (!clip_fatal) {
      while (wl_display_prepare_read(display) != 0) {
        wl_display_dispatch_pending(display);
      }
      wl_display_flush(display);
      can_read = true;
    }

    struct pollfd fds[2] = {
        {wake_r, POLLIN, 0},
        {can_read ? wl_display_get_fd(display) : -1, POLLIN, 0},
    };
    int n = poll(fds, 2, -1);
    if (n < 0) {
      if (can_read) {
        wl_display_cancel_read(display);
      }
      if (errno == EINTR) {
        continue;
      }
      clip_fatal = true;
      continue;
    }

    if (can_read) {
      if (fds[1].revents & POLLIN) {
        if (wl_display_read_events(display) < 0) {
          clip_fatal = true;
        }
      } else {
        wl_display_cancel_read(display);
        if (fds[1].revents & (POLLERR | POLLHUP)) {
          clip_fatal = true;
        }
      }
      if (!clip_fatal && wl_display_dispatch_pending(display) < 0) {
        clip_fatal = true;
      }
    }

    if (fds[0].revents & POLLIN) {
      char drain[16];
      ssize_t r = read(wake_r, drain, sizeof(drain));
      (void)r;
      handle_pending_command();
    }
  }
  return NULL;
}

// ── init + public entry points (protocol thread) ──────────────

static void clip_init_cleanup(void) {
  if (device) {
    dc->device_destroy(device);
    device = NULL;
  }
  if (manager) {
    dc->manager_destroy(manager);
    manager = NULL;
  }
  dc = NULL;
  if (seat) {
    wl_seat_destroy(seat);
    seat = NULL;
  }
  if (registry) {
    wl_registry_destroy(registry);
    registry = NULL;
  }
  if (display) {
    wl_display_disconnect(display);
    display = NULL;
  }
  ext_found = false;
  zwlr_found = false;
}

static bool ensure_clip_init(void) {
  if (clip_initialized) {
    return !clip_fatal;
  }

  signal(SIGPIPE, SIG_IGN);

  display = wl_display_connect(NULL);
  if (!display) {
    return false;
  }

  registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  if (wl_display_roundtrip(display) < 0 || !seat ||
      (!ext_found && !zwlr_found)) {
    clip_init_cleanup();
    return false;
  }

  if (ext_found) {
    dc = &ext_backend;
    manager = wl_registry_bind(registry, ext_name,
                               &ext_data_control_manager_v1_interface, 1);
  } else {
    dc = &zwlr_backend;
    manager = wl_registry_bind(registry, zwlr_name,
                               &zwlr_data_control_manager_v1_interface,
                               zwlr_version < 2 ? zwlr_version : 2);
  }

  device = dc->get_data_device(manager, seat);
  dc->add_device_listener(device);
  if (wl_display_roundtrip(display) < 0) {
    clip_init_cleanup();
    return false;
  }

  int pipe_fds[2];
  if (pipe2(pipe_fds, O_CLOEXEC) != 0) {
    clip_init_cleanup();
    return false;
  }
  wake_r = pipe_fds[0];
  wake_w = pipe_fds[1];

  if (pthread_create(&clip_thread, NULL, clip_thread_main, NULL) != 0) {
    close(wake_r);
    close(wake_w);
    wake_r = wake_w = -1;
    clip_init_cleanup();
    return false;
  }

  clip_initialized = true;
  return true;
}

static int submit_cmd(int type, const char *in_text, char **out_text) {
  pthread_mutex_lock(&cmd_lock);
  cmd.type = type;
  cmd.in_text = in_text;
  cmd.out_text = NULL;
  cmd.status = BRIDGE_STATUS_FAILED;
  cmd.done = false;
  ssize_t w = write(wake_w, "x", 1);
  (void)w;
  while (!cmd.done) {
    pthread_cond_wait(&cmd_cond, &cmd_lock);
  }
  int status = cmd.status;
  if (out_text) {
    *out_text = cmd.out_text;
  } else {
    free(cmd.out_text);
  }
  cmd.type = CMD_NONE;
  cmd.out_text = NULL;
  pthread_mutex_unlock(&cmd_lock);
  return status;
}

static void normalize_lf_inplace(char *text) {
  if (!text) {
    return;
  }
  char *src = text;
  char *dst = text;
  while (*src) {
    if (src[0] == '\r' && src[1] == '\n') {
      *dst++ = '\n';
      src += 2;
      continue;
    }
    *dst++ = *src++;
  }
  *dst = '\0';
}

int bridge_clipboard_output(const char *eol, char **text_out) {
  if (!text_out) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }
  *text_out = NULL;

  if (eol && strcmp(eol, "lf") != 0) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  if (!ensure_clip_init()) {
    return BRIDGE_STATUS_FAILED;
  }

  char *text = NULL;
  int status = submit_cmd(CMD_OUTPUT, NULL, &text);
  if (status != BRIDGE_STATUS_OK || !text) {
    free(text);
    return BRIDGE_STATUS_FAILED;
  }

  normalize_lf_inplace(text);
  *text_out = text;
  return BRIDGE_STATUS_OK;
}

int bridge_clipboard_input(const char *text) {
  if (!text) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  if (!ensure_clip_init()) {
    return BRIDGE_STATUS_FAILED;
  }

  return submit_cmd(CMD_INPUT, text, NULL);
}
