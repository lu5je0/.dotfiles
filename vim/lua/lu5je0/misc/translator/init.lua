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
}

local function translate_async(query)
  window.close(state)
  window.set_anchor(state)

  local req_id = state.request_id + 1
  state.request_id = req_id

  window.render(state, { 'loading...' }, {
    { row = 0, col_start = 0, col_end = -1, hl = 'Comment' }
  }, {
    auto_width = true,
  })

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
    window.render(state, lines, hls)
  end)
end

local function replace_cword(text)
  vim.cmd('normal! viw')
  visual.visual_replace(text)
end

local function translate_word()
  if window.focus(state) then
    return
  end
  if not wd.ensure_exists() then
    return
  end
  translate_async(vim.fn.expand('<cword>'))
end

local function translate_visual()
  if window.focus(state) then
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
  vim.keymap.set('n', '<leader>ww', translate_word, { desc = 'translate cword' })
  vim.keymap.set('x', '<leader>ww', translate_visual, { desc = 'translate selected' })
  vim.keymap.set('n', '<leader>wr', translate_replace_word, { desc = 'translate cword and replace' })
  vim.keymap.set('x', '<leader>wr', translate_replace_visual, { desc = 'translate and replace' })
end

return M
