local M = {}

M.buffer_name_map = {}

M.pick_active = false
M.pick_map = {}

M.refresh_scheduled = false

-- per-window buffer tracking: win_id -> { buf1, buf2, ... } in order of first open
M.win_bufs = {}

-- persistent global buffer order for the single-window / single-tabpage case;
-- drag-reordering rewrites this list.
M.buf_order = {}

-- per-window hit-test ranges recorded during render: win_id -> { {buf, ordinal, from, to}, ... }
M.tab_regions = {}

-- active drag session: { buf = <bufnr>, win = <win_id> } or nil
M.drag = nil

-- window whose last tab was dragged out: renders an empty tab strip and is
-- closed when the mouse is released.
M.pending_close_win = nil

return M
