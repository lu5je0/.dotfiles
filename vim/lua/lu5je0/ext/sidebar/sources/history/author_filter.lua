local lifecycle = require('lu5je0.ext.sidebar.lifecycle')
local model = require('lu5je0.ext.sidebar.sources.history.model')

local M = {}

function M.setup_completion(prompt, buf)
  local h = prompt.source
  vim.bo[buf].completeopt = 'menu,menuone'
  local candidates = {}
  prompt.job = model.load_authors(h.repo_root, function(entries)
    if lifecycle.is_current(prompt.ctx) and h.filter_prompt == prompt then
      candidates = entries
      prompt.job = nil
    end
  end)

  vim.keymap.set('i', '<CR>', function()
    return vim.fn.pumvisible() == 1 and '<C-y><CR>' or '<CR>'
  end, { buffer = buf, expr = true })
  vim.keymap.set('i', '<Tab>', function()
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.keycode('<C-n>'), 'in', false)
      return
    end
    local column = vim.api.nvim_win_get_cursor(prompt.win)[2]
    local typed = vim.fn.tolower(vim.api.nvim_get_current_line():sub(1, column))
    local matches = vim.tbl_filter(function(candidate)
      return vim.startswith(vim.fn.tolower(candidate.word), typed)
    end, candidates)
    if #matches > 0 then
      vim.fn.complete(1, matches)
    end
  end, { buffer = buf, nowait = true })
end

return M
