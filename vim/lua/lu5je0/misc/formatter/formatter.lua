local M = {}

local cursor_util = require('lu5je0.core.cursor')


M.FORMAT_TOOL_TYPE = {
  LSP = 'LSP',
  EXTERNAL = 'EXTERNAL'
}

M.FORMAT_TYPE = {
  FORMAT = 'FORMAT',
  RANGE_FORMAT = 'RANGE_FORMAT'
}

local config = {}

local get_format_priority = function(filetype)
  if config.format_priority[filetype] then
    return config.format_priority[filetype]
  end
  return { M.FORMAT_TOOL_TYPE.LSP, M.FORMAT_TOOL_TYPE.EXTERNAL }
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
      vim.lsp.buf.formatting({})
      return true
    end
  elseif format_type == M.FORMAT_TYPE.RANGE_FORMAT then
    if server_capabilities.format then
      ---@diagnostic disable-next-line: missing-parameter
      vim.lsp.buf.range_formatting()
      return true
    end
  end
end

local function external_format(format_type, filetype)
  if not config.external_formatter[filetype] then
    print('miss format config')
    return
  end
  
  cursor_util.save_position()
  print('external_format')
  if format_type == M.FORMAT_TYPE.FORMAT then
    if not config.external_formatter[filetype].format then
      print('miss external_format')
      return false
    end
    config.external_formatter[filetype].format()
  elseif format_type == M.FORMAT_TYPE.RANGE_FORMAT then
    if not config.external_formatter[filetype].range_format then
      print('miss range external_format')
      return false
    end
    config.external_formatter[filetype].range_format()
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
        print('lsp_format')
        return
      end
    end

    -- external format
    if v == M.FORMAT_TOOL_TYPE.EXTERNAL then
      if external_format(format_type, filetype) then
        print('external format')
        return
      end
    end
  end
end

local function keymapping()
  local opts = {}

  vim.defer_fn(function()
    vim.keymap.set('n', '<leader>cf', function()
      M.format(M.FORMAT_TYPE.FORMAT)
    end, opts)

    vim.keymap.set('x', '<leader>cf', function()
      M.format(M.FORMAT_TYPE.RANGE_FORMAT)
    end, opts)
  end, 10)
end

function M.setup(params)
  -- default format_methods={ 'LSP' }
  config = params

  keymapping()
end

return M
