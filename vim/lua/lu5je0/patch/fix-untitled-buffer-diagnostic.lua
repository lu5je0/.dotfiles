-- 这个 patch 的目的：
-- 1) 未命名 buffer（[No Name]）的 bufname 为空。某些 LSP 仍会返回它的诊断，
--    但 Neovim 处理诊断时走的是 URI -> fname -> bufadd/bufexists 这条链路，
--    空名字无法映射回原 buffer，导致诊断丢失。
-- 2) 给未命名 buffer 生成稳定的虚拟 URI：
--      file:///tmp/nvim-untitled-buffer/untitled-<bufnr>
--    再通过 bufadd/bufexists 把这个虚拟路径反查回原未命名 buffer。
-- 3) 注意：Neovim 里 bufnr=0 表示“当前 buffer”，不是字面值 0。
--    如果按 0 处理，LSP 请求（如 outline 的 documentSymbol）会发错 URI
--    （untitled-0），从而出现无结果。

if vim.g._fix_untitled_file_diagnostic_applied then
  return
end

local untitled_prefix = '/tmp/nvim-untitled-buffer/untitled-'

local function normalize_bufnr(bufnr)
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function is_untitled_buf(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == ''
end

local function untitled_uri(bufnr)
  return vim.uri_from_fname(untitled_prefix .. bufnr)
end

local function parse_untitled_bufnr(fname)
  if type(fname) ~= 'string' or not vim.startswith(fname, untitled_prefix) then
    return nil
  end
  local bufnr = tonumber(fname:match('untitled%-(%d+)$'))
  if bufnr and is_untitled_buf(bufnr) then
    return bufnr
  end
  return nil
end

local old_uri_from_bufnr = vim.uri_from_bufnr
vim.uri_from_bufnr = function(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if is_untitled_buf(bufnr) then
    return untitled_uri(bufnr)
  end
  return old_uri_from_bufnr(bufnr)
end

local old_bufadd = vim.fn.bufadd
vim.fn.bufadd = function(fname)
  local bufnr = parse_untitled_bufnr(fname)
  if bufnr then
    return bufnr
  end
  return old_bufadd(fname)
end

local old_bufexists = vim.fn.bufexists
vim.fn.bufexists = function(fname)
  local bufnr = parse_untitled_bufnr(fname)
  if bufnr then
    return 1
  end
  return old_bufexists(fname)
end

vim.g._fix_untitled_file_diagnostic_applied = true
