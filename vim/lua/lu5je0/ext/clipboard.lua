local M = {}

local GROUP_NAME = 'clipboard_event_group'

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

local function create_autocmd()
  local group = vim.api.nvim_create_augroup(GROUP_NAME, { clear = true })

  vim.api.nvim_create_autocmd({ 'FocusGained' }, {
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

local function clear_autocmd()
  vim.api.nvim_create_augroup(GROUP_NAME, { clear = true })
end

local function create_user_command()
  local autocmd_created = true
  vim.api.nvim_create_user_command('ClipboardAutocmdToggle', function()
    if autocmd_created then
      vim.o.clipboard = 'unnamedplus'
      clear_autocmd()
      print('The clipboard autocmd has cleared')
    else
      vim.o.clipboard = ''
      create_autocmd()
      print('The clipboard autocmd has started')
    end
    autocmd_created = not autocmd_created
  end, { force = true })
end

M.setup = function()
  if vim.fn.has('clipboard') == 0 then
    return
  end
  
  if os.getenv('TERMINAL_EMULATOR') == 'JetBrains-JediTerm' then
    vim.o.clipboard = 'unnamedplus'
    return
  end
  
  vim.defer_fn(M.read_clipboard, 10)

  -- 默认启用
  create_autocmd()
  
  -- 创建toggle命令
  create_user_command()
end

return M
