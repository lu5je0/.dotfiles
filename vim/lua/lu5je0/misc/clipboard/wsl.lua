local M = {}

local augroup = vim.api.nvim_create_augroup("deferClip", {})

local entries = {
  first = 1,
  last = 1,
}
local active_entry = {}

local function add_entry(entry)
  entries[entries.last] = entry
  entries.last = entries.last + 1
end

local function pop_entry()
  if entries.first < entries.last then
    local entry = entries[entries.first]
    entries[entries.first] = nil
    entries.first = entries.first + 1
    return entry
  end
end

local function sync_from()
  vim.fn.jobstart({ "win32yank.exe", "-o", "--lf" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      -- 避免切换窗口后regtype丢失
      if active_entry ~= nil and #data < 100 and table.concat(data, '\n') == vim.fn.getreg('"') then
        return
      end
      active_entry = { lines = data, regtype = 'v' }
    end,
  })
end

local sync_to
do
  local cur_sync_job
  local function sync_next(entry)
    local chan = vim.fn.jobstart({ "win32yank.exe", "-i" }, {
      on_exit = function(_)
        local next_entry = pop_entry()
        if next_entry then
          sync_next(next_entry)
        else
          cur_sync_job = nil
        end
      end,
    })
    cur_sync_job = chan
    vim.fn.chansend(chan, entry.lines)
    vim.fn.chanclose(chan, "stdin")
  end

  sync_to = function()
    if cur_sync_job then
      return
    else
      local entry = pop_entry()
      if entry then
        sync_next(entry)
      end
    end
  end
end

function M.copy(lines, regtype)
  add_entry({ lines = lines, regtype = regtype })
  active_entry = { lines = lines, regtype = regtype }
  sync_to()
end

function M.get_active()
  return { active_entry.lines, active_entry.regtype }
end

function M.setup()
  vim.o.clipboard = 'unnamed'
  
  local set_fn = function(lines, regtype)
    M.copy(lines, regtype)
  end
  
  local get_fn = function()
    return M.get_active()
  end
  
  vim.g.clipboard = {
    name = 'wsl-clipboard',
    copy = {
      ["+"] = set_fn,
      ['*'] = set_fn
    },
    paste = {
      ["+"] = get_fn,
      ["*"] = get_fn
    }
  }
  
  vim.api.nvim_create_autocmd({ "FocusGained" }, {
    group = augroup,
    callback = sync_from,
  })
  sync_from()
end

return M
