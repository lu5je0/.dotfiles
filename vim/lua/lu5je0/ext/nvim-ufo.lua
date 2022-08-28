local parsers = require('nvim-treesitter.parsers')

local fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
  local newVirtText = {}
  -- local suffix = (' … %s  %d '):format(vim.fn.getline(endLnum), endLnum - lnum)
  local suffix = ('  %d '):format(endLnum - lnum)
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
  table.insert(newVirtText, { suffix, 'MoreMsg' })
  return newVirtText
end

require('ufo').setup({
  provider_selector = function(bufnr, filetype, buftype)
    if parsers.get_parser(bufnr) then
      return { 'treesitter' }
    end
    return { 'lsp' }
  end,
  close_fold_kinds = {},
  open_fold_hl_timeout = 200,
  fold_virt_text_handler = fold_virt_text_handler
})
