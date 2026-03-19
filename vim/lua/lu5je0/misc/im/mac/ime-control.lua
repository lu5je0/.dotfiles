local M = {}

local ABC_IM_SOURCE_CODE = 'com.apple.keylayout.ABC'

local STD_PATH = vim.fn.stdpath('config')

local STATUS = {
  last_ime = ABC_IM_SOURCE_CODE
}

function M.get_im_switcher()
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

local function enable_keeper()
  -- true: focused + normal mode, keeper should enforce ABC
  vim.g._ime_keeper_active = true
  local group = vim.api.nvim_create_augroup('ime-control-focus', { clear = true })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    callback = function()
      vim.g._ime_keeper_active = true
    end
  })
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    callback = function()
      vim.g._ime_keeper_active = false
    end
  })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      if vim.fn.mode() ~= 'i' then
        vim.g._ime_keeper_active = true
        M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
      end
    end
  })
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function()
      vim.g._ime_keeper_active = false
    end
  })

  -- event-driven: subprocess listens for CF notification, stdout piped to neovim
  local stdout = vim.uv.new_pipe(false)
  local handle, pid = vim.uv.spawn(STD_PATH .. '/lib/ime_watcher_mac', {
    stdio = { nil, stdout, nil },
  }, function()
    stdout:close()
  end)

  local buf = ''
  stdout:read_start(function(err, data)
    if err or not data then return end
    buf = buf .. data
    while true do
      local nl = buf:find('\n')
      if not nl then break end
      local ime = buf:sub(1, nl - 1)
      buf = buf:sub(nl + 1)
      if vim.g._ime_keeper_active and ime ~= ABC_IM_SOURCE_CODE then
        M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
      end
    end
  end)
end

M.setup = function()
  enable_keeper()
  M.get_im_switcher().switch_to_ime(ABC_IM_SOURCE_CODE)
  return M
end

return M
