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

def closeBuffer():
    number = vim.current.buffer.number
    vim.command("bNext")
    vim.command("bdelete " + str(number))
