#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <imm.h>
#include <windows.h>
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "imm32.lib")

#ifndef IMC_GETOPENSTATUS
#define IMC_GETOPENSTATUS 0x0005
#endif
#ifndef IMC_SETOPENSTATUS
#define IMC_SETOPENSTATUS 0x0006
#endif
#elif defined(__APPLE__)
#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>
#endif

static int saved_ime_status = -1; // -1: unknown, 0: eng, 1: chi

#if defined(_WIN32)
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
#elif defined(__APPLE__)
static int cstr_has_prefix(const char *str, const char *prefix) {
  return strncmp(str, prefix, strlen(prefix)) == 0;
}

static int source_id_to_status(const char *source_id) {
  if (cstr_has_prefix(source_id, "com.apple.inputmethod.SC") ||
      cstr_has_prefix(source_id, "com.apple.inputmethod.TC") ||
      cstr_has_prefix(source_id, "com.sogou") ||
      cstr_has_prefix(source_id, "com.baidu")) {
    return 1;
  }
  if (cstr_has_prefix(source_id, "com.apple.keylayout")) {
    return 0;
  }
  return -1;
}

static TISInputSourceRef find_input_source(const char *prefixes[], int prefix_count) {
  CFStringRef keys[] = {kTISPropertyInputSourceIsSelectCapable,
                        kTISPropertyInputSourceIsEnabled};
  CFTypeRef values[] = {kCFBooleanTrue, kCFBooleanTrue};
  CFDictionaryRef properties =
      CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 2,
                         &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  if (!properties) {
    return NULL;
  }

  CFArrayRef sources = TISCreateInputSourceList(properties, false);
  CFRelease(properties);
  if (!sources) {
    return NULL;
  }

  TISInputSourceRef found = NULL;
  CFIndex count = CFArrayGetCount(sources);
  for (CFIndex i = 0; i < count; ++i) {
    TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
    CFStringRef source_id_cf =
        TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    if (!source_id_cf) {
      continue;
    }

    char source_id[256];
    if (!CFStringGetCString(source_id_cf, source_id, sizeof(source_id),
                            kCFStringEncodingUTF8)) {
      continue;
    }

    for (int j = 0; j < prefix_count; ++j) {
      if (cstr_has_prefix(source_id, prefixes[j])) {
        found = source;
        CFRetain(found);
        goto done;
      }
    }
  }

done:
  CFRelease(sources);
  return found;
}

static void set_ime_open_status(bool is_open) {
  const char *eng_prefixes[] = {"com.apple.keylayout.US", "com.apple.keylayout.ABC"};
  const char *chi_prefixes[] = {"com.apple.inputmethod.SC.Pinyin",
                                "com.sogou.inputmethod.sogou",
                                "com.baidu.inputmethod.Baidu",
                                "com.apple.inputmethod.SC"};

  const char **prefixes = is_open ? chi_prefixes : eng_prefixes;
  int prefix_count = is_open ? (int)(sizeof(chi_prefixes) / sizeof(chi_prefixes[0]))
                             : (int)(sizeof(eng_prefixes) / sizeof(eng_prefixes[0]));

  TISInputSourceRef source = find_input_source(prefixes, prefix_count);
  if (!source) {
    return;
  }
  TISSelectInputSource(source);
  CFRelease(source);
}

static int get_ime_open_status(void) {
  TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
  if (!current) {
    return -1;
  }

  CFStringRef source_id_cf = TISGetInputSourceProperty(current, kTISPropertyInputSourceID);
  if (!source_id_cf) {
    CFRelease(current);
    return -1;
  }

  char source_id[256];
  if (!CFStringGetCString(source_id_cf, source_id, sizeof(source_id),
                          kCFStringEncodingUTF8)) {
    CFRelease(current);
    return -1;
  }
  CFRelease(current);
  return source_id_to_status(source_id);
}
#else
#error "Unsupported platform"
#endif

static void print_usage(const char *prog_name) {
  fprintf(stderr, "用法: %s [命令] [选项]\n\n", prog_name);
  fprintf(stderr, "命令:\n");
  fprintf(stderr, "  chi       切换到中文输入模式\n");
  fprintf(stderr, "  eng       切换到英文输入模式\n");
  fprintf(stderr, "  status    查询当前输入模式\n");
  fprintf(stderr, "  normal    切换到英文模式并记住当前状态\n");
  fprintf(stderr, "  insert    切换到上次'normal'记住的状态\n\n");
  fprintf(stderr, "选项:\n");
  fprintf(stderr, "  -i, --interactive    进入交互模式\n");
  fprintf(stderr, "  -h, --help           显示此帮助信息\n");
}

static void process_command(const char *command) {
  if (!command || command[0] == '\0') {
    return;
  }

  if (strcmp(command, "chi") == 0) {
    set_ime_open_status(true);
  } else if (strcmp(command, "eng") == 0) {
    set_ime_open_status(false);
  } else if (strcmp(command, "status") == 0) {
    int status = get_ime_open_status();
    if (status == 1) {
      printf("chi\n");
    } else if (status == 0) {
      printf("eng\n");
    }
  } else if (strcmp(command, "normal") == 0) {
    int current_status = get_ime_open_status();
    if (current_status != -1) {
      saved_ime_status = current_status;
    }
    set_ime_open_status(false);
    printf("eng\n");
  } else if (strcmp(command, "insert") == 0) {
    if (saved_ime_status != -1) {
      bool target_is_open = saved_ime_status == 1;
      set_ime_open_status(target_is_open);
      printf("%s\n", target_is_open ? "chi" : "eng");
    }
  }
}

static void run_interactive_mode(void) {
  char line[256];
  while (fgets(line, sizeof(line), stdin)) {
    size_t len = strlen(line);
    if (len > 0 && line[len - 1] == '\n') {
      line[len - 1] = '\0';
    }
    if (strcmp(line, "exit") == 0) {
      break;
    }
    process_command(line);
  }
}

int main(int argc, char *argv[]) {
#if defined(_WIN32)
  SetConsoleOutputCP(CP_UTF8);
#endif

  const char *command = NULL;
  bool interactive_mode = false;
  bool show_help = false;

  for (int i = 1; i < argc; ++i) {
    char *arg = argv[i];
    if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
      show_help = true;
      break;
    }
    if (strcmp(arg, "-i") == 0 || strcmp(arg, "--interactive") == 0) {
      interactive_mode = true;
    } else if (!command && (strcmp(arg, "chi") == 0 || strcmp(arg, "eng") == 0 ||
                            strcmp(arg, "status") == 0 ||
                            strcmp(arg, "normal") == 0 ||
                            strcmp(arg, "insert") == 0)) {
      command = arg;
    }
  }

  if (show_help) {
    print_usage(argv[0]);
    return 0;
  }
  if (interactive_mode) {
    run_interactive_mode();
    return 0;
  }
  if (!command) {
    fprintf(stderr, "错误: 未提供有效命令。使用 -h 查看帮助。\n");
    return 1;
  }

  process_command(command);
  return 0;
}
