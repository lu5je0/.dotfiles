#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "../bridge-status.h"
#include "../clipboard-bridge.h"

static char *utf16_to_utf8(const wchar_t *wstr) {
  if (!wstr) {
    return NULL;
  }
  int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
  if (len <= 0) {
    return NULL;
  }

  char *out = (char *)malloc((size_t)len);
  if (!out) {
    return NULL;
  }

  if (WideCharToMultiByte(CP_UTF8, 0, wstr, -1, out, len, NULL, NULL) <= 0) {
    free(out);
    return NULL;
  }
  return out;
}

static wchar_t *utf8_to_utf16(const char *str) {
  if (!str) {
    return NULL;
  }
  int len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
  if (len <= 0) {
    return NULL;
  }

  wchar_t *out = (wchar_t *)malloc((size_t)len * sizeof(wchar_t));
  if (!out) {
    return NULL;
  }

  if (MultiByteToWideChar(CP_UTF8, 0, str, -1, out, len) <= 0) {
    free(out);
    return NULL;
  }
  return out;
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

  if (!OpenClipboard(NULL)) {
    return BRIDGE_STATUS_FAILED;
  }

  HANDLE data = GetClipboardData(CF_UNICODETEXT);
  if (!data) {
    CloseClipboard();
    return BRIDGE_STATUS_FAILED;
  }

  wchar_t *wtext = (wchar_t *)GlobalLock(data);
  if (!wtext) {
    CloseClipboard();
    return BRIDGE_STATUS_FAILED;
  }

  char *utf8 = utf16_to_utf8(wtext);
  GlobalUnlock(data);
  CloseClipboard();

  if (!utf8) {
    return BRIDGE_STATUS_FAILED;
  }

  normalize_lf_inplace(utf8);
  *text_out = utf8;
  return BRIDGE_STATUS_OK;
}

int bridge_clipboard_input(const char *text) {
  if (!text) {
    return BRIDGE_STATUS_INVALID_PARAMS;
  }

  wchar_t *wtext = utf8_to_utf16(text);
  if (!wtext) {
    return BRIDGE_STATUS_FAILED;
  }

  size_t bytes = (wcslen(wtext) + 1) * sizeof(wchar_t);
  HGLOBAL hmem = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!hmem) {
    free(wtext);
    return BRIDGE_STATUS_FAILED;
  }

  void *dst = GlobalLock(hmem);
  if (!dst) {
    GlobalFree(hmem);
    free(wtext);
    return BRIDGE_STATUS_FAILED;
  }
  memcpy(dst, wtext, bytes);
  GlobalUnlock(hmem);
  free(wtext);

  if (!OpenClipboard(NULL)) {
    GlobalFree(hmem);
    return BRIDGE_STATUS_FAILED;
  }

  if (!EmptyClipboard()) {
    CloseClipboard();
    GlobalFree(hmem);
    return BRIDGE_STATUS_FAILED;
  }

  if (!SetClipboardData(CF_UNICODETEXT, hmem)) {
    CloseClipboard();
    GlobalFree(hmem);
    return BRIDGE_STATUS_FAILED;
  }

  CloseClipboard();
  return BRIDGE_STATUS_OK;
}
