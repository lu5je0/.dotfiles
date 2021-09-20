import vim
import time
import re

def jsonFormat():
    import jsbeautifier
    buffer = vim.current.buffer
    json = "".join(buffer)

    opts = jsbeautifier.default_options()
    opts.indent_size = 2
    opts.space_in_empty_paren = True
    res = jsbeautifier.beautify(json, opts).split('\n')

    buffer[0:len(res)] = res
    if vim.eval("&ft") == "":
        vim.command("set filetype=json")

def resetFileTypeTemporary(func):
    def wrapper(*args, **kw):
        ft = vim.eval("&ft")
        vim.command("set ft=none")
        r = func(*args, **kw)
        vim.command("set ft=" + ft)
        return r
    return wrapper

@resetFileTypeTemporary
def keepLines(str_patterns):
    patterns = [re.compile(pattern) for pattern in str_patterns]
    buffer = vim.current.buffer

    rm_line_cnt = 0
    for num in range(len(buffer) - 1, -1, -1):
        flag = False
        for pattern in patterns:
            if pattern.search(buffer[num]) != None:
                flag = True
        if not flag:
            rm_line_cnt += 1
            del(buffer[num])
    print(str_patterns, ', del {} lines'.format(rm_line_cnt))

@resetFileTypeTemporary
def keepMatchs(pattern):
    ft = vim.eval("&ft")
    vim.command("set ft=none")
    pattern = re.compile(pattern)
    buffer = vim.current.buffer

    rm_line_cnt = 0
    for num in range(len(buffer) - 1, -1, -1):
        matchs = pattern.findall(buffer[num])
        if len(matchs) != 0:
            buffer[num] = " ".join(matchs)
        else:
            del(buffer[num])
    print('del {} lines'.format(rm_line_cnt))
    vim.command("set ft=" + ft)

@resetFileTypeTemporary
def delLines(str_patterns):
    patterns = [re.compile(pattern) for pattern in str_patterns]
    buffer = vim.current.buffer

    rm_line_cnt = 0
    for num in range(len(buffer) - 1, -1, -1):
        flag = False
        for pattern in patterns:
            if pattern.search(buffer[num]) != None:
                flag = True
        if flag:
            rm_line_cnt += 1
            del(buffer[num])
    print(str_patterns, ', del {} lines'.format(rm_line_cnt))

def getBufType(number):
    return vim.eval("getbufvar({}, \"&buftype\")".format(number))

def closeBuffer():
    try:
        cur_buffer = vim.current.buffer
        number = cur_buffer.number
        is_edit = int(vim.eval("getbufvar(bufname(), \"&mod\")")) == 1
        buftype = getBufType(number)

        buftype_list = ["", "acwrite", "nofile"]
        if buftype not in buftype_list: 
            # print("quit")
            vim.command("quit")
            return

        txt_window_count = 0
        for window in vim.current.tabpage.windows:
            buffer = window.buffer
            if getBufType(buffer.number) in buftype_list:
                txt_window_count += 1
                if txt_window_count > 1:
                    break

        # 如果编辑过buffer，则需要确认
        if is_edit and txt_window_count == 1:
            has_mac = int(vim.eval("has('mac')")) == 1
            if has_mac:
                vim.command("set guioptions+=c")
            confirm = int(vim.eval('''confirm("Close without saving?", "&No\n&Yes")'''))
            if has_mac:
                vim.command("set guioptions-=c")
            if confirm != 2:
                return

        # 一个tab页中有两个的buffer时，直接quit
        if txt_window_count == 1:
            # print("bd")
            vim.command("bp")
            vim.command("bd! " + str(number))
        else:
            # print("q")
            vim.command("q")
    except Exception as e:
        print("close waring", e)
