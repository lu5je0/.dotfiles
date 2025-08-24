#include <iostream>
#include <string>
#include <vector>
// chrono 和 iomanip 库已不再需要
#include <windows.h>
#include <imm.h>

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

// --- 核心输入法控制函数 (无改动) ---

void set_ime_open_status(bool is_open) {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return;
    HWND ime_hwnd = ImmGetDefaultIMEWnd(hwnd);
    if (!ime_hwnd) return;
    SendMessage(ime_hwnd, WM_IME_CONTROL, IMC_SETOPENSTATUS, is_open ? 1 : 0);
}

int get_ime_open_status() {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) return -1;
    HWND ime_hwnd = ImmGetDefaultIMEWnd(hwnd);
    if (!ime_hwnd) return -1;
    LRESULT status = SendMessage(ime_hwnd, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0);
    return status != 0 ? 1 : 0;
}

// --- 辅助函数 ---

void print_usage(const char* prog_name) {
    // 帮助信息中移除 --log 选项
    std::cerr << "用法: " << prog_name << " [命令] [选项]\n\n"
              << "命令:\n"
              << "  chi       切换到中文输入模式\n"
              << "  eng       切换到英文输入模式\n"
              << "  status    查询当前输入模式\n"
              << "  normal    切换到英文模式并记住当前状态\n"
              << "  insert    切换到上次'normal'记住的状态\n\n"
              << "选项:\n"
              << "  -i, --interactive    进入交互模式\n"
              << "  -h, --help           显示此帮助信息\n";
}

// 命令处理函数 (移除所有不必要的stderr输出)
void process_command(const std::string& command) {
    if (command.empty()) {
        return;
    }

    if (command == "chi") {
        set_ime_open_status(true);
    }
    else if (command == "eng") {
        set_ime_open_status(false);
    }
    else if (command == "status") {
        int status = get_ime_open_status();
        if (status == 1) std::cout << "chi" << std::endl;
        else if (status == 0) std::cout << "eng" << std::endl;
        // 查询失败时，静默处理，不输出
    }
    else if (command == "normal") {
        int current_status = get_ime_open_status();
        if (current_status != -1) {
            saved_ime_status = current_status;
        }
        set_ime_open_status(false);
        std::cout << "eng" << std::endl;
    }
    else if (command == "insert") {
        if (saved_ime_status != -1) {
            bool target_is_open = (saved_ime_status == 1);
            set_ime_open_status(target_is_open);
            std::cout << (target_is_open ? "chi" : "eng") << std::endl;
        }
        // 如果未保存状态，静默处理，不输出
    }
    // 对于未知命令，静默处理，不输出
}

// 交互模式主循环
void run_interactive_mode() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line == "exit") {
            break;
        }
        process_command(line);
    }
}

int main(int argc, char* argv[]) {
    SetConsoleOutputCP(CP_UTF8);

    std::string command;
    bool interactive_mode = false;
    bool show_help = false;

    // 解析参数 (移除 --log)
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            show_help = true;
            break; 
        }
        if (arg == "-i" || arg == "--interactive") {
            interactive_mode = true;
        }
        else if (command.empty() && (arg == "chi" || arg == "eng" || arg == "status" || arg == "normal" || arg == "insert")) {
            command = arg; 
        }
    }

    // 根据模式决定执行路径
    if (show_help) {
        print_usage(argv[0]);
        return 0;
    }

    if (interactive_mode) {
        run_interactive_mode();
    }
    else {
        // 只有在未提供命令时才打印错误，这是必要的提示
        if (command.empty()) {
            std::cerr << "错误: 未提供有效命令。使用 -h 查看帮助。\n";
            return 1;
        }
        process_command(command);
    }

    return 0;
}
