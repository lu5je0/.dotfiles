local visual = require('lu5je0.core.visual')
local content = require('lu5je0.misc.translator.content')
local wd = require('lu5je0.misc.translator.wd')
local window = require('lu5je0.misc.translator.window')

local M = {}

local state = {
  win = nil,
  buf = nil,
  close_group = nil,
  source_win = nil,
  request_id = 0,
  opts = {},
  history = {},
  history_index = 0,
  popup_fixed_size = nil,
}

local function reset_history()
  state.history = {}
  state.history_index = 0
  state.popup_fixed_size = nil
end

local function get_float_cursor()
  if not window.has_float(state) or vim.api.nvim_get_current_win() ~= state.win then
    return nil
  end
  return vim.api.nvim_win_get_cursor(state.win)
end

local function clamp_cursor(lines, cursor)
  if not cursor then
    return nil
  end
  local row = math.max(1, math.min(cursor[1], #lines))
  local col_max = math.max(0, vim.fn.strchars(lines[row] or ''))
  local col = math.max(0, math.min(cursor[2], col_max))
  return { row, col }
end

local function save_current_history_cursor()
  local item = state.history[state.history_index]
  local cursor = get_float_cursor()
  if not item or not cursor then
    return
  end
  item.cursor = clamp_cursor(item.lines, cursor)
end

local function push_history(entry)
  if state.history_index < #state.history then
    for i = #state.history, state.history_index + 1, -1 do
      table.remove(state.history, i)
    end
  end
  table.insert(state.history, entry)
  state.history_index = #state.history
end

local function render_history(index)
  local item = state.history[index]
  if not item then
    return false
  end
  save_current_history_cursor()
  state.history_index = index
  window.render(state, item.lines, item.hls, {
    keep_position = true,
    width = state.popup_fixed_size and state.popup_fixed_size.width or nil,
    height = state.popup_fixed_size and state.popup_fixed_size.height or nil,
  })
  if window.has_float(state) and item.cursor then
    pcall(vim.api.nvim_win_set_cursor, state.win, clamp_cursor(item.lines, item.cursor))
  end
  return true
end

local function history_back()
  if state.history_index <= 1 then
    return
  end
  state.request_id = state.request_id + 1
  render_history(state.history_index - 1)
end

local function history_forward()
  if state.history_index >= #state.history then
    return
  end
  state.request_id = state.request_id + 1
  render_history(state.history_index + 1)
end

local function translate_async(query, render_opts)
  if query == nil or query == '' then
    return
  end

  render_opts = render_opts or {}

  if not window.has_float(state) then
    reset_history()
    window.set_anchor(state)
  end

  local req_id = state.request_id + 1
  state.request_id = req_id
  local cursor_before = nil
  if render_opts.cursor_to_start then
    save_current_history_cursor()
  end
  if render_opts.preserve_cursor then
    save_current_history_cursor()
    cursor_before = get_float_cursor()
  end

  local loading_render_opts = {
    auto_width = true,
  }
  if render_opts.keep_loading_size and window.has_float(state) then
    loading_render_opts.auto_width = false
    loading_render_opts.width = vim.api.nvim_win_get_width(state.win)
    loading_render_opts.height = vim.api.nvim_win_get_height(state.win)
  end
  if render_opts.keep_position then
    loading_render_opts.keep_position = true
  end
  if render_opts.fixed_size then
    loading_render_opts.auto_width = false
    loading_render_opts.width = render_opts.fixed_size.width
    loading_render_opts.height = render_opts.fixed_size.height
  end

  if render_opts.show_loading ~= false then
    window.render(state, { 'loading...' }, {
      { row = 0, col_start = 0, col_end = -1, hl = 'Comment' }
    }, loading_render_opts)
    if render_opts.cursor_to_start and window.has_float(state) then
      pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
    end
  end

  wd.query_async(query, function(result, err)
    if req_id ~= state.request_id or not window.has_float(state) then
      return
    end

    if err then
      vim.notify(err, vim.log.levels.ERROR)
      window.close(state)
      return
    end

    local lines, hls = content.build_display_lines(result)
    window.render(state, lines, hls, {
      keep_position = render_opts.keep_position == true,
      width = render_opts.fixed_size and render_opts.fixed_size.width or nil,
      height = render_opts.fixed_size and render_opts.fixed_size.height or nil,
    })
    local final_cursor = nil
    if render_opts.cursor_to_start then
      final_cursor = { 1, 0 }
      pcall(vim.api.nvim_win_set_cursor, state.win, final_cursor)
    elseif render_opts.preserve_cursor and cursor_before then
      final_cursor = clamp_cursor(lines, cursor_before)
      pcall(vim.api.nvim_win_set_cursor, state.win, final_cursor)
    end
    push_history({
      query = query,
      lines = lines,
      hls = hls,
      cursor = final_cursor or clamp_cursor(lines, get_float_cursor() or { 1, 0 }),
    })
  end)
end

local function replace_cword(text)
  vim.cmd('normal! viw')
  visual.visual_replace(text)
end

local function translate_word()
  if window.has_float(state) and vim.api.nvim_get_current_win() ~= state.win then
    window.focus(state)
    return
  end
  if not wd.ensure_exists() then
    return
  end
  translate_async(vim.fn.expand('<cword>'))
end

local function translate_visual()
  if window.has_float(state) and vim.api.nvim_get_current_win() ~= state.win then
    window.focus(state)
    return
  end
  if not wd.ensure_exists() then
    return
  end
  translate_async(visual.get_visual_selection_as_string())
end

local function translate_replace_word()
  if not wd.ensure_exists() then
    return
  end

  local result, err = wd.query_sync(vim.fn.expand('<cword>'))
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local text = content.first_meaning(result)
  if text and text ~= '' then
    replace_cword(text)
  end
end

local function translate_replace_visual()
  if not wd.ensure_exists() then
    return
  end

  local result, err = wd.query_sync(visual.get_visual_selection_as_string())
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local text = content.first_meaning(result)
  if text and text ~= '' then
    visual.visual_replace(text)
  end
end

--- Setup translator keymaps and popup behavior.
--- @param opts? { width?: number } Popup width configuration.
--- `width` accepts:
--- - integer > 0: fixed width in columns
--- - number between 0 and 1: percentage of current editor columns
--- Invalid or missing values fallback to default width `40`.
function M.setup(opts)
  state.opts = opts or {}
  state.on_popup_translate_word = function()
    if not wd.ensure_exists() then
      return
    end
    if window.has_float(state) and not state.popup_fixed_size then
      state.popup_fixed_size = {
        width = vim.api.nvim_win_get_width(state.win),
        height = vim.api.nvim_win_get_height(state.win),
      }
    end
    translate_async(vim.fn.expand('<cword>'), {
      keep_loading_size = true,
      keep_position = true,
      cursor_to_start = true,
      fixed_size = state.popup_fixed_size,
      show_loading = true,
    })
  end
  state.on_popup_history_back = history_back
  state.on_popup_history_forward = history_forward
  state.on_close = reset_history

  vim.keymap.set('n', '<leader>ww', translate_word, { desc = 'translate cword' })
  vim.keymap.set('x', '<leader>ww', translate_visual, { desc = 'translate selected' })
  vim.keymap.set('n', '<leader>wr', translate_replace_word, { desc = 'translate cword and replace' })
  vim.keymap.set('x', '<leader>wr', translate_replace_visual, { desc = 'translate and replace' })
end

return M
