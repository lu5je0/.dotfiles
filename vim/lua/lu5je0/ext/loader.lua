local ext_loader_group = vim.api.nvim_create_augroup('ext_loader_group', { clear = true })

local M = {}
M.lazy_load_active_cmd_opts_map = {}

local _all_opts = {}

local function load_ext(opts)
  if not opts.loaded then
    if type(opts.config) == 'function' then
      local t0 = vim.uv.hrtime()
      opts.config()
      opts._load_time_ms = (vim.uv.hrtime() - t0) / 1e6
    end
    opts.loaded = true
  end
end

M.lazy_load = function(opts)
  _all_opts[#_all_opts + 1] = opts
  if opts and opts.keys then
    for _, key in ipairs(opts.keys) do
      for _, mode in ipairs(key.mode) do
        local lhs = key[1]
        vim.keymap.set(mode, lhs, function()
          -- Delete proxy keymaps for all modes of this key
          for _, m in ipairs(key.mode) do
            pcall(vim.keymap.del, m, lhs)
          end
          load_ext(opts)
          vim.defer_fn(function()
            require('lu5je0.core.keys').feedkey(lhs)
          end, opts.keys.defer or 0)
        end)
      end
    end
  end

  if opts and opts.cmd then
    for _, cmd in ipairs(opts.cmd) do
      M.lazy_load_active_cmd_opts_map[cmd] = opts

      vim.api.nvim_create_user_command(cmd, function(event)
        local command = {
          cmd = cmd,
          bang = event.bang or nil,
          mods = event.smods,
          args = event.fargs,
          count = event.count >= 0 and event.range == 0 and event.count or nil,
        }
        if event.range == 1 then
          command.range = { event.line1 }
        elseif event.range == 2 then
          command.range = { event.line1, event.line2 }
        end
        vim.api.nvim_del_user_command(cmd)

        load_ext(opts)

        local info = vim.api.nvim_get_commands({})[cmd] or vim.api.nvim_buf_get_commands(0, {})[cmd]
        command.nargs = info.nargs
        if event.args and event.args ~= "" and info.nargs and info.nargs:find("[1?]") then
          command.args = { event.args }
        end
        vim.cmd(command)
      end, {
        bang = true,
        range = true,
        nargs = "*",
        complete = function(_, line)
          -- Load real command definition before completion so command-specific
          -- completions are available even on first Tab.
          pcall(vim.api.nvim_del_user_command, cmd)
          load_ext(M.lazy_load_active_cmd_opts_map[cmd])

          local info = vim.api.nvim_get_commands({})[cmd] or vim.api.nvim_buf_get_commands(0, {})[cmd]
          if not info then
            return {}
          end

          -- NOTE: return completion from the newly loaded real command.
          return vim.fn.getcompletion(line, "cmdline")
        end,
      })
    end
  end

  if opts and opts.event then
    for _, event in ipairs(opts.event) do
      vim.api.nvim_create_autocmd(event, {
        group = ext_loader_group,
        once = true,
        pattern = { '*' },
        callback = function(_)
          load_ext(opts)
        end
      })
    end
  end
end

local function collect_triggers(opts)
  local parts = {}
  if opts.keys then
    for _, key in ipairs(opts.keys) do
      if type(key[1]) == 'string' then
        parts[#parts + 1] = { text = key[1], type = 'key' }
      end
    end
  end
  if opts.cmd then
    for _, cmd in ipairs(opts.cmd) do
      parts[#parts + 1] = { text = ':' .. cmd, type = 'cmd' }
    end
  end
  if opts.event then
    for _, ev in ipairs(opts.event) do
      parts[#parts + 1] = { text = ev, type = 'event' }
    end
  end
  return parts
end

local NS = vim.api.nvim_create_namespace('ext_loader_popup')

local popup_win = nil
local popup_buf = nil

local function close_popup()
  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
  end
  popup_win = nil
  popup_buf = nil
end

local function show_popup()
  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    close_popup()
    return
  end

  local loaded, pending = {}, {}
  for _, opts in ipairs(_all_opts) do
    local name = opts.name or '(unnamed)'
    local triggers = collect_triggers(opts)
    if opts.loaded then
      loaded[#loaded + 1] = { name = name, ms = opts._load_time_ms or 0, triggers = triggers }
    else
      pending[#pending + 1] = { name = name, triggers = triggers }
    end
  end
  table.sort(loaded, function(a, b) return a.ms > b.ms end)

  local lines = {}
  local highlights = {}

  local name_col_width = 0
  for _, e in ipairs(loaded) do
    name_col_width = math.max(name_col_width, #e.name)
  end
  for _, e in ipairs(pending) do
    name_col_width = math.max(name_col_width, #e.name)
  end
  name_col_width = name_col_width + 2

  local function add_hl(row, col_start, col_end, hl_group)
    highlights[#highlights + 1] = { row = row, col_start = col_start, col_end = col_end, hl = hl_group }
  end

  local function format_trigger_line(prefix_icon, icon_hl, time_str, name, triggers, row)
    local line = '  ' .. prefix_icon .. '  '
    local col = #line

    add_hl(row, 2, 2 + #prefix_icon, icon_hl)

    if time_str then
      line = line .. time_str .. '  '
      add_hl(row, col, col + #time_str, 'Number')
      col = #line
    end

    line = line .. name
    col = #line
    local padding = name_col_width - #name
    line = line .. string.rep(' ', padding)
    col = #line

    for i, t in ipairs(triggers) do
      if i > 1 then
        line = line .. '  '
        col = #line
      end
      line = line .. t.text
      local hl = t.type == 'key' and 'Special' or t.type == 'cmd' and 'Function' or 'Type'
      add_hl(row, col, col + #t.text, hl)
      col = #line
    end

    return line
  end

  -- Loaded section
  if #loaded > 0 then
    lines[#lines + 1] = ' Loaded:'
    add_hl(#lines - 1, 1, 8, 'Title')
    for _, e in ipairs(loaded) do
      local time_str = string.format('%6.2fms', e.ms)
      local line = format_trigger_line('✓', 'DiagnosticOk', time_str, e.name, e.triggers, #lines)
      lines[#lines + 1] = line
    end
  end

  -- Separator
  if #loaded > 0 and #pending > 0 then
    lines[#lines + 1] = ''
  end

  -- Pending section
  if #pending > 0 then
    lines[#lines + 1] = ' Pending:'
    add_hl(#lines - 1, 1, 9, 'Title')
    for _, e in ipairs(pending) do
      local time_pad = '        '
      local line = format_trigger_line('○', 'Comment', time_pad, e.name, e.triggers, #lines)
      lines[#lines + 1] = line
    end
  end

  -- Footer
  lines[#lines + 1] = ''
  local hint = 'q: close'
  local max_width = 0
  for _, l in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(l))
  end
  max_width = math.max(max_width, 30)
  local hint_padding = max_width - #hint
  local footer = string.rep(' ', hint_padding) .. hint
  lines[#lines + 1] = footer
  add_hl(#lines - 1, hint_padding, hint_padding + #hint, 'Comment')

  -- Window dimensions
  local win_width = max_width + 2
  local win_height = #lines
  local columns = vim.o.columns
  local editor_lines = vim.o.lines
  local row = math.max(0, math.floor((editor_lines - win_height) / 2) - 1)
  local col = math.max(0, math.floor((columns - win_width) / 2))

  local title = string.format(' ExtLoader (%d/%d loaded) ', #loaded, #loaded + #pending)

  popup_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[popup_buf].buftype = 'nofile'
  vim.bo[popup_buf].bufhidden = 'wipe'
  vim.bo[popup_buf].swapfile = false

  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.bo[popup_buf].modifiable = false

  popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
    zindex = 100,
  })
  vim.wo[popup_win].winhighlight = 'Normal:Normal,FloatBorder:Special'
  vim.wo[popup_win].cursorline = false

  vim.api.nvim_buf_clear_namespace(popup_buf, NS, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(popup_buf, NS, hl.hl, hl.row, hl.col_start, hl.col_end)
  end

  local opts = { buffer = popup_buf, nowait = true }
  vim.keymap.set('n', 'q', close_popup, opts)
  vim.keymap.set('n', '<esc>', close_popup, opts)
end

vim.api.nvim_create_user_command('ExtLoader', show_popup, {})

return M
