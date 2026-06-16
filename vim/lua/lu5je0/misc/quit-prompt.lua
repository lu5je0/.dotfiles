local M = {}

local devicons = require('nvim-web-devicons')
local cursor_utils = require('lu5je0.core.cursor')
local keys = require('lu5je0.core.keys')

local function keymap(mode, lhs, rhs, opts)
  if type(lhs) == 'table' then
    for _, v in ipairs(lhs) do
      vim.keymap.set(mode, v, rhs, opts)
    end
  else
    vim.keymap.set(mode, lhs, rhs, opts)
  end
end

local function get_extension(filename)
  return filename:match('.+%.(%w+)$')
end

local function text_align_center(text, width)
  return string.rep(' ', math.floor((width - #text) / 2)) .. text
end

local function build_unsaved_info()
  local filenames = {}
  local name_map = require('lu5je0.ext.winbar.state').buffer_name_map
  for _, buf in ipairs(vim.fn.getbufinfo({ bufloaded = 1, buflisted = 1 })) do
    if buf.changed == 1 then
      local name = vim.fn.fnamemodify(buf.name, ':t')
      if name == '' then
        local n = name_map[buf.bufnr]
        name = n and ('[Untitled-' .. n .. ']') or '[Untitled]'
      end
      table.insert(filenames, name)
    end
  end
  return filenames
end

local function create_popup(title, filenames, choice)
  local file_lines = {}
  local icon_highlights = {}
  local width = 55
  for _, filename in ipairs(filenames) do
    local icon, hl = devicons.get_icon(filename, get_extension(filename), { default = true })
    local line = ' ' .. (icon or '') .. ' ' .. filename
    table.insert(file_lines, line)
    table.insert(icon_highlights, hl or 'Normal')
  end

  local height = 2 + #filenames

  cursor_utils.cursor_visible(false)
  vim.cmd('redraw')

  local buf = vim.api.nvim_create_buf(false, true)

  local row = math.floor((vim.o.lines - height) / 2) - 3
  local col = math.floor((vim.o.columns - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
    zindex = 100,
  })
  vim.api.nvim_set_option_value('winhighlight', 'Normal:Normal,FloatBorder:Normal', { win = win })
  vim.fn.win_execute(win, 'set ft=confirm')

  -- content
  local lines = { text_align_center(title, width) }
  for _, line in ipairs(file_lines) do
    table.insert(lines, line)
  end
  table.insert(lines, text_align_center(choice, width))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- highlights
  local ns = vim.api.nvim_create_namespace('quit_prompt')
  vim.hl.range(buf, ns, #filenames == 0 and 'Green' or 'Red', { 0, 0 }, { 0, -1 })
  for i, hl in ipairs(icon_highlights) do
    vim.hl.range(buf, ns, hl, { i, 1 }, { i, 5 })
  end

  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

  -- close logic
  local function close()
    cursor_utils.cursor_visible(true)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local opts = { noremap = true, nowait = true, buffer = buf }
  keymap('n', { '<esc>', 'q', '<c-c>', '<cr>', 'n' }, close, opts)
  keymap('n', { 'i', 'o', 'v', 'V', '<leader>Q' }, '<nop>', opts)
  keymap('n', { 'Y', 'y' }, function()
    close()
    vim.cmd('qa!')
  end, opts)
  keymap('n', 's', function()
    close()
    vim.cmd('wqa!')
  end, opts)

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = close,
  })
end

function M.exit_vim_with_dialog()
  local filenames = build_unsaved_info()
  if #filenames > 0 then
    create_popup('The change of the following buffers will be discarded.', filenames, '[N]o, (Y)es, (S)ave ALl')
  else
    create_popup('Exit vim?', {}, '[N]o, (Y)es')
  end
end

function M.close_buffer()
  local valid_buffers = require('lu5je0.core.buffers').valid_buffers()
  local cur_buf_nr = vim.api.nvim_get_current_buf()
  local cur_win = vim.api.nvim_get_current_win()

  local txt_window_cnt = 0
  for _, v in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.tbl_contains(valid_buffers, vim.api.nvim_win_get_buf(v)) then
      txt_window_cnt = txt_window_cnt + 1
    end
  end

  if txt_window_cnt ~= 0 and not vim.tbl_contains(valid_buffers, cur_buf_nr) then
    vim.cmd('q')
    return
  end

  local function confirm_discard(bufnr)
    if not vim.bo[bufnr].modified then return true end
    return vim.fn.confirm('Close without saving?', '&No\n&Yes') == 2
  end

  local winbar_state = require('lu5je0.ext.winbar.state')
  local win_bufs = winbar_state.win_bufs[cur_win]

  if win_bufs then
    local filtered = {}
    local cur_idx
    for _, b in ipairs(win_bufs) do
      if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
        filtered[#filtered + 1] = b
        if b == cur_buf_nr then
          cur_idx = #filtered
        end
      end
    end

    if cur_idx and #filtered > 1 then
      local prev_buf
      if cur_idx < #filtered then
        prev_buf = filtered[cur_idx + 1]
      else
        prev_buf = filtered[cur_idx - 1]
      end

      -- check if this buffer is owned by other windows before deciding to confirm
      local buf_in_other_win = false
      for w, bufs in pairs(winbar_state.win_bufs) do
        if w ~= cur_win and vim.api.nvim_win_is_valid(w) then
          for _, b in ipairs(bufs) do
            if b == cur_buf_nr then
              buf_in_other_win = true
              break
            end
          end
          if buf_in_other_win then break end
        end
      end

      if not buf_in_other_win and not confirm_discard(cur_buf_nr) then
        return
      end

      -- remove from current window's list
      local new_list = {}
      for _, b in ipairs(win_bufs) do
        if b ~= cur_buf_nr then
          new_list[#new_list + 1] = b
        end
      end
      winbar_state.win_bufs[cur_win] = new_list

      vim.api.nvim_set_current_buf(prev_buf)

      if not buf_in_other_win then
        vim.cmd('silent! bd! ' .. cur_buf_nr)
      end
      return
    elseif cur_idx and #filtered == 1 then
      if txt_window_cnt > 1 then
        local buf_in_other_win = false
        for w, bufs in pairs(winbar_state.win_bufs) do
          if w ~= cur_win and vim.api.nvim_win_is_valid(w) then
            for _, b in ipairs(bufs) do
              if b == cur_buf_nr then
                buf_in_other_win = true
                break
              end
            end
            if buf_in_other_win then break end
          end
        end

        if not buf_in_other_win and not confirm_discard(cur_buf_nr) then
          return
        end

        winbar_state.win_bufs[cur_win] = nil
        vim.cmd('q')
        keys.feedkey('<c-w>p')

        if not buf_in_other_win then
          vim.cmd('silent! bd! ' .. cur_buf_nr)
        end
        return
      end

      if #vim.api.nvim_list_tabpages() > 1 then
        if not confirm_discard(cur_buf_nr) then return end
        winbar_state.win_bufs[cur_win] = nil
        vim.cmd('q')
        return
      end

      -- single window, single tab: find another valid buf to switch to
      local alt_buf
      for _, b in ipairs(valid_buffers) do
        if b ~= cur_buf_nr then
          alt_buf = b
          break
        end
      end
      if alt_buf then
        if not confirm_discard(cur_buf_nr) then
          return
        end

        winbar_state.win_bufs[cur_win] = { alt_buf }
        vim.api.nvim_set_current_buf(alt_buf)
        vim.cmd('silent! bd! ' .. cur_buf_nr)
        return
      end
    end
  end

  if txt_window_cnt > 1 then
    vim.cmd('q')
    keys.feedkey('<c-w>p')
  else
    if not confirm_discard(cur_buf_nr) then return end
    if #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd('q')
    else
      vim.cmd('bp')
      vim.cmd('silent! bd! ' .. cur_buf_nr)
    end
  end
end

function M.setup()
  vim.keymap.set('n', '<leader>q', M.close_buffer, { silent = true })
  vim.keymap.set('n', '<leader>Q', M.exit_vim_with_dialog, { silent = true })
end

return M
