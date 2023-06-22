local M = {}

local group = vim.api.nvim_create_augroup('im-keeper', { clear = true })

local function switch_to_en()
  if M.os == 'mac' then
    require('lu5je0.misc.im.mac.im').switch_to_en()
  elseif M.os == 'win' then
    require('lu5je0.misc.im.win.im').disable_ime()
  end
end

local focus_gained = true
local function keep_normal_mode_with_abc_im(interval)
  local timer = vim.loop.new_timer()

  timer:start(0, interval, vim.schedule_wrap(function()
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

local function switch_normal_mode_on_focus_gained()
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    pattern = { '*' },
    callback = function()
      if vim.api.nvim_get_mode().mode == 'n' then
        switch_to_en()
      end
    end
  })
end

function M.setup(config)
  config = vim.tbl_deep_extend('force', {
    mac = {
      keep = false,
      interval = 1000,
      focus_gained = true,
    },
    win = {
      keep = false,
      interval = 1000,
      focus_gained = true,
    }
  }, config)
  
  if vim.fn.has('mac') == 1 then
    M.os = 'mac'
  elseif vim.fn.has('wsl') == 1 then
    M.os = 'win'
  end
  
  local platform_config = config[M.os]
  if platform_config == nil then
    return
  end
  
  if platform_config.keep then
    keep_normal_mode_with_abc_im(platform_config.interval)
  elseif platform_config.focus_gained then
    switch_normal_mode_on_focus_gained()
  end
end

return M
