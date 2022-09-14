local M = {}


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

  for _, v in ipairs(attached_lsps) do
    print(_, v.server_capabilities.documentFormattingProvider)
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
  print(dump(server_capabilities))
  if format_type == M.FORMAT_TYPE.FORMAT then
    if server_capabilities.format then
      vim.lsp.buf.formatting({})
      return true
    end
  elseif format_type == M.FORMAT_TYPE.RANGE_FORMAT then
    if server_capabilities.format then
      vim.lsp.buf.range_formatting()
      return true
    end
  end
end

local function external_format(filetype)
  print('external_format')
  if not config.external_formatter[filetype] or not config.external_formatter[filetype].format then
    print('miss external_format')
    return false
  end
  config.external_formatter[filetype].format()
  print("external format done")
  return true
end

local function external_range_format(filetype)
  print('external_format')
  if not config.external_formatter[filetype] or not config.external_formatter[filetype].range_format then
    return false
  end
  config.external_formatter[filetype].range_format()
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
      if format_type == M.FORMAT_TYPE.FORMAT then
        if external_format(filetype) then
          print('external_format')
          return
        end
      end
      if format_type == M.FORMAT_TYPE.RANGE_FORMAT then
        if external_range_format(filetype) then
          print('external_range_format')
          return
        end
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
