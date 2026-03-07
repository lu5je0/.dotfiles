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
