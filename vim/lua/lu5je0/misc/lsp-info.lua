local M = {}
local window
local namespace = vim.api.nvim_create_namespace('lsp_info_popup')

local function display(value)
  if value == nil or value == '' then
    return '(none)'
  end
  if type(value) == 'function' then
    return '(function)'
  end
  if type(value) == 'table' then
    local parts = {}
    for _, item in ipairs(value) do
      parts[#parts + 1] = display(item)
    end
    return table.concat(parts, ', ')
  end
  return tostring(value):gsub('\n', '\\n')
end

local function command(cmd)
  if type(cmd) ~= 'table' then
    return display(cmd)
  end
  local parts = {}
  for _, arg in ipairs(cmd) do
    parts[#parts + 1] = arg:find('%s') and vim.fn.shellescape(arg) or arg
  end
  return table.concat(parts, ' ')
end

local function path(value)
  return type(value) == 'string' and vim.fn.fnamemodify(value, ':~') or display(value)
end

local function enabled_configs()
  if vim.lsp.get_configs then
    return vim.lsp.get_configs { enabled = true }
  end
  -- Older 0.12 builds have no public config enumeration API.
  local configs = {}
  for name in pairs(vim.lsp._enabled_configs or {}) do
    local config = vim.lsp.config[name]
    if config then
      configs[#configs + 1] = config
    end
  end
  return configs
end

function M.lines(bufnr)
  local ft = vim.bo[bufnr].filetype
  local attached, other, pending, attached_names = {}, {}, {}, {}
  local name_width = 0
  for _, client in ipairs(vim.lsp.get_clients()) do
    local group = client.attached_buffers[bufnr] and attached or other
    group[#group + 1] = client
    if group == attached then
      attached_names[client.name] = true
    end
    name_width = math.max(name_width, vim.fn.strdisplaywidth(client.name))
  end
  for _, config in ipairs(enabled_configs()) do
    if not attached_names[config.name] and (not config.filetypes or vim.tbl_contains(config.filetypes, ft)) then
      pending[#pending + 1] = config
      name_width = math.max(name_width, vim.fn.strdisplaywidth(config.name))
    end
  end

  local lines, highlights = {}, {}
  local function add(parts)
    local text = ''
    for _, part in ipairs(parts) do
      local start = #text
      text = text .. part[1]
      if part[2] then
        highlights[#highlights + 1] = { row = #lines, start = start, finish = #text, group = part[2] }
      end
    end
    lines[#lines + 1] = text
  end
  local function detail(label, value, group)
    add { { '       ' .. string.format('%-8s', label), 'Comment' }, { value, group or 'String' } }
  end
  local function heading(title, count)
    add { { ' ' .. title .. ':', 'Title' }, { ('  %d'):format(count), 'Comment' } }
  end

  add { { ' File: ', 'Comment' }, { path(vim.api.nvim_buf_get_name(bufnr)), 'Directory' } }
  add { { ' Filetype: ', 'Comment' }, { display(ft), 'Type' } }
  lines[#lines + 1] = ''
  for _, section in ipairs {
    { title = 'Attached', entries = attached, icon = '✓', group = 'DiagnosticOk' },
    { title = 'Other buffers', entries = other, icon = '●', group = 'Special' },
    { title = 'Not attached', entries = pending, icon = '○', group = 'Comment', pending = true },
  } do
    if #section.entries > 0 or section.entries == attached then
      table.sort(section.entries, function(a, b)
        return a.name == b.name and (a.id or 0) < (b.id or 0) or a.name < b.name
      end)
      heading(section.title, #section.entries)
      if #section.entries == 0 then
        add { { '  ○  No clients attached to this buffer', 'Comment' } }
      end
      for _, entry in ipairs(section.entries) do
        local config = section.pending and entry or entry.config
        local status = section.pending and 'enabled' or ('#%d · %s'):format(entry.id, entry.initialized and 'ready' or 'starting')
        local status_hl = 'Comment'
        if section.pending and type(config.cmd) == 'table' and config.cmd[1] and vim.fn.executable(config.cmd[1]) ~= 1 then
          status, status_hl = 'executable not found', 'DiagnosticWarn'
        end
        add {
          { '  ' },
          { section.icon, section.group },
          { '  ' },
          { entry.name, 'Function' },
          { string.rep(' ', name_width - vim.fn.strdisplaywidth(entry.name) + 2) },
          { status, status_hl },
        }
        if not section.pending then
          detail('root', path(entry.root_dir or config.root_dir), 'Directory')
        end
        detail('cmd', command(config.cmd))
        if section.pending and config.root_markers then
          detail('markers', display(config.root_markers), 'Special')
        end
      end
      lines[#lines + 1] = ''
    end
  end
  add { { ' Log: ', 'Comment' }, { path(vim.lsp.log.get_filename()), 'Comment' } }
  lines[#lines + 1] = ''
  add { { ' q / <Esc>: close   ·   :checkhealth vim.lsp', 'Comment' } }
  return lines, highlights, #attached
end

function M.open()
  if window and vim.api.nvim_win_is_valid(window) then
    vim.api.nvim_set_current_win(window)
    return
  end
  local lines, highlights, attached = M.lines(vim.api.nvim_get_current_buf())
  local function layout()
    local width = math.max(1, math.min(math.floor(vim.o.columns * 0.8), vim.o.columns - 2))
    local height = math.max(1, math.min(math.floor(vim.o.lines * 0.8), vim.o.lines - 2))
    return {
      relative = 'editor',
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
    }
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, namespace, hl.row, hl.start, { end_col = hl.finish, hl_group = hl.group })
  end
  window = vim.api.nvim_open_win(
    buf,
    true,
    vim.tbl_extend('force', layout(), {
      style = 'minimal',
      border = 'rounded',
      title = (' LspInfo (%d attached) '):format(attached),
      title_pos = 'center',
      zindex = 100,
    })
  )
  vim.wo[window].winhighlight = 'Normal:Normal,FloatBorder:Special'
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = true
  vim.wo[window].linebreak = true
  vim.wo[window].breakindent = true
  local win = window
  local group = vim.api.nvim_create_augroup('lsp_info_popup', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, layout())
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, key in ipairs { 'q', '<Esc>' } do
    vim.keymap.set('n', key, close, { buffer = buf, silent = true, nowait = true })
  end
end

return M
