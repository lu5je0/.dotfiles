import vim
import re

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

def keepMatchs(pattern):
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
    cur_buffer = vim.current.buffer
    number = cur_buffer.number
    is_edit = int(vim.eval("getbufvar(bufname(), \"&mod\")")) == 1
    buftype = getBufType(number)
    if buftype != "":
        vim.command("quit")
        return

    if is_edit:
        confirm = int(vim.eval('''confirm("Close without saving?", "&No\n&Yes")'''))
        if confirm != 2:
            print("Canceled")
            return

    count = 0
    has_same_buffer = False
    for window in vim.current.tabpage.windows:
        buffer = window.buffer
        if buffer.number == number:
            has_same_buffer = True
        if getBufType(buffer.number) == "":
            count += 1
            if count > 1:
                break
    if count <= 1:
        vim.command("bp")
    elif has_same_buffer:
        vim.command("quit!")
        return
    vim.command("bd! " + str(number))
