#include <stdio.h>
#include <string.h>
#include <stdbool.h>
// 引入 macOS 的核心服务和 Carbon 框架，其中包含了文本输入源服务
#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>

// --- 状态保存变量 ---
// 在 macOS 中，我们保存的是输入法源对象的引用，而不是一个简单的 0/1 状态
static TISInputSourceRef saved_input_source = NULL;

// --- 核心输入法控制函数 ---

/**
 * @brief 根据部分 ID 查找并返回第一个匹配的输入法源
 * @param target_id_prefixes 一个 C 字符串数组，包含要查找的输入法 ID 前缀
 * @param num_prefixes 数组中前缀的数量
 * @return 找到的 TISInputSourceRef 对象 (调用者需要释放), 或 NULL
 */
TISInputSourceRef find_input_source(const char* target_id_prefixes[], int num_prefixes) {
    // 构建一个属性字典，只选择已启用和可选的键盘布局输入源
    CFStringRef keys[] = { kTISPropertyInputSourceIsSelectCapable, kTISPropertyInputSourceIsEnabled };
    CFTypeRef values[] = { kCFBooleanTrue, kCFBooleanTrue };
    CFDictionaryRef properties = CFDictionaryCreate(kCFAllocatorDefault,
                                                    (const void**)keys, (const void**)values,
                                                    2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    // 获取所有符合条件的输入法列表 (*** THIS IS THE CORRECTED LINE ***)
    CFArrayRef sources = TISCreateInputSourceList(properties, false);
    CFRelease(properties);
    if (!sources) return NULL;

    TISInputSourceRef found_source = NULL;
    CFIndex num_sources = CFArrayGetCount(sources);

    // 遍历列表查找匹配的输入法
    for (CFIndex i = 0; i < num_sources; ++i) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
        // 获取输入法 ID (例如 "com.apple.keylayout.US")
        CFStringRef source_id_cf = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
        if (!source_id_cf) continue;

        char source_id_str[256];
        // 将 CFString 转换为 C 字符串
        CFStringGetCString(source_id_cf, source_id_str, sizeof(source_id_str), kCFStringEncodingUTF8);

        // 与提供的所有前缀进行比较
        for (int j = 0; j < num_prefixes; ++j) {
            if (strncmp(source_id_str, target_id_prefixes[j], strlen(target_id_prefixes[j])) == 0) {
                found_source = source;
                CFRetain(found_source); // 增加引用计数，因为我们将返回它
                goto end_loop;
            }
        }
    }

end_loop:
    CFRelease(sources); // 释放输入法列表
    return found_source;
}

/**
 * @brief 切换到指定的输入法
 * @param is_chinese true 表示切换到中文, false 表示切换到英文
 */
void set_ime_status(bool is_chinese) {
    // 常见的英文输入法 ID 前缀
    const char* eng_prefixes[] = {
        "com.apple.keylayout.US",         // 美式键盘
        "com.apple.keylayout.ABC"         // "ABC" 键盘 (较新 macOS 版本)
    };
    // 常见的简体中文输入法 ID 前缀
    const char* chi_prefixes[] = {
        "com.apple.inputmethod.SC.Pinyin",// 官方拼音
        "com.sogou.inputmethod.sogou",    // 搜狗输入法
        "com.baidu.inputmethod.Baidu",    // 百度输入法
        "com.apple.inputmethod.SC"        // 匹配所有苹果官方简体中文输入法
    };

    TISInputSourceRef source = NULL;
    if (is_chinese) {
        source = find_input_source(chi_prefixes, sizeof(chi_prefixes) / sizeof(chi_prefixes[0]));
    } else {
        source = find_input_source(eng_prefixes, sizeof(eng_prefixes) / sizeof(eng_prefixes[0]));
    }

    if (source) {
        TISSelectInputSource(source); // 切换输入法
        CFRelease(source);            // 释放我们找到的输入法对象
    }
}

/**
 * @brief 获取当前输入法状态
 * @return "chi" 表示中文, "eng" 表示英文, NULL 表示未知
 */
const char* get_ime_status_string() {
    TISInputSourceRef current_source = TISCopyCurrentKeyboardInputSource();
    if (!current_source) return NULL;

    CFStringRef source_id_cf = TISGetInputSourceProperty(current_source, kTISPropertyInputSourceID);
    if (!source_id_cf) {
        CFRelease(current_source);
        return NULL;
    }

    char source_id_str[256];
    CFStringGetCString(source_id_cf, source_id_str, sizeof(source_id_str), kCFStringEncodingUTF8);
    CFRelease(current_source); // 释放当前输入法对象

    // 检查是否是中文或英文
    if (strncmp(source_id_str, "com.apple.inputmethod.SC", strlen("com.apple.inputmethod.SC")) == 0 ||
        strncmp(source_id_str, "com.apple.inputmethod.TC", strlen("com.apple.inputmethod.TC")) == 0 ||
        strncmp(source_id_str, "com.sogou", strlen("com.sogou")) == 0 ||
        strncmp(source_id_str, "com.baidu", strlen("com.baidu")) == 0) {
        return "chi";
    }
    // 英文输入法通常是 keylayout 类型
    if (strncmp(source_id_str, "com.apple.keylayout", strlen("com.apple.keylayout")) == 0) {
        return "eng";
    }

    return NULL; // 未知状态
}

// --- 辅助函数 (与 Windows 版本几乎相同) ---

void print_usage(const char* prog_name) {
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

void process_command(const char* command) {
    if (command == NULL || command[0] == '\0') {
        return;
    }

    if (strcmp(command, "chi") == 0) {
        set_ime_status(true);
    }
    else if (strcmp(command, "eng") == 0) {
        set_ime_status(false);
    }
    else if (strcmp(command, "status") == 0) {
        const char* status = get_ime_status_string();
        if (status) {
            printf("%s\n", status);
        }
    }
    else if (strcmp(command, "normal") == 0) {
        TISInputSourceRef current_source = TISCopyCurrentKeyboardInputSource();
        if (current_source) {
            if (saved_input_source) {
                CFRelease(saved_input_source); // 释放之前保存的
            }
            saved_input_source = current_source; // 保存新的 (Copy 函数返回的对象引用计数为1, 无需再 Retain)
        }
        set_ime_status(false);
        printf("eng\n");
    }
    else if (strcmp(command, "insert") == 0) {
        if (saved_input_source) {
            TISSelectInputSource(saved_input_source);
            const char* status = get_ime_status_string();
             if (status) {
                printf("%s\n", status);
            }
        }
    }
}

void run_interactive_mode() {
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

int main(int argc, char* argv[]) {
    // macOS 默认使用 UTF-8，无需特殊设置

    const char* command = NULL;
    bool interactive_mode = false;
    bool show_help = false;

    for (int i = 1; i < argc; ++i) {
        char* arg = argv[i];
        if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
            show_help = true;
            break;
        }
        if (strcmp(arg, "-i") == 0 || strcmp(arg, "--interactive") == 0) {
            interactive_mode = true;
        }
        else if (command == NULL &&
                 (strcmp(arg, "chi") == 0 || strcmp(arg, "eng") == 0 ||
                  strcmp(arg, "status") == 0 || strcmp(arg, "normal") == 0 ||
                  strcmp(arg, "insert") == 0))
        {
            command = arg;
        }
    }

    if (show_help) {
        print_usage(argv[0]);
        return 0;
    }

    if (interactive_mode) {
        run_interactive_mode();
    } else {
        if (command == NULL) {
            fprintf(stderr, "错误: 未提供有效命令。使用 -h 查看帮助。\n");
            return 1;
        }
        process_command(command);
    }

    // 程序结束前，释放保存的输入法对象
    if (saved_input_source) {
        CFRelease(saved_input_source);
    }

    return 0;
}
