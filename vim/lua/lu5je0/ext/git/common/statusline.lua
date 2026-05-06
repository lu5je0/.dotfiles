local string_utils = require('lu5je0.lang.string-utils')

local M = {}

local function escape_statusline(text)
  return tostring(text or ''):gsub('%%', '%%%%')
end

function M.short_filename(path, max_len)
  local filename = vim.fn.fnamemodify(path or '', ':t')
  if filename == '' then
    filename = path or ''
  end
  return string_utils.get_short_filename(filename, max_len or 25)
end

function M.dual(side, rev, path, opts)
  opts = opts or {}
  local side_hl = side == 'NEW' and 'Number' or 'Comment'
  local filename = M.short_filename(path, opts.max_filename_len)
  return string.format(
    ' %%#%s#%s%%* %%#Special#%s%%* %%#Comment#%s%%*',
    side_hl,
    escape_statusline(side),
    escape_statusline(rev),
    escape_statusline(filename)
  )
end

function M.log(label, value, opts)
  opts = opts or {}
  local value_hl = opts.loading and 'Special' or 'Number'
  local suffix = opts.limited and '%#WarningMsg#+%*' or ''
  return string.format(
    ' %%#Function#%s%%* %%#%s#%s%%*%s',
    escape_statusline(label),
    value_hl,
    escape_statusline(value),
    suffix
  )
end

function M.log_count(label, count, unit, opts)
  opts = opts or {}
  if opts.loading then
    return M.log(label, 'loading', { loading = true })
  end
  return M.log(label, string.format('%d %s', count, unit), {
    limited = opts.limited,
  })
end

return M
