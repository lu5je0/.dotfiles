// Linux IME backend: toggles fcitx5/rime ascii_mode over the session bus,
// mirroring the semantics of the Windows backend (normal returns the
// pre-switch state; watch is a polling thread emitting normalized events).
#include <dbus/dbus.h>
#include <pthread.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#include "../bridge-status.h"
#include "../im.h"

#define FCITX_DEST "org.fcitx.Fcitx5"
#define RIME_PATH "/rime"
#define RIME_IFACE "org.fcitx.Fcitx.Rime1"
#define CALL_TIMEOUT_MS 500
#define WATCH_INTERVAL_US (200 * 1000)

static int saved_ime_status = -1; // 1 = ime (chinese), 0 = ascii

static pthread_mutex_t watch_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t watch_thread;
static bool watcher_started = false;
static bool watch_enabled = false;
static bool baseline_pending = false;
static bool watch_stop = false;
static int last_watch_status = -1;
static unsigned long watch_error = 0;
static const char *watch_error_step = "not_started";

static DBusConnection *main_conn = NULL;

static pthread_once_t dbus_threads_once = PTHREAD_ONCE_INIT;

static void init_dbus_threads(void) {
  dbus_threads_init_default();
}

static DBusConnection *open_conn(void) {
  pthread_once(&dbus_threads_once, init_dbus_threads);

  DBusError err;
  dbus_error_init(&err);
  DBusConnection *conn = dbus_bus_get_private(DBUS_BUS_SESSION, &err);
  if (dbus_error_is_set(&err)) {
    dbus_error_free(&err);
    return NULL;
  }
  if (conn) {
    dbus_connection_set_exit_on_disconnect(conn, FALSE);
  }
  return conn;
}

static void close_conn(DBusConnection **conn) {
  if (*conn) {
    dbus_connection_close(*conn);
    dbus_connection_unref(*conn);
    *conn = NULL;
  }
}

// Returns 1 if rime is in ascii mode, 0 if in ime mode, -1 on failure.
static int rime_is_ascii(DBusConnection *conn) {
  DBusMessage *msg = dbus_message_new_method_call(FCITX_DEST, RIME_PATH,
                                                  RIME_IFACE, "IsAsciiMode");
  if (!msg) {
    return -1;
  }

  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply =
      dbus_connection_send_with_reply_and_block(conn, msg, CALL_TIMEOUT_MS, &err);
  dbus_message_unref(msg);
  if (!reply) {
    dbus_error_free(&err);
    return -1;
  }

  dbus_bool_t value = FALSE;
  dbus_bool_t ok = dbus_message_get_args(reply, &err, DBUS_TYPE_BOOLEAN, &value,
                                         DBUS_TYPE_INVALID);
  dbus_message_unref(reply);
  if (!ok) {
    dbus_error_free(&err);
    return -1;
  }
  return value ? 1 : 0;
}

static int rime_set_ascii(DBusConnection *conn, bool ascii) {
  DBusMessage *msg = dbus_message_new_method_call(FCITX_DEST, RIME_PATH,
                                                  RIME_IFACE, "SetAsciiMode");
  if (!msg) {
    return -1;
  }

  dbus_bool_t value = ascii ? TRUE : FALSE;
  if (!dbus_message_append_args(msg, DBUS_TYPE_BOOLEAN, &value,
                                DBUS_TYPE_INVALID)) {
    dbus_message_unref(msg);
    return -1;
  }

  DBusError err;
  dbus_error_init(&err);
  DBusMessage *reply =
      dbus_connection_send_with_reply_and_block(conn, msg, CALL_TIMEOUT_MS, &err);
  dbus_message_unref(msg);
  if (!reply) {
    dbus_error_free(&err);
    return -1;
  }
  dbus_message_unref(reply);
  return 0;
}

// Main-thread helpers with one reconnect retry so a restarted session bus or
// fcitx5 doesn't permanently break the bridge.
static int main_conn_is_ascii(void) {
  for (int attempt = 0; attempt < 2; attempt++) {
    if (!main_conn) {
      main_conn = open_conn();
    }
    if (!main_conn) {
      return -1;
    }
    int result = rime_is_ascii(main_conn);
    if (result >= 0) {
      return result;
    }
    close_conn(&main_conn);
  }
  return -1;
}

static int main_conn_set_ascii(bool ascii) {
  for (int attempt = 0; attempt < 2; attempt++) {
    if (!main_conn) {
      main_conn = open_conn();
    }
    if (!main_conn) {
      return -1;
    }
    if (rime_set_ascii(main_conn, ascii) == 0) {
      return 0;
    }
    close_conn(&main_conn);
  }
  return -1;
}

static const char *status_to_state(int status) {
  return status == 1 ? "ime" : "ascii";
}

static void *watch_thread_main(void *unused) {
  (void)unused;
  DBusConnection *conn = NULL;

  for (;;) {
    usleep(WATCH_INTERVAL_US);

    pthread_mutex_lock(&watch_lock);
    bool stop = watch_stop;
    bool enabled = watch_enabled;
    bool baseline = baseline_pending;
    pthread_mutex_unlock(&watch_lock);

    if (stop) {
      break;
    }
    if (!enabled) {
      continue;
    }

    if (!conn) {
      conn = open_conn();
      if (!conn) {
        continue;
      }
    }

    int ascii = rime_is_ascii(conn);
    if (ascii < 0) {
      close_conn(&conn);
      continue;
    }
    int current_status = ascii ? 0 : 1;

    pthread_mutex_lock(&watch_lock);
    if (baseline) {
      last_watch_status = current_status;
      baseline_pending = false;
      pthread_mutex_unlock(&watch_lock);
      continue;
    }
    if (current_status != last_watch_status) {
      last_watch_status = current_status;
      pthread_mutex_unlock(&watch_lock);
      bridge_emit_ime_changed_state(status_to_state(current_status));
      continue;
    }
    pthread_mutex_unlock(&watch_lock);
  }

  close_conn(&conn);
  return NULL;
}

static int ensure_watcher_started(void) {
  pthread_mutex_lock(&watch_lock);
  if (watcher_started) {
    pthread_mutex_unlock(&watch_lock);
    return BRIDGE_STATUS_OK;
  }

  watch_stop = false;
  watch_error = 0;
  watch_error_step = "create_thread";
  int rc = pthread_create(&watch_thread, NULL, watch_thread_main, NULL);
  if (rc != 0) {
    watch_error = (unsigned long)rc;
    pthread_mutex_unlock(&watch_lock);
    return BRIDGE_STATUS_FAILED;
  }

  watcher_started = true;
  watch_error_step = "running";
  pthread_mutex_unlock(&watch_lock);
  return BRIDGE_STATUS_OK;
}

int bridge_ime_normal(char *state_out, size_t state_out_sz) {
  if (!state_out || state_out_sz == 0) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  int ascii = main_conn_is_ascii();
  if (ascii < 0) {
    return BRIDGE_STATUS_FAILED;
  }
  int current_status = ascii ? 0 : 1;
  saved_ime_status = current_status;

  if (current_status == 1 && main_conn_set_ascii(true) != 0) {
    return BRIDGE_STATUS_FAILED;
  }

  // Report the pre-switch state so stateless callers can remember what to
  // restore on the next insert.
  strncpy(state_out, status_to_state(current_status), state_out_sz - 1);
  state_out[state_out_sz - 1] = '\0';
  return BRIDGE_STATUS_OK;
}

int bridge_ime_insert(const char *restore, char *state_out, size_t state_out_sz) {
  if (!state_out || state_out_sz == 0) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  bool target_is_ime = false;
  if (restore != NULL) {
    target_is_ime = (strcmp(restore, "ime") == 0);
  } else if (saved_ime_status != -1) {
    target_is_ime = (saved_ime_status == 1);
  }

  if (target_is_ime && main_conn_set_ascii(false) != 0) {
    return BRIDGE_STATUS_FAILED;
  }

  strncpy(state_out, target_is_ime ? "ime" : "ascii", state_out_sz - 1);
  state_out[state_out_sz - 1] = '\0';
  return BRIDGE_STATUS_OK;
}

int bridge_ime_watch(bool enable) {
  int status = ensure_watcher_started();
  if (status != BRIDGE_STATUS_OK) {
    return status;
  }

  pthread_mutex_lock(&watch_lock);
  watch_enabled = enable;
  baseline_pending = enable;
  if (!enable) {
    last_watch_status = -1;
  }
  pthread_mutex_unlock(&watch_lock);
  return BRIDGE_STATUS_OK;
}

unsigned long bridge_ime_watch_error(void) {
  return watch_error;
}

const char *bridge_ime_watch_error_step(void) {
  return watch_error_step;
}

void bridge_ime_shutdown(void) {
  pthread_mutex_lock(&watch_lock);
  bool started = watcher_started;
  watch_stop = true;
  watch_enabled = false;
  baseline_pending = false;
  last_watch_status = -1;
  watcher_started = false;
  pthread_mutex_unlock(&watch_lock);

  if (started) {
    pthread_join(watch_thread, NULL);
  }
  close_conn(&main_conn);
}
