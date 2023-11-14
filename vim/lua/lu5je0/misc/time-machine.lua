local M = {}

local PATH = vim.fn.stdpath("state") .. '/time-machine/'
local MAX_KEEP_LINES = 5000
local MAX_KEEP_FILE_CNT = 300
local MAX_KEEP_DAYS = 10

local cnt = 0
local function assemble_file_name(buf_nr)
  local filetype = vim.bo[buf_nr].filetype
  if filetype == '' then
    filetype = 'txt'
  end
  
  local cur_buf_name = vim.fn.expand('%:t')
  if cur_buf_name ~= "" then
    cur_buf_name = "-" .. cur_buf_name
  end
  
  local filename = os.date("%Y-%m-%dT%H:%M:%S-", os.time()) .. cnt .. cur_buf_name .. '.' .. filetype
  
  cnt = cnt + 1
  return filename
end

local function create_dir_if_absent()
  if vim.fn.isdirectory(PATH) == 0 then
    vim.fn.system('mkdir -p ' .. PATH)
  end
end

local function do_save(buf_nr)
  local filename = assemble_file_name(buf_nr)
  local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  
  if #lines == 1 and lines[1] == '' then
    return
  end
  
  if #lines > MAX_KEEP_LINES then
    return
  end
  
  create_dir_if_absent()
  local file = io.open(PATH .. filename, "w+")
  if file then
    for _, line in ipairs(lines) do
      file:write(line)
      file:write('\n')
    end
    file:flush()
    file:close()
  end
end

local function clear_old_file()
  local files = {}
  for file in vim.fs.dir(PATH) do
    table.insert(files, file)
  end
  
  -- 最大文件数清理
  if #files > MAX_KEEP_FILE_CNT then
    table.sort(files)
    local need_del_cnt = #files - MAX_KEEP_FILE_CNT 
    for i, filename in ipairs(files) do
      if i <= need_del_cnt then
        -- print('deleting ' .. filename)
        vim.fn.delete(PATH .. filename)
      end
    end
  end
  
  -- 最长日期清理，每次最多清理三个
  local max_process_cnt = 2
  for i, filename in ipairs(files) do
    if i <= max_process_cnt then
      local stat = vim.loop.fs_stat(PATH .. filename)
      if stat and stat.birthtime and vim.loop.gettimeofday() - stat.birthtime.sec > MAX_KEEP_DAYS * 24 * 60 * 60 then
        -- print('clear 过期文件' .. filename)
        vim.fn.delete(PATH .. filename)
      end
    end
  end
end

local function now()
  local timestamp, s = vim.loop.gettimeofday()
  return timestamp * 1000 + math.floor(s / 1000)
end

-- 保存buffer
function M.save_buffer(buf_nr)
  local timestamp = now()
  
  -- 只有buffer没有文件名并且文件编辑过 或者 文件不存在 才保存
  local filepath = vim.fn.expand('%:p')
  if vim.fn.filereadable(filepath) == 1 and vim.api.nvim_buf_get_name(buf_nr) ~= "" and vim.bo.modified then
    return
  end
  
  do_save(buf_nr)
  clear_old_file()
  
  local spent_mills = now() - timestamp
  if spent_mills > 100 then
    print('time-machine save buffer spent more than 300 mills')
  end
end

-- 返回保存目录
function M.get_path()
  return PATH
end

return M
