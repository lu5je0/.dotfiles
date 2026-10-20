-- 原生多光标的批量编辑保护，供 gitsigns / DiffBase 共用。
-- 不加载按键适配层，也不负责 Git 操作或匹配规则。
local M = {}
local ok, mc = pcall(require, 'vim._core.mcursor')
M.supported = ok and type(mc.active) == 'function' and vim.fn.exists('+follow') == 1

local function report_error(err)
  if err then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

M.preserve = function(action)
  return action(report_error)
end

local cursor_edits = {}
local edit_watchers = {}
local capture_session, restore_session

--- 注册会话元数据的保存与恢复；匹配规则等私有状态由按键适配层持有。
--- @param capture fun(buf: integer): any
--- @param restore fun(buf: integer, state: any)
function M.set_session_hooks(capture, restore)
  capture_session, restore_session = capture, restore
end

--- 用户主动结束会话时取消尚未完成的恢复。
--- @param buf integer
function M.cancel(buf)
  if cursor_edits[buf] then
    cursor_edits[buf].cancelled = true
  end
end

if not M.supported then
  return M
end

local ns = vim.api.nvim_create_namespace('nvim.multicursor')

--- 批量替换行会合并原生 extmarks。保存逻辑位置，在外部编辑完成后还原。
--- action(done) 必须在同步/异步编辑结束时调用 done；普通编辑仍走原生位置追踪。
--- @param action fun(done: fun(err?: string))
function M.preserve(action)
  if vim.v.cascading then
    return
  end
  if not mc.active() then
    return action(report_error)
  end
  local buf = vim.api.nvim_get_current_buf()
  if cursor_edits[buf] then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local state = {
    points = { { cur[1] - 1, cur[2] } },
    win = vim.api.nvim_get_current_win(),
    follow = vim.bo[buf].follow,
    session = capture_session and capture_session(buf),
  }
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
    state.points[#state.points + 1] = { mark[2], mark[3], mark[1] }
  end
  cursor_edits[buf] = state
  if not edit_watchers[buf] then
    edit_watchers[buf] = vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, b, _, first, last, new_last)
        local edit = cursor_edits[b]
        if not edit then
          return
        end
        edit.changed = true
        for _, pos in ipairs(edit.points) do
          if pos[1] >= last then
            pos[1] = pos[1] + new_last - last
          elseif pos[1] >= first then
            pos[1] = first + math.min(pos[1] - first, math.max(new_last - first - 1, 0))
          end
        end
      end,
      on_detach = function(_, b)
        cursor_edits[b], edit_watchers[b] = nil, nil
      end,
    })
  end

  -- 在 typed CmdAtom 外只执行一次外部编辑，避免在每个 cursor 上重放整段替换。
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() ~= buf or cursor_edits[buf] ~= state or state.cancelled then
      if cursor_edits[buf] == state then
        cursor_edits[buf] = nil
      end
      return
    end
    vim.bo[buf].follow = false
    local finished = false
    local function done(err)
      if finished then
        return
      end
      finished = true
      report_error(err)
      vim.schedule(function()
        if cursor_edits[buf] ~= state then
          return
        end
        cursor_edits[buf] = nil
        if state.cancelled or not vim.api.nvim_buf_is_loaded(buf) then
          return
        end
        if state.changed then
          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
          local seen = {}
          for i, pos in ipairs(state.points) do
            local row = math.min(pos[1], vim.api.nvim_buf_line_count(buf) - 1)
            local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
            local col = math.min(pos[2], math.max(#line - 1, 0))
            -- 字节列不能落在 UTF-8 续字节上。
            while col > 0 and (line:byte(col + 1) or 0) >= 0x80 and line:byte(col + 1) < 0xC0 do
              col = col - 1
            end
            local key = row .. ':' .. col
            if i == 1 then
              if vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_win_get_buf(state.win) == buf then
                vim.api.nvim_win_set_cursor(state.win, { row + 1, col })
              end
            elseif not seen[key] then
              vim.api.nvim_buf_set_extmark(buf, ns, row, col, { id = pos[3] })
            end
            seen[key] = true
          end
          if restore_session then
            restore_session(buf, state.session)
          end
        end
        vim.bo[buf].follow = state.follow
      end)
    end
    local success, err = pcall(action, done)
    if not success then
      done()
      error(err)
    end
  end)
end

return M
