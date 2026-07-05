-- Winbar render profiler: identify hot spots
-- Usage: cd vim && nvim --headless -u NONE -l tests/winbar/profile.lua

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/../../'
vim.opt.rtp:prepend(root)

package.loaded['nvim-web-devicons'] = {
  get_icon = function(name, ext, _opts)
    return '', 'DevIconLua'
  end,
}

local highlights = require('lu5je0.ext.winbar.highlights')
local state = require('lu5je0.ext.winbar.state')
local render = require('lu5je0.ext.winbar.render')

highlights.apply()

local filenames = {
  'lua/lu5je0/ext/winbar/render.lua',
  'lua/lu5je0/ext/sidebar/window.lua',
  'lua/lu5je0/misc/quit-prompt.lua',
  'lua/lu5je0/ext/winbar/config.lua',
  'lua/lu5je0/ext/winbar/state.lua',
  'lua/lu5je0/ext/winbar/init.lua',
  'lua/lu5je0/core/buffers.lua',
  'package.json',
  'README.md',
  'tests/sidebar/helpers.lua',
  'lua/lu5je0/ext/sidebar/sources/files/init.lua',
  'lua/lu5je0/ext/sidebar/sources/git_changes/parser.lua',
  'tsconfig.json',
  'src/components/App.tsx',
  'src/utils/format.ts',
}

local bufs = {}
for i, name in ipairs(filenames) do
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. '/' .. name)
  bufs[i] = buf
end

local win = vim.api.nvim_get_current_win()
state.win_bufs[win] = bufs
state.focused_win = win
vim.api.nvim_set_current_buf(bufs[5])

local orig_get_width = vim.api.nvim_win_get_width
vim.api.nvim_win_get_width = function(_w) return 120 end

-- warmup
for _ = 1, 20 do render.build_winbar(win) end

-- profile individual API calls
local N = 1000
local timers = {}

local function time_section(label, fn)
  local s = vim.uv.hrtime()
  for _ = 1, N do fn() end
  timers[#timers + 1] = { label = label, ns = vim.uv.hrtime() - s }
end

-- 1. valid_buffers
time_section('valid_buffers()', function()
  require('lu5je0.core.buffers').valid_buffers()
end)

-- 2. tabpage_list_wins
time_section('tabpage_list_wins', function()
  vim.api.nvim_tabpage_list_wins(0)
end)

-- 3. win_get_config per win
local wins = vim.api.nvim_tabpage_list_wins(0)
time_section('win_get_config (per win)', function()
  for _, w in ipairs(wins) do
    vim.api.nvim_win_get_config(w)
  end
end)

-- 4. buf_get_name (x15)
time_section('buf_get_name x15', function()
  for _, b in ipairs(bufs) do
    vim.api.nvim_buf_get_name(b)
  end
end)

-- 5. vim.bo[buf].modified x15
time_section('vim.bo[buf].modified x15', function()
  for _, b in ipairs(bufs) do
    local _ = vim.bo[b].modified
  end
end)

-- 6. nvim_strwidth x15
time_section('strwidth x15', function()
  for i = 1, 15 do
    vim.api.nvim_strwidth('render.lua')
  end
end)

-- 7. vim.fn.getcwd
time_section('vim.fn.getcwd()', function()
  vim.fn.getcwd()
end)

-- 8. full build_winbar
time_section('build_winbar (full)', function()
  render.build_winbar(win)
end)

vim.api.nvim_win_get_width = orig_get_width

print(string.format('\nProfile results (%d iterations)\n', N))
print(string.format('%-30s %10s %10s', 'Section', 'Total(ms)', 'Avg(µs)'))
print(string.rep('-', 55))
for _, t in ipairs(timers) do
  print(string.format('%-30s %10.2f %10.2f', t.label, t.ns/1e6, t.ns/N/1e3))
end

vim.cmd('qa!')
