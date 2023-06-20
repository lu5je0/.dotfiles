require("substitute").setup {}

vim.keymap.set("n", "cx", function()
  local backup_range = vim.highlight.range
  
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.highlight.range = function(...)
    local params = { ... }
    -- 只有再exchange的时候修改优先级
    if params[3] == 'SubstituteExchange' then
      params[6].priority = 5000
    end
    backup_range(...)
  end
  
  require('substitute.exchange').operator()
  
  -- 恢复range函数避免影响性能
  vim.defer_fn(function()
    vim.highlight.range = backup_range
  end, 1000)
end, { noremap = true })

vim.keymap.set("n", "gr", require('substitute').operator, { noremap = true })
vim.keymap.set("n", "grr", require('substitute').line, { noremap = true })
vim.keymap.set("x", "gr", require('substitute').visual, { noremap = true })
