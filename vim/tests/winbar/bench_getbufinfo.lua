-- Isolated benchmark: only getbufinfo optimization vs original
-- Usage: cd vim && nvim --headless -u NONE -l tests/winbar/bench_getbufinfo.lua

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
  if i == 3 then vim.bo[buf].modified = true end
end

local win = vim.api.nvim_get_current_win()
state.win_bufs[win] = bufs
state.focused_win = win
vim.api.nvim_set_current_buf(bufs[5])

local orig_get_width = vim.api.nvim_win_get_width
vim.api.nvim_win_get_width = function(_w) return 120 end

-- Approach A: original (vim.bo per buf)
local function valid_buffers_original()
  local result = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      result[#result + 1] = buf
    end
  end
  return result
end

local function get_modified_original(buf_list)
  local m = {}
  for _, b in ipairs(buf_list) do
    m[b] = vim.bo[b].modified
  end
  return m
end

-- Approach B: getbufinfo
local function valid_buffers_getbufinfo()
  local valid = {}
  local modified = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = info.bufnr
    valid[#valid + 1] = buf
    modified[buf] = info.changed == 1
  end
  return valid, modified
end

local N = 3000

-- warmup
for _ = 1, 50 do
  valid_buffers_original()
  get_modified_original(bufs)
  valid_buffers_getbufinfo()
end

-- bench original
local s1 = vim.uv.hrtime()
for _ = 1, N do
  local v = valid_buffers_original()
  get_modified_original(v)
end
local t1 = vim.uv.hrtime() - s1

-- bench getbufinfo
local s2 = vim.uv.hrtime()
for _ = 1, N do
  valid_buffers_getbufinfo()
end
local t2 = vim.uv.hrtime() - s2

vim.api.nvim_win_get_width = orig_get_width

print(string.format('\ngetbufinfo isolated benchmark (%d iterations)\n', N))
print(string.format('%-35s %10s %10s', 'Method', 'Total(ms)', 'Avg(µs)'))
print(string.rep('-', 60))
print(string.format('%-35s %10.2f %10.2f', 'vim.bo[] x30 (original)', t1/1e6, t1/N/1e3))
print(string.format('%-35s %10.2f %10.2f', 'getbufinfo({buflisted=1})', t2/1e6, t2/N/1e3))
print(string.format('\nSpeedup: %.1fx', t1/t2))

-- Also bench full build_winbar (current optimized version)
for _ = 1, 50 do render.build_winbar(win) end
local s3 = vim.uv.hrtime()
for _ = 1, N do render.build_winbar(win) end
local t3 = vim.uv.hrtime() - s3
print(string.format('\nFull build_winbar (current):        %10.2f ms  %10.2f µs/call', t3/1e6, t3/N/1e3))

vim.cmd('qa!')
