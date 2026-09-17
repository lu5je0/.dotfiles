-- Registers an autocmd that fires whenever a buffer's 'modified' flag changes.
--
-- The event differs by version, and neither alone covers both paths:
--
--   Nvim 0.12: natural edits (insert/delete/undo) only set `b_changed_invalid` and are
--   dispatched from the main loop as `BufModifiedSet`; `OptionSet modified` fires only for
--   an explicit `:set [no]modified`.
--
--   Nvim 0.13: `BufModifiedSet` was removed (news.txt / deprecated.txt, PR #35610).
--   `changed_internal()` / `unchanged()` call `aucmd_defer_modified()` directly, so
--   `OptionSet modified` now covers natural edits too.
--
-- So 0.12 needs BOTH events, while 0.13 only accepts `OptionSet`. Registering both on 0.13
-- is impossible (`BufModifiedSet` is not in the event table and creation errors), hence the
-- capability probe. On 0.12 the two events are disjoint (each path fires exactly one), so
-- there is no duplicate triggering.
local M = {}

local has_buf_modified_set = vim.fn.exists('##BufModifiedSet') == 1

--- Calls `callback` when any buffer's 'modified' flag changes.
---
--- `callback` receives the autocmd event args. Both `BufModifiedSet` (0.12) and
--- `OptionSet modified` (0.12 + 0.13) are covered by a single registration.
--- @param group integer|string augroup id or name
--- @param callback fun(ev: vim.api.keyset.events) Called on every change.
function M.register(group, callback)
  vim.api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = 'modified',
    callback = callback,
  })
  if has_buf_modified_set then
    vim.api.nvim_create_autocmd('BufModifiedSet', {
      group = group,
      callback = callback,
    })
  end
end

return M
