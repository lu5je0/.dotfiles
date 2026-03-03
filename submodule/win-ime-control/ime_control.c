#include <imm.h>
#include <stdbool.h> // 用于 bool 类型
#include <stdio.h>
#include <string.h>
#include <windows.h>

// 链接 user32.lib 和 imm32.lib 库
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "imm32.lib")

// --- 手动定义缺失的IME控制常量 ---
#ifndef IMC_GETOPENSTATUS
#define IMC_GETOPENSTATUS 0x0005
#endif
#ifndef IMC_SETOPENSTATUS
#define IMC_SETOPENSTATUS 0x0006
#endif

// --- 状态保存变量 ---
static int saved_ime_status = -1; // -1: 未保存, 0: 英文(关闭), 1: 中文(打开)

// --- 核心输入法控制函数 ---

/**
 * @brief 设置输入法的打开状态 (开:中文, 关:英文)
 * @param is_open true 表示打开 (中文), false 表示关闭 (英文)
 */
void set_ime_open_status(bool is_open) {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd)
    return;
  HWND ime_hwnd = ImmGetDefaultIMEWnd(hwnd);
  if (!ime_hwnd)
    return;
  // 发送消息来设置输入法状态
  SendMessage(ime_hwnd, WM_IME_CONTROL, IMC_SETOPENSTATUS, is_open ? 1 : 0);
}

/**
 * @brief 获取当前输入法的打开状态
 * @return 1 表示打开 (中文), 0 表示关闭 (英文), -1 表示获取失败
 */
int get_ime_open_status() {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd)
    return -1;
  HWND ime_hwnd = ImmGetDefaultIMEWnd(hwnd);
  if (!ime_hwnd)
    return -1;
  // 发送消息来获取输入法状态
  LRESULT status = SendMessage(ime_hwnd, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0);
  return status != 0 ? 1 : 0;
}

// --- 辅助函数 ---

/**
 * @brief 打印程序用法帮助信息
 * @param prog_name 程序的可执行文件名
 */
void print_usage(const char *prog_name) {
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

/**
 * @brief 处理单个命令
 * @param command 要处理的命令字符串
 */
void process_command(const char *command) {
  if (command == NULL || command[0] == '\0') {
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
    // 查询失败时，静默处理
  } else if (strcmp(command, "normal") == 0) {
    int current_status = get_ime_open_status();
    if (current_status != -1) {
      saved_ime_status = current_status;
    }
    set_ime_open_status(false);
    printf("eng\n");
  } else if (strcmp(command, "insert") == 0) {
    if (saved_ime_status != -1) {
      bool target_is_open = (saved_ime_status == 1);
      set_ime_open_status(target_is_open);
      printf("%s\n", target_is_open ? "chi" : "eng");
    }
    // 如果未保存状态，静默处理
  }
  // 对于未知命令，静默处理
}

/**
 * @brief 运行交互模式主循环
 */
void run_interactive_mode() {
  char line[256];
  while (fgets(line, sizeof(line), stdin)) {
    // 移除 fgets 读取到的末尾换行符
    size_t len = strlen(line);
    if (len > 0 && line[len - 1] == '\n') {
      line[len - 1] = '\0';
    }

    // 检查退出命令
    if (strcmp(line, "exit") == 0) {
      break;
    }

    process_command(line);
  }
}

int main(int argc, char *argv[]) {
  // 设置控制台输出编码为 UTF-8，以正确显示中文
  SetConsoleOutputCP(CP_UTF8);

  const char *command = NULL;
  bool interactive_mode = false;
  bool show_help = false;

  // 解析命令行参数
  for (int i = 1; i < argc; ++i) {
    char *arg = argv[i];
    if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
      show_help = true;
      break;
    }
    if (strcmp(arg, "-i") == 0 || strcmp(arg, "--interactive") == 0) {
      interactive_mode = true;
    }
    // 检查是否是合法的命令，并且尚未指定过命令
    else if (command == NULL &&
             (strcmp(arg, "chi") == 0 || strcmp(arg, "eng") == 0 ||
              strcmp(arg, "status") == 0 || strcmp(arg, "normal") == 0 ||
              strcmp(arg, "insert") == 0)) {
      command = arg;
    }
  }

  // 根据解析结果决定执行路径
  if (show_help) {
    print_usage(argv[0]);
    return 0;
  }

  if (interactive_mode) {
    run_interactive_mode();
  } else {
    // 在非交互模式下，如果未提供命令，则显示错误并退出
    if (command == NULL) {
      fprintf(stderr, "错误: 未提供有效命令。使用 -h 查看帮助。\n");
      return 1;
    }
    process_command(command);
  }

  return 0;
}
