local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'

local std_path = vim.fn.stdpath('config')
local group = vim.api.nvim_create_augroup('ime-status', { clear = true })
local rate_limiter = require('lu5je0.lang.ratelimiter'):create(7, 0.5)

local M = {
  last_ime = ABC_IM_SOURCE_CODE
}

M.get_im_switcher = function()
  if M.im_switcher ~= nil then
    return M.im_switcher
  end
  M.im_switcher = (function()
    local ffi = require('ffi')
    local xkb_switch_lib = ffi.load(std_path .. '/lib/XkbSwitchLib.lib')
    ffi.cdef([[
    const char* Xkb_Switch_getXkbLayout();
    void Xkb_Switch_setXkbLayout(const char *s);
    ]])

    -- local macism = ffi.load(std_path .. '/lib/libmacism.dylib')
    -- ffi.cdef([[
    -- void switch_ime(const char *ime);
    -- ]])

    return {
      switch_to_ime = function(im_code)
        if im_code == nil then
          return
        end
        ---@diagnostic disable-next-line: undefined-field
        pcall(xkb_switch_lib.Xkb_Switch_setXkbLayout, im_code)
      end,
      -- switch_to_ime_macism_dylib = function(im_code)
      --   macism.switch_ime(im_code)
      -- end,
      switch_to_ime_macism_executed_file = function(im_code)
        vim.loop.new_thread(function(path, ime)
          io.popen(('%s %s 3000 2>/dev/null'):format(path, ime)):close()
        end, std_path .. '/lib/macism', im_code)
      end,
      get_ime = function()
        ---@diagnostic disable-next-line: undefined-field
        local ok, ime = pcall(xkb_switch_lib.Xkb_Switch_getXkbLayout)
        if ok then
          return ffi.string(ime)
        end
        return ABC_IM_SOURCE_CODE
      end
    }
  end)()
  return M.im_switcher
end

M.switch_to_en = function()
  if M.get_im_switcher().get_ime() ~= ABC_IM_SOURCE_CODE then
    M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
  end
end

M.toggle_save_last_ime = function()
  local keeper = require('lu5je0.misc.env-keeper')
  local v = keeper.get('save_last_ime', true)
  if v then
    print("keep last ime disabled")
  else
    print("keep last ime enabled")
  end
  M.save_last_ime = not v
  keeper.set('save_last_ime', M.save_last_ime)
end

M.switch_insert_mode = rate_limiter:wrap(function()
  if M.save_last_ime and M.last_ime ~= ABC_IM_SOURCE_CODE then
    M.get_im_switcher().switch_to_ime(M.last_ime)
    -- M.get_im_switcher().switch_to_ime_macism_executed_file(M.last_ime)
  end
end)

M.switch_normal_mode = rate_limiter:wrap(function()
  if M.save_last_ime then
    M.last_ime = M.get_im_switcher().get_ime()
  end
  M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
end)

M.setup = function()
  M.save_last_ime = require('lu5je0.misc.env-keeper').get('save_last_ime', true)

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.switch_normal_mode()
    end
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.switch_normal_mode()
    end
  })

  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = { '*' },
    callback = function()
      M.switch_insert_mode()
    end
  })

  vim.keymap.set('n', '<leader>vi', M.toggle_save_last_ime)
end

return M
