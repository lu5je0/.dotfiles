local M = {}

local group = vim.api.nvim_create_augroup('im-keeper', { clear = true })

local function switch_to_en()
  if M.os == 'mac' then
    require('lu5je0.misc.im.mac.im').switch_to_en()
  elseif M.os == 'win' then
    require('lu5je0.misc.im.win.im').disable_ime()
  end
end

local function keep_normal_mode_with_abc_im(interval)
  vim.api.nvim_create_autocmd('CursorHold', {
    group = group,
    callback = function()
      if vim.api.nvim_get_mode().mode == 'n' then
        switch_to_en()
      end
    end,
  })
end

function M.setup(config)
  config = vim.tbl_deep_extend('force', {
    mac = {
      keep = false,
    },
    win = {
      keep = false,
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
  end
end

return M
