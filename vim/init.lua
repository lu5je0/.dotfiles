vim.loader.enable()

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local core_modules = {
  'lu5je0.lang.enhance',
  'lu5je0.options',
  'lu5je0.mappings',
  'lu5je0.plugins',
  'lu5je0.commands',
  'lu5je0.autocmds',
  'lu5je0.filetype',
  'lu5je0.ext-loader',
}

for _, module in ipairs(core_modules) do
  local ok, err = pcall(require, module)
  if not ok then
    vim.notify('Error loading ' .. module .. '\n\n' .. err)
  end
end

vim.cmd('runtime functions.vim')
