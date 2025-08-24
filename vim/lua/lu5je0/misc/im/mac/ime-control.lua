local M = {}

local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'

local STD_PATH = vim.fn.stdpath('config')

local STATUS = {
  last_ime = ABC_IM_SOURCE_CODE
}

local function get_im_switcher()
  if M.im_switcher ~= nil then
    return M.im_switcher
  end
  M.im_switcher = (function()
    local ffi = require('ffi')
    local xkb_switch_lib = ffi.load(STD_PATH .. '/lib/XkbSwitchLib.lib')
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
        vim.uv.new_thread(function(path, ime)
          io.popen(('%s %s 3000 2>/dev/null'):format(path, ime)):close()
        end, STD_PATH .. '/lib/macism', im_code)
      end,
      -- avg: 0.0035ms
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

M.insert = function()
  if STATUS.last_ime ~= ABC_IM_SOURCE_CODE then
    get_im_switcher().switch_to_ime(M.last_ime)
    -- get_im_switcher().switch_to_ime_macism_executed_file(M.last_ime)
  end
end

M.normal = function()
  local active_ime = M.get_im_switcher().get_ime()
  STATUS.last_ime = active_ime
  if active_ime == ABC_IM_SOURCE_CODE then
    return
  end
  get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
end

return M
