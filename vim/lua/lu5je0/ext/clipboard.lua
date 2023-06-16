local M = {}

local GROUP_NAME = 'clipboard_event_group'
local STD_PATH = vim.fn.stdpath('config')

local has = function(feature)
  return vim.fn.has(feature) == 1
end

local function set_g_clipboard()
  if has('wsl') then
    vim.g.clipboard = {
      name = 'win32yank',
      copy = {
        ['+'] = { 'win32yank.exe', '-i', '--crlf' },
        ['*'] = { 'win32yank.exe', '-i', '--crlf' },
      },
      paste = {
        ['+'] = { 'win32yank.exe', '-o', '--lf' },
        ['*'] = { 'win32yank.exe', '-o', '--lf' },
      },
      cache_enabled = 1,
    }
  elseif has('mac') then
    vim.cmd[[
    function s:get_active()
      return luaeval('require("lu5je0.ext.clipboard").read_clipboard_ffi()')
    endfunction
    let g:clipboard = {
          \   'name': 'pbcopy',
          \   'copy': {
          \      '+': 'pbcopy',
          \      '*': 'pbcopy',
          \    },
          \   'paste': {
          \      '+': {-> s:get_active()},
          \      '*': {-> s:get_active()},
          \   },
          \   'cache_enabled': 1,
          \ }
    ]]
  end
end

local ffi = require('ffi')
local lib_clipboard = ffi.load(STD_PATH .. '/lib/liblibclipboard.dylib')
ffi.cdef([[
const char* get_contents();
]])

function M.read_clipboard_ffi()
  return string.split(ffi.string(lib_clipboard.get_contents()), '\n')
end

function M.read_clipboard()
  if vim.g.clipboard and vim.g.clipboard.paste then
    local cmd = ''
    for _, v in ipairs(vim.g.clipboard.paste['*']) do
      cmd = cmd .. v .. ' '
    end
    local ok, r = pcall(io.popen, cmd .. ' 2>/dev/null')
    if ok and r then
      vim.fn.setreg('"', r:read("*a"))
    else
      print('read clipboard fail', r)
    end
  end
end

local last_write = nil
function M.write_to_clipboard()
  if last_write and last_write == vim.fn.getreg('"') then
    return
  end
      
  ---@diagnostic disable-next-line: missing-parameter
  local reg_content = vim.fn.getreg('"')
  vim.fn.setreg('*', reg_content)
  last_write = reg_content
end

local function create_defer_autocmd()
  local group = vim.api.nvim_create_augroup(GROUP_NAME, { clear = true })

  vim.api.nvim_create_autocmd({ 'FocusGained', 'VimEnter' }, {
    group = group,
    pattern = { '*' },
    callback = function()
      M.read_clipboard()
    end
  })
  
  -- telescope
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { 'TelescopePrompt' },
    callback = function()
      if vim.fn.has('wsl') == 1 or vim.fn.has('mac') == 1 then
        M.write_to_clipboard()
      end
    end
  })

  vim.api.nvim_create_autocmd({ 'FocusLost', 'CmdlineEnter', 'QuitPre' }, {
    group = group,
    pattern = { '*' },
    callback = function(args)
      if vim.bo.buftype == 'terminal' then
        if vim.api.nvim_get_mode().mode ~= 'nt' then
          return
        end
      end
      
      vim.defer_fn(function()
        M.write_to_clipboard()
      end, 0)
    end
  })
end

local function clear_defer_autocmd()
  vim.api.nvim_create_augroup(GROUP_NAME, { clear = true })
end

local function create_defer_toggle_command()
  local autocmd_created = true
  vim.api.nvim_create_user_command('ClipboardAutocmdToggle', function()
    if autocmd_created then
      vim.o.clipboard = 'unnamedplus'
      clear_defer_autocmd()
      print('The clipboard autocmd has cleared')
    else
      vim.o.clipboard = ''
      create_defer_autocmd()
      print('The clipboard autocmd has started')
    end
    autocmd_created = not autocmd_created
  end, { force = true })
end

M.setup = function()
  set_g_clipboard()
  if not has('clipboard') then
    return
  end

  if os.getenv('TERMINAL_EMULATOR') == 'JetBrains-JediTerm' then
    vim.o.clipboard = 'unnamedplus'
    return
  end

  if has('wsl') then
    -- 默认启用
    create_defer_autocmd()

    -- 创建toggle命令
    create_defer_toggle_command()
  else
    vim.o.clipboard = 'unnamedplus'
  end
end

return M
