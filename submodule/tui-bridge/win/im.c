#include <windows.h>
#include <imm.h>
#include <stdbool.h>
#include <string.h>

#include "../bridge-status.h"
#include "../im.h"

#ifndef IMC_GETOPENSTATUS
#define IMC_GETOPENSTATUS 0x0005
#endif
#ifndef IMC_SETOPENSTATUS
#define IMC_SETOPENSTATUS 0x0006
#endif

static int saved_ime_status = -1;

static HANDLE watch_thread = NULL;
static HANDLE watch_ready_event = NULL;
static HANDLE watch_stop_event = NULL;
static CRITICAL_SECTION watch_lock;
static bool watch_lock_ready = false;
static bool watcher_started = false;
static bool watch_enabled = false;
static bool baseline_pending = false;
static int last_watch_status = -1;
static unsigned long watch_error = 0;
static const char *watch_error_step = "not_started";

static void ensure_watch_lock(void) {
  if (!watch_lock_ready) {
    InitializeCriticalSection(&watch_lock);
    watch_lock_ready = true;
  }
}

static void set_ime_open_status(bool is_open) {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd) {
    return;
  }
  HWND ime_hwnd = ImmGetDefaultIMEWnd(hwnd);
  if (!ime_hwnd) {
    return;
  }
  SendMessage(ime_hwnd, WM_IME_CONTROL, IMC_SETOPENSTATUS, is_open ? 1 : 0);
}

static int get_ime_open_status(void) {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd) {
    return -1;
  }
  HWND ime_hwnd = ImmGetDefaultIMEWnd(hwnd);
  if (!ime_hwnd) {
    return -1;
  }
  LRESULT status = SendMessage(ime_hwnd, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0);
  return status != 0 ? 1 : 0;
}

static const char *status_to_state(int status) {
  return status == 1 ? "chi" : "eng";
}

static DWORD WINAPI watch_thread_main(void *unused) {
  (void)unused;

  watch_error = 0;
  watch_error_step = "running";
  SetEvent(watch_ready_event);

  while (WaitForSingleObject(watch_stop_event, 120) == WAIT_TIMEOUT) {
    bool current_watch_enabled;
    bool current_baseline_pending;
    int current_status;

    EnterCriticalSection(&watch_lock);
    current_watch_enabled = watch_enabled;
    current_baseline_pending = baseline_pending;
    LeaveCriticalSection(&watch_lock);

    if (!current_watch_enabled) {
      continue;
    }

    current_status = get_ime_open_status();
    if (current_status == -1) {
      continue;
    }

    if (current_baseline_pending) {
      EnterCriticalSection(&watch_lock);
      last_watch_status = current_status;
      baseline_pending = false;
      LeaveCriticalSection(&watch_lock);
      continue;
    }

    EnterCriticalSection(&watch_lock);
    if (current_status != last_watch_status) {
      last_watch_status = current_status;
      LeaveCriticalSection(&watch_lock);
      bridge_emit_ime_changed_state(status_to_state(current_status));
      continue;
    }
    LeaveCriticalSection(&watch_lock);
  }

  return 0;
}

static int ensure_watcher_started(void) {
  HANDLE thread_handle;
  HANDLE ready_event;
  HANDLE stop_event;

  ensure_watch_lock();

  EnterCriticalSection(&watch_lock);
  if (watcher_started) {
    LeaveCriticalSection(&watch_lock);
    return BRIDGE_STATUS_OK;
  }

  ready_event = CreateEvent(NULL, TRUE, FALSE, NULL);
  stop_event = CreateEvent(NULL, TRUE, FALSE, NULL);
  if (!ready_event || !stop_event) {
    if (ready_event) {
      CloseHandle(ready_event);
    }
    if (stop_event) {
      CloseHandle(stop_event);
    }
    watch_error = GetLastError();
    watch_error_step = "create_event";
    LeaveCriticalSection(&watch_lock);
    return BRIDGE_STATUS_FAILED;
  }

  watch_ready_event = ready_event;
  watch_stop_event = stop_event;
  watch_error = 0;
  watch_error_step = "create_thread";

  thread_handle = CreateThread(NULL, 0, watch_thread_main, NULL, 0, NULL);
  if (!thread_handle) {
    watch_error = GetLastError();
    CloseHandle(watch_ready_event);
    CloseHandle(watch_stop_event);
    watch_ready_event = NULL;
    watch_stop_event = NULL;
    LeaveCriticalSection(&watch_lock);
    return BRIDGE_STATUS_FAILED;
  }

  watch_thread = thread_handle;
  watcher_started = true;
  LeaveCriticalSection(&watch_lock);

  WaitForSingleObject(watch_ready_event, INFINITE);
  return BRIDGE_STATUS_OK;
}

int bridge_ime_call(const char *method, char *state_out, size_t state_out_sz) {
  if (!method || !state_out || state_out_sz == 0) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  if (strcmp(method, "normal") == 0) {
    int current_status = get_ime_open_status();
    if (current_status != -1) {
      saved_ime_status = current_status;
    }
    set_ime_open_status(false);
    strncpy(state_out, "eng", state_out_sz - 1);
    state_out[state_out_sz - 1] = '\0';
    return BRIDGE_STATUS_OK;
  }

  if (strcmp(method, "insert") == 0) {
    bool target_is_open = false;
    if (saved_ime_status != -1) {
      target_is_open = (saved_ime_status == 1);
    }
    set_ime_open_status(target_is_open);
    strncpy(state_out, target_is_open ? "chi" : "eng", state_out_sz - 1);
    state_out[state_out_sz - 1] = '\0';
    return BRIDGE_STATUS_OK;
  }

  return BRIDGE_STATUS_INVALID_METHOD;
}

int bridge_ime_watch(bool enable) {
  int status = ensure_watcher_started();

  if (status != BRIDGE_STATUS_OK) {
    return status;
  }

  EnterCriticalSection(&watch_lock);
  watch_enabled = enable;
  baseline_pending = enable;
  if (!enable) {
    last_watch_status = -1;
  }
  LeaveCriticalSection(&watch_lock);

  return BRIDGE_STATUS_OK;
}

unsigned long bridge_ime_watch_error(void) {
  return watch_error;
}

const char *bridge_ime_watch_error_step(void) {
  return watch_error_step;
}

void bridge_ime_shutdown(void) {
  HANDLE thread_handle = NULL;
  HANDLE ready_event = NULL;
  HANDLE stop_event = NULL;

  if (!watch_lock_ready) {
    return;
  }

  EnterCriticalSection(&watch_lock);
  thread_handle = watch_thread;
  ready_event = watch_ready_event;
  stop_event = watch_stop_event;
  watch_thread = NULL;
  watch_ready_event = NULL;
  watch_stop_event = NULL;
  watcher_started = false;
  watch_enabled = false;
  baseline_pending = false;
  last_watch_status = -1;
  LeaveCriticalSection(&watch_lock);

  if (stop_event) {
    SetEvent(stop_event);
  }
  if (thread_handle) {
    WaitForSingleObject(thread_handle, 2000);
    CloseHandle(thread_handle);
  }
  if (ready_event) {
    CloseHandle(ready_event);
  }
  if (stop_event) {
    CloseHandle(stop_event);
  }

  DeleteCriticalSection(&watch_lock);
  watch_lock_ready = false;
}
