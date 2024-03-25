local parsers = require('nvim-treesitter.parsers')
local string_utils = require('lu5je0.lang.string-utils')
local render = require('ufo.render')

local suffix_ft_white_list = { 'lua', 'java', 'json', 'xml', 'rust', 'python', 'html', 'c', 'cpp' }
local fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
  local newVirtText = {}

  -- 获取下一行，并移除首尾空格
  local next_line = string_utils.trim(vim.fn.getline(endLnum))
  -- todo 冗余
  local suffix = (' … %s 󰁂 %d'):format(next_line, endLnum - lnum)

  -- local suffix = (' 󰁂 %d '):format(endLnum - lnum)
  local sufWidth = vim.fn.strdisplaywidth(suffix)
  local targetWidth = width - sufWidth
  local curWidth = 0
  for _, chunk in ipairs(virtText) do
    local chunkText = chunk[1]
    local chunkWidth = vim.fn.strdisplaywidth(chunkText)
    if targetWidth > curWidth + chunkWidth then
      table.insert(newVirtText, chunk)
    else
      chunkText = truncate(chunkText, targetWidth - curWidth)
      local hlGroup = chunk[2]
      table.insert(newVirtText, { chunkText, hlGroup })
      chunkWidth = vim.fn.strdisplaywidth(chunkText)
      -- str width returned from truncate() may less than 2nd argument, need padding
      if curWidth + chunkWidth < targetWidth then
        suffix = suffix .. (' '):rep(targetWidth - curWidth - chunkWidth)
      end
      break
    end
    curWidth = curWidth + chunkWidth
  end

  local suffix_list = suffix:split('󰁂')

  local filetype = vim.bo.filetype
  if table.contain(suffix_ft_white_list, filetype) then
    table.insert(newVirtText, { ' … ', 'TSPunctBracket' })

    local nss = {}
    for _, ns in pairs(vim.api.nvim_get_namespaces()) do
      table.insert(nss, ns)
    end

    local end_line_virt_text = render.captureVirtText(vim.api.nvim_get_current_buf(), vim.fn.getline(endLnum), endLnum, nil, nss, 0)
    -- 移除前导空格
    local encounter_text = false
    for _, v in ipairs(end_line_virt_text) do
      if not encounter_text and string_utils.is_blank(v[1]) then
        goto continue
      end

      table.insert(newVirtText, v)
      encounter_text = true

      ::continue::
    end
  end

  table.insert(newVirtText, { ' 󰁂' .. suffix_list[2], 'MoreMsg' })
  return newVirtText
end

-- vim.o.foldcolumn = '1'
vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
vim.o.foldlevelstart = 99
vim.o.foldenable = true

local trigger_fold_opened = function()
  vim.defer_fn(function()
    vim.cmd('doautocmd User FoldChanged')
    vim.cmd('doautocmd User FoldOpened')
  end, 0)
end

local trigger_fold_closed = function()
  vim.defer_fn(function()
    vim.cmd('doautocmd User FoldChanged')
    vim.cmd('doautocmd User FoldClosed')
  end, 0)
end

vim.keymap.set('n', 'zR', function()
  require('ufo').openAllFolds()
  trigger_fold_opened()
end)
vim.keymap.set('n', 'zM', function()
  require('ufo').closeAllFolds()
  trigger_fold_closed()
end)

vim.keymap.set('n', 'zc', function()
  vim.api.nvim_feedkeys('zc', 'n', true)
  trigger_fold_closed()
end, { noremap = true })

vim.keymap.set('n', 'zo', function()
  vim.api.nvim_feedkeys('zo', 'n', true)
  trigger_fold_opened()
end, { noremap = true })

local group = vim.api.nvim_create_augroup('nvim-ufo-patch', { clear = true })
vim.api.nvim_create_autocmd('WinNew', {
  group = group,
  pattern = '*',
  callback = function()
    vim.cmd('UfoDetach')
    vim.cmd('UfoAttach')
  end,
})

require('ufo').setup({
  provider_selector = function(bufnr, filetype, buftype)
    if parsers.get_parser(bufnr) then
      return { 'treesitter' }
    end
    return { 'treesitter' }
  end,
  close_fold_kinds_for_ft = {},
  open_fold_hl_timeout = 0,
  fold_virt_text_handler = fold_virt_text_handler
})

-- local group = vim.api.nvim_create_augroup('nvim-ufo', { clear = true })
-- vim.api.nvim_create_autocmd("LspAttach", {
--   group = group,
--   ---@diagnostic disable-next-line: unused-local
--   callback = function(args)
--     require('ufo').setup()
--   end
-- })
