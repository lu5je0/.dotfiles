import vim
import time
import re
from datetime import datetime, timedelta

def executeTime(func):
    def wrapper(*args, **kw):
        now = time.time()
        r = func(*args, **kw)
        print("Took", time.time() - now, "seconds")
        return r
    return wrapper

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
def replace_all_timestamp(surround):
    if len(surround) != 0:
        surround = surround[0]
    else:
        surround = ''
    
    # 获取当前时间
    current_time = datetime.now()

    # 计算10年前和5年后的时间
    years_ago = current_time - timedelta(days=365*10)
    years_later = current_time + timedelta(days=365*5)

    # 将时间转换为时间戳（以秒为单位）
    timestamp_five_years_ago = years_ago.timestamp()
    timestamp_five_years_later = years_later.timestamp()

    # 正则表达式匹配时间戳（秒或毫秒）
    timestamp_pattern = re.compile(r'(?<!\d)(\d{10,13})(?!\d)')

    def convert_timestamp(match):
        timestamp = int(match.group())
        # 如果是毫秒时间戳，转换为秒
        if len(match.group()) == 13:
            timestamp /= 1000
        # 检查时间戳是否在范围内
        if timestamp_five_years_ago <= timestamp <= timestamp_five_years_later:
            dt = datetime.fromtimestamp(timestamp)
            return surround + dt.strftime('%Y-%m-%d %H:%M:%S') + surround
        return match.group()

    buffer = vim.current.buffer
    for i, line in enumerate(buffer):
        buffer[i] = timestamp_pattern.sub(convert_timestamp, line)
    
@resetFileTypeTemporary
def set_operation(operations):
    if len(operations) == 0:
        return
    
    operation = operations[0]
    
    buffer = vim.current.buffer
    
    set_a = set()
    set_b = set()
    
    blank_line_count = 0
    for line in buffer:
        if line.strip() == '':
            blank_line_count += 1
            continue
        if blank_line_count == 0:
            set_a.add(line)
        else:
            set_b.add(line)
    if blank_line_count != 1:
        print('Only one empty line allowed')
        return
    
    if operation == 'intersection':
        result_set = set_a & set_b
    elif operation == 'difference':
        result_set = set_a - set_b
    elif operation == 'union':
        result_set = set_a | set_b
    elif operation == 'complement':
        result_set = set_a ^ set_b
    elif operation == 'symmetric-difference': # 对称差是指两个集合的并集减去其交集的部分
        result_set = (set_a | set_b) - (set_a & set_b)
    else:
        print('Unknown operation: ' + str(operation))
        return
    
    result_set = sorted(list(result_set))

    if len(result_set) < len(buffer):
        for num in range(len(buffer) - 1, len(result_set) - 1, -1):
            del(buffer[num])
            
    for i, line in enumerate(result_set):
        buffer[i] = line
        
    print('Operation {} done'.format(operation))


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
