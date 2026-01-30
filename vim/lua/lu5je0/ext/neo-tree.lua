local M = {}

-- cwd 历史栈（对齐你 nvim-tree 的 back/forward 习惯）
M.pwd_stack = require('lu5je0.lang.stack'):create()
M.pwd_forward_stack = require('lu5je0.lang.stack'):create()
M._is_jumping = false
M._last_pushed_cwd = nil

function M.pwd_stack_push()
  if M._is_jumping then
    return
  end
  local cwd = vim.fn.getcwd()
  if M._last_pushed_cwd ~= cwd then
    M.pwd_stack:push(cwd)
    M._last_pushed_cwd = cwd
  end
end

local function neotree_refresh()
  -- neo-tree 刷新是 action/API，不是 :Neotree refresh 子命令
  pcall(function()
    require("neo-tree.sources.manager").refresh("filesystem")
  end)
end

local function back()
  if M.pwd_stack:count() >= 2 then
    M._is_jumping = true
    M.pwd_forward_stack:push(M.pwd_stack:pop())
    local target = M.pwd_stack:pop()
    vim.cmd(':cd ' .. target)
    M._is_jumping = false
    neotree_refresh()
  end
end

local function forward()
  if M.pwd_forward_stack:count() >= 1 then
    M._is_jumping = true
    local target = M.pwd_forward_stack:pop()
    vim.cmd(':cd ' .. target)
    M._is_jumping = false
    neotree_refresh()
  end
end

M.setup = function()
  vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])

  local function cmd(s)
    return function() vim.cmd(s) end
  end

  require("neo-tree").setup({
    close_if_last_window = false,
    popup_border_style = "rounded",
    enable_git_status = true,
    enable_diagnostics = false,

    source_selector = {
      winbar = true,
      statusline = false,
    },

    filesystem = {
      bind_to_cwd = true,
      follow_current_file = { enabled = false },
      use_libuv_file_watcher = true,

      filtered_items = {
        visible = false,
        hide_dotfiles = true,
        hide_gitignored = false,
        hide_hidden = false,
      },
    },

    window = {
      position = "left",
      width = 35,
      mapping_options = {
        noremap = true,
        nowait = true,
      },
      mappings = {
        -- 基础导航（对齐你的 nvim-tree）
        ["l"] = "open",
        ["<cr>"] = "open",
        ["h"] = "close_node",
        ["u"] = "navigate_up",
        ["q"] = "close_window",

        -- 刷新/帮助/过滤
        ["r"] = "refresh",
        ["?"] = "show_help",
        ["f"] = "filter_on_submit",
        ["<esc>"] = "clear_filter",

        -- 文件操作（对齐你常用的那套）
        ["ma"] = "add",
        ["mv"] = "rename",
        ["D"] = "delete",
        ["dd"] = "cut_to_clipboard",
        ["yy"] = "copy_to_clipboard",
        ["p"] = "paste_from_clipboard",

        -- 显隐 dotfiles（对齐 I）
        ["I"] = "toggle_hidden",

        -- cd：切当前节点为根
        ["cd"] = "set_root",

        -- 防止误触（你原来有 ["c"]="noop"）
        ["c"] = "noop",

        -- x：切宽
        ["x"] = function(state)
          local winid = state.winid
          if not winid or not vim.api.nvim_win_is_valid(winid) then
            return
          end
          local cur = vim.api.nvim_win_get_width(winid)
          local half = math.floor(vim.o.columns * 0.5)
          state._last_width = state._last_width or cur
          local target
          if cur ~= half then
            state._last_width = cur
            target = half
          else
            target = state._last_width
          end
          vim.api.nvim_win_set_width(winid, target)
        end,

        -- 切 source
        ["<left>"] = "prev_source",
        ["<right>"] = "next_source",

        ["z"] = "noop",

        -- 目录 back/forward（对齐你的 nvim-tree）
        ["<c-o>"] = back,
        ["<c-i>"] = forward,
      },
    },
  })

  -- 全局快捷键（对齐你的 nvim-tree）
  vim.keymap.set('n', '<leader>e', cmd('Neotree toggle'), { desc = 'neo-tree toggle' })
  vim.keymap.set('n', '<leader>E', cmd('Neotree focus'), { desc = 'neo-tree focus' })
  vim.keymap.set('n', '<leader>fe', cmd('Neotree focus reveal'), { desc = 'neo-tree reveal file' })

  -- 初始化栈 + DirChanged 自动记录（对齐你 nvim-tree 的 autocmd DirChanged）
  local cwd = vim.fn.getcwd()
  M.pwd_stack:push(cwd)
  M._last_pushed_cwd = cwd

  vim.api.nvim_create_autocmd('DirChanged', {
    callback = function()
      require('lu5je0.ext.neo-tree').pwd_stack_push()
    end,
  })
end

return M

