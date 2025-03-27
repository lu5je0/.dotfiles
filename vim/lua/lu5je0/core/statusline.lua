local M = {}

local function get_location(win_id, buf_id)
  -- 验证窗口是否正在显示目标缓冲区
  local current_buf_in_win = vim.api.nvim_win_get_buf(win_id)
  if current_buf_in_win ~= buf_id then
    return "BufNotInWin"  -- 或返回 nil/自定义错误
  end

  -- 获取该窗口的实时光标位置（1-based 行号，0-based 列号）
  local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
  local line = cursor_pos[1]
  local col = cursor_pos[2] + 1  -- 转换为用户习惯的 1-based 列号
  return string.format("%3d:%-2d", line, col)
end

local function get_progress(win_id, buf_id)
  -- 验证窗口是否正在显示目标缓冲区
  local current_buf_in_win = vim.api.nvim_win_get_buf(win_id)
  if current_buf_in_win ~= buf_id then
    return "BufNotInWin"  -- 或返回 nil/自定义错误
  end

  -- 获取总行数和当前行
  local total = vim.api.nvim_buf_line_count(buf_id)
  local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
  local cur_line = cursor_pos[1]

  -- 计算进度
  if cur_line == 1 then
    return 'Top'
  elseif cur_line >= total then
    return 'Bot'
  else
    return string.format('%2d%%%%', math.floor(cur_line / total * 100))
  end
end

M.setup = function()
  -- 创建状态栏生成函数
  _G.MyStatusLine = function()
    local win_id = vim.g.statusline_winid
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    if vim.bo[buf_id].filetype == 'NvimTree' then
      return '%#StatusLineGrey# NVIMTREE'
    end

    local parts = {}

    -- 左侧组件
    table.insert(parts, "%#StatusLineYellow# NOR")

    -- table.insert(parts, "%#StatusLine#  ")    -- 白色图标

    local filename = vim.fn.expand('%:t')
    if filename == '' then
      filename = '[Untitled]'
    end
    table.insert(parts, "%#StatusLineGrey# " .. filename) -- 品红文字

    -- old
    -- table.insert(parts, "%=%#StatusLine#")  -- 右对齐
    -- table.insert(parts, "%l:%c  ")         -- 行列号

    -- new

    table.insert(parts, "%=%#StatusLine#")  -- 右对齐
    table.insert(parts, get_location(win_id, buf_id) .. " " .. get_progress(win_id, buf_id) .. "  ")         -- 行列号

    -- 编码信息
    local encoding = vim.fn.toupper(
      vim.o.fileencoding ~= '' 
      and vim.o.fileencoding 
      or vim.b.encoding
    )
    table.insert(parts, "%#StatusLineGreen#"..encoding.." ")

    -- 换行符
    table.insert(parts, "%{&fileformat == 'unix' ? 'LF' : 'CRLF'} ")

    return table.concat(parts, '')
  end

  -- 设置状态栏调用方式
  vim.cmd[[set statusline=%!v:lua.MyStatusLine()]]

  -- local bg = '#2c2e34'
  -- vim.cmd(string.gsub([[
  -- " hi NvimTreeNormal guibg=%s
  -- " hi NvimTreeNormalNC guibg=%s
  -- " hi NvimTreeEndOfBuffer guifg=%s
  --
  -- hi VertSplit guifg=#27292d guibg=bg
  -- hi NvimTreeVertSplit guifg=bg guibg=bg
  --
  -- hi NvimTreeWinSeparator guibg=%s guifg=%s
  -- ]], '%%s', bg))
end

return M
