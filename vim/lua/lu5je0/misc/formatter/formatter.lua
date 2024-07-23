local M = {}

local cursor_util = require('lu5je0.core.cursor')
local log = function(...)
  if vim.g.enable_formatter_log then
    print(...)
  end
end

M.FORMAT_TOOL_TYPE = {
  LSP = 'LSP',
  EXTERNAL = 'EXTERNAL'
}

M.FORMAT_TYPE = {
  FORMAT = 'FORMAT',
  RANGE_FORMAT = 'RANGE_FORMAT'
}

local config = {}

local function get_format_priority(filetype)
  if config.format_priority[filetype] then
    return config.format_priority[filetype]
  end
  for k, v in pairs(config.format_priority) do
    if type(k) == "table" then
      for _, ft in ipairs(k) do
        if ft == filetype then
          return v
        end
      end
    end
  end

  return { M.FORMAT_TOOL_TYPE.LSP, M.FORMAT_TOOL_TYPE.EXTERNAL }
end

local function get_external_formatter(filetype)
  if config.external_formatter[filetype] then
    return config.external_formatter[filetype]
  end
  for k, v in pairs(config.external_formatter) do
    if type(k) == "table" then
      for _, ft in ipairs(k) do
        if ft == filetype then
          return v
        end
      end
    end
  end
end

local function is_exists_lsp_format_capabilities()
  local attached_lsps = vim.lsp.buf_get_clients(0)
  local result = {
    format = false,
    range_format = false
  }

  for _, v in pairs(attached_lsps) do
    if v.server_capabilities.documentFormattingProvider then
      result.format = true
    end
    if v.server_capabilities.documentRangeFormattingProvider then
      result.range_format = true
    end
  end

  return result
end

local function lsp_format(format_type)
  local server_capabilities = is_exists_lsp_format_capabilities()
  if format_type == M.FORMAT_TYPE.FORMAT then
    if server_capabilities.format then
      vim.lsp.buf.format { async = true }
      return true
    end
  elseif format_type == M.FORMAT_TYPE.RANGE_FORMAT then
    if server_capabilities.format then
      vim.lsp.buf.format { async = true }
      return true
    end
  end
end

local function external_format(format_type, filetype)
  local external_formatter = get_external_formatter(filetype)

  if not external_formatter then
    log('miss format config')
    return
  end

  cursor_util.save_position()
  if format_type == M.FORMAT_TYPE.FORMAT then
    if not external_formatter.format then
      log('miss external_format')
      return false
    end
    external_formatter.format()
  elseif format_type == M.FORMAT_TYPE.RANGE_FORMAT then
    if not external_formatter.range_format then
      log('miss range external_format')
      return false
    end
    local back_to_n = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
    vim.api.nvim_feedkeys(back_to_n, "x", false)
    
    -- 使用 vim.fn.getpos() 获取 '< 和 '> 标记的位置
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    -- start_pos[2] 和 end_pos[2] 分别是开始和结束的行号
    local start_line = start_pos[2]
    local end_line = end_pos[2]
    
    external_formatter.range_format(start_line, end_line)
  end
  cursor_util.goto_saved_position()
  return true
end

function M.format(format_type)
  local filetype = vim.bo.filetype
  local current_format_priority = get_format_priority(filetype)

  for _, v in ipairs(current_format_priority) do
    -- lsp format
    if v == M.FORMAT_TOOL_TYPE.LSP then
      if lsp_format(format_type) then
        -- print('lsp format')
        return
      end
    end

    -- external format
    if v == M.FORMAT_TOOL_TYPE.EXTERNAL then
      if external_format(format_type, filetype) then
        -- print('external format')
        return
      end
    end
  end
end

local function keymapping()
  local opts = {}

  vim.keymap.set('n', '<leader>cf', function()
    M.format(M.FORMAT_TYPE.FORMAT)
  end, opts)

  vim.keymap.set('x', '<leader>cf', function()
    M.format(M.FORMAT_TYPE.RANGE_FORMAT)
  end, opts)
end

function M.setup(params)
  -- default format_methods={ 'LSP' }
  config = params

  keymapping()
end

return M
