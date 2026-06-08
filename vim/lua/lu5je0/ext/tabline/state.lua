local M = {}

M.buffer_name_map = {}

M.pick_active = false
M.pick_map = {}

M.refresh_scheduled = false

-- per-window buffer tracking: win_id -> { buf1, buf2, ... } in order of first open
M.win_bufs = {}

-- the actual focused window (updated before winbar eval)
M.focused_win = -1

return M
