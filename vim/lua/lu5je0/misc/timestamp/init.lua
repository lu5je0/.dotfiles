local visual_core_api = require('lu5je0.core.visual')
local utils = require('lu5je0.misc.timestamp.utils')
local modify = require('lu5je0.misc.timestamp.modify')
local show = require('lu5je0.misc.timestamp.show')
local replace_all = require('lu5je0.misc.timestamp.replace_all')

local M = {}
local did_setup = false

local function get_timestamp()
  if vim.api.nvim_get_mode().mode == 'v' then
    return visual_core_api.get_visual_selection_as_string()
  end
  return vim.fn.expand('<cword>')
end

function M.show_in_date()
  print(utils.parse(get_timestamp()))
end

M.modify_timestamp = modify.modify_timestamp
M.toggle_timestamp_show = show.toggle_timestamp_show
M.replace_all_timestamp = replace_all.replace_all_timestamp

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  vim.api.nvim_create_user_command('TimestampModify', function()
    M.modify_timestamp()
  end, { nargs = 0, desc = '转换并编辑光标下的Unix时间戳' })

  vim.api.nvim_create_user_command('TimestampShow', function()
    M.toggle_timestamp_show()
  end, { nargs = 0, desc = '切换显示时间戳对应的日期文本' })

  vim.api.nvim_create_user_command('TimestampReplaceAll', function(opts)
    M.replace_all_timestamp(opts.fargs[1] or '')
  end, { nargs = '?', desc = '将 buffer 中时间戳替换为日期时间' })

  vim.keymap.set('n', '<Plug>(TimestampModify)', function()
    M.modify_timestamp()
  end, { silent = true })
end

return M
