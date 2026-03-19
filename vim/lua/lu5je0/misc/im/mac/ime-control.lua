local M = {}

local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'
local native = require('lu5je0.core.native')

local STATUS = {
  last_ime = ABC_IM_SOURCE_CODE
}

local state = {
  bridge = nil,
  subscribed = false,
}

function M.get_im_switcher()
  if M.im_switcher ~= nil then
    return M.im_switcher
  end
  M.im_switcher = (function()
    local ffi = require('ffi')
    local xkb_switch_lib = ffi.load(native.resolve_path({
      filename = 'XkbSwitchLib.lib',
      platform = 'macos',
      kind = 'lib',
    }))
    ffi.cdef([[
    const char* Xkb_Switch_getXkbLayout();
    void Xkb_Switch_setXkbLayout(const char *s);
    ]])

    return {
      switch_to_ime = function(im_code)
        if im_code == nil then
          return
        end
        ---@diagnostic disable-next-line: undefined-field
        pcall(xkb_switch_lib.Xkb_Switch_setXkbLayout, im_code)
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
    M.get_im_switcher().switch_to_ime(STATUS.last_ime)
  end
end

M.normal = function()
  local active_ime = M.get_im_switcher().get_ime()
  STATUS.last_ime = active_ime
  if active_ime == ABC_IM_SOURCE_CODE then
    return
  end
  M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
end

local function ensure_bridge(opts)
  if state.bridge then
    return state.bridge
  end
  state.bridge = require('lu5je0.misc.tui-bridge.ext.im').setup(opts or {})
  return state.bridge
end

function M.keeper(enable)
  ensure_bridge().watch(enable == true)
end

function M.on_change(handler)
  local bridge = ensure_bridge()
  if not state.subscribed then
    state.subscribed = true
  end
  bridge.on_change(handler)
end

function M.should_normalize(args)
  return args.source_id ~= ABC_IM_SOURCE_CODE
end

M.setup = function(opts)
  ensure_bridge(opts)
  M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
  return M
end

return M
