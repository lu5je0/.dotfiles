local M = {}

local group = vim.api.nvim_create_augroup('ime-status', { clear = true })

local function switch_to_en()
  if vim.fn.has('mac') == 1 then
    require('lu5je0.misc.im.mac.im').switch_to_en()
  else
    print('switch_to_en error')
  end
end

local focus_gained = true
local function keep_normal_mode_with_abc_im()
  local timer = vim.loop.new_timer()

  timer:start(0, 400, vim.schedule_wrap(function()
    if focus_gained then
      if vim.api.nvim_get_mode().mode == 'n' then
        switch_to_en()
        -- print('switch_to_en when focus_gained')
      end
    end
  end))
  
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    pattern = { '*' },
    callback = function()
      focus_gained = false
    end
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    pattern = { '*' },
    callback = function()
      focus_gained = true
    end
  })
end

M.setup = function()
  if vim.fn.has('mac') == 0 then
    return
  end
  keep_normal_mode_with_abc_im()
end

return M
