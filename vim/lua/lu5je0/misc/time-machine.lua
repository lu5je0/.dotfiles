local M = {}

local PATH = vim.fn.stdpath("state") .. '/time-machine/'
local MAX_KEEP_LINES = 2000
local MAX_KEEP_FILE_CNT = 5

local cnt = 0
local function assemble_file_name(buf_nr)
  local filetype = vim.bo[buf_nr].filetype
  if filetype == '' then
    filetype = 'txt'
  end
  local filename = os.date("%Y-%m-%dT%H:%M:%S-", os.time()) .. cnt .. '.' .. filetype
  cnt = cnt + 1
  return filename
end

local function do_save(buf_nr)
  local filename = assemble_file_name(buf_nr)
  local lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
  
  if #lines > MAX_KEEP_LINES then
    return
  end
  
  local file = io.open(PATH .. filename, "w+")
  if file then
    for _, line in ipairs(lines) do
      file:write(line)
      file:write('\n')
    end
    file:flush()
  end
end

local function clear_old_file()
  local files = {}
  for file in vim.fs.dir(PATH) do
    table.insert(files, file)
  end
  table.sort(files)
  
  if #files > MAX_KEEP_FILE_CNT then
    local need_del_cnt = #files - MAX_KEEP_FILE_CNT 
    for i, filename in ipairs(files) do
      if i <= need_del_cnt then
        -- print('deleting ' .. filename)
        vim.fn.delete(PATH .. filename)
      end
    end
  end
end

local function create_dir_if_absent()
  if vim.fn.isdirectory(PATH) == 0 then
    vim.fn.system('mkdir -p ' .. PATH)
  end
end

-- 保存buffer
function M.save_buffer(buf_nr)
  -- 只有buffer没有文件名并且文件编辑过才保存
  if vim.api.nvim_buf_get_name(buf_nr) ~= "" and vim.bo.modified then
    return
  end
  
  create_dir_if_absent()
  do_save(buf_nr)
  clear_old_file()
end

-- 返回保存目录
function M.get_path()
  return PATH
end

return M
