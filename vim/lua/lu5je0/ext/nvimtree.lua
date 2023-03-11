---@diagnostic disable: missing-parameter
local M = {}

local lib = require('nvim-tree.lib')
local keys_helper = require('lu5je0.core.keys')
local api = require('nvim-tree.api')
local log = require('lu5je0.core.log')
local string_utils = require('lu5je0.lang.string-utils')

M.pwd_stack = require('lu5je0.lang.stack'):create()
M.pwd_forward_stack = require('lu5je0.lang.stack'):create()
M.pwd_back_state = 0

function M.locate_file()
  local cur_filepath = vim.fn.expand('%:p')
  local cur_file_dir_path = vim.fs.dirname(cur_filepath)
  local cwd = vim.fn.getcwd()

  if cur_file_dir_path == '' then
    return
  end

  local function turn_on_hidden_filter()
    if require("nvim-tree.explorer.filters").config.filter_dotfiles then
      api.tree.toggle_hidden_filter()
    end
  end

  local is_dotfile = vim.fs.basename(cur_filepath):sub(1, 1) == '.'
  if is_dotfile then
    turn_on_hidden_filter()
  end

  if not string_utils.starts_with(cur_file_dir_path, cwd) then
    vim.cmd(':cd ' .. cur_file_dir_path)
  else
    -- check if file in dotdir
    if not is_dotfile then
      for dir in vim.fs.parents(cur_filepath) do
        if dir == vim.fn.getcwd() then
          -- 如果和当前目录一样，就直接跳过吧
          break
        end
        if vim.fs.basename(dir):sub(1, 1) == '.' then
          turn_on_hidden_filter()
          break
        end
      end
    end
  end

  vim.cmd('NvimTreeFindFile')
end

function M.terminal_cd()
  local path = vim.fn.fnamemodify(require('nvim-tree.lib').get_node_at_cursor().absolute_path, ':p:h')
  require('lu5je0.ext.terminal').send_to_terminal(('cd "%s"'):format(path))
end

function M.delete_node()
  local bufs = require("lu5je0.core.buffers").valid_buffers()
  -- local bufs = vim.api.nvim_list_bufs()

  local is_remove_cur_file = false
  local cur_file_win_id = nil
  for _, win_id in pairs(vim.api.nvim_list_wins()) do
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    if vim.fn.buflisted(buf_id) then
      local path = vim.fn.expand("#" .. tostring(buf_id) .. ":p")
      if path == lib.get_node_at_cursor().absolute_path then
        is_remove_cur_file = true
        cur_file_win_id = win_id
        break
      end
    end
  end

  -- try to get substitute file when remove cur file
  local substitute_buf_id = nil
  if is_remove_cur_file then
    for _, buf_id in pairs(bufs) do
      if vim.fn.buflisted(buf_id) then
        if vim.bo[buf_id].filetype == 'NvimTree' then
          goto continue
        end
        local path = vim.fn.expand("#" .. tostring(buf_id) .. ":p")
        if path ~= lib.get_node_at_cursor().absolute_path
            and vim.bo[buf_id].buftype == ''
            and not string.find(path, 'undotree')
        then
          substitute_buf_id = buf_id
          break
        end
      end
      ::continue::
    end
  end

  if is_remove_cur_file and substitute_buf_id ~= nil then
    vim.api.nvim_win_set_buf(cur_file_win_id, substitute_buf_id)
  end
  local cur_width = vim.api.nvim_win_get_width(0)
  require 'nvim-tree.actions.dispatch'.dispatch('remove')
  if is_remove_cur_file and substitute_buf_id == nil then
    vim.cmd("vnew")
    vim.cmd('NvimTreeResize ' .. cur_width)
    keys_helper.feedkey('<c-w>p')
  end
end

function M.edit()
  if _G.preview_popup then
    _G.preview_popup:unmount()
  end
  require 'nvim-tree.actions.dispatch'.dispatch('edit')
end

function M.pwd_stack_push()
  M.pwd_stack:push(vim.fn.getcwd())
end

function M.create_dir()
  local origin_input = vim.ui.input
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.ui.input = function(input_opts, fn)
    local origin_fn = fn
    input_opts.prompt = 'Create Directory '
    fn = function(new_file_path)
      if new_file_path ~= nil then
        new_file_path = new_file_path .. '/'
      end
      return origin_fn(new_file_path)
    end
    origin_input(input_opts, fn)
  end
  require 'nvim-tree.actions.dispatch'.dispatch('create')
  vim.ui.input = origin_input
end

function M.back()
  if M.pwd_stack:count() >= 2 then
    M.pwd_back_state = 1
    M.pwd_forward_stack:push(M.pwd_stack:pop())
    vim.cmd(':cd ' .. M.pwd_stack:pop())
    M.pwd_back_state = 0
  end
end

function M.forward()
  if M.pwd_forward_stack:count() >= 1 then
    vim.cmd(':cd ' .. M.pwd_forward_stack:pop())
  end
end

function M.cd()
  require 'nvim-tree.actions.dispatch'.dispatch('cd')
  vim.cmd('norm gg')
end

function M.preview()
  local path = lib.get_node_at_cursor().absolute_path
  if vim.fn.isdirectory(path) == 1 then
    return
  end
  pcall(require('lu5je0.core.ui').preview, path)
end

function M.file_info()
  local info = vim.fn.system('ls -alhd "' ..
    lib.get_node_at_cursor().absolute_path .. '" -l --time-style="+%Y-%m-%d %H:%M:%S"')
  info = info .. vim.fn.system('du -h --max-depth=0 "' .. lib.get_node_at_cursor().absolute_path .. '"'):sub(1, -2)
  require('lu5je0.core.ui').popup_info_window(info)
end

function M.open_node()
  local node = lib.get_node_at_cursor()
  if node == nil then
    return
  end

  local parent_absolute_path = node.absolute_path
  if not node.open and (node.has_children or (node.nodes and #node.nodes ~= 0)) then
    vim.schedule(function()
      vim.cmd('norm j')
      if lib.get_node_at_cursor().parent.absolute_path ~= parent_absolute_path then
        vim.cmd('norm k')
      end
    end)
  end
  require 'nvim-tree.actions.dispatch'.dispatch('edit')
end

function M.close_node()
  local node = lib.get_node_at_cursor()
  require 'nvim-tree.actions.dispatch'.dispatch('close_node')
  if vim.fn.getcwd() == '/' then
    if node ~= lib.get_node_at_cursor() then
      keys_helper.feedkey('k')
    end
  end
end

function M.toggle_width()
  local cur_width = vim.api.nvim_win_get_width(0)
  local after_width = math.floor(vim.api.nvim_eval('&co') * 2 / 5)

  if M.last_width == nil or cur_width ~= after_width then
    vim.cmd('NvimTreeResize ' .. after_width)
    M.last_width = cur_width
    vim.cmd('vertical resize ' .. after_width)
  else
    vim.cmd('NvimTreeResize ' .. M.last_width)
    vim.cmd('vertical resize ' .. M.last_width)
  end
end

function M.increase_width(w)
  vim.cmd('vertical resize +' .. w)

  local width = vim.api.nvim_win_get_width(vim.api.nvim_get_current_win())
  vim.cmd('NvimTreeResize ' .. (width + w))
end

function M.reduce_width(w)
  vim.cmd('vertical resize -' .. w)

  local width = vim.api.nvim_win_get_width(vim.api.nvim_get_current_win())
  vim.cmd('NvimTreeResize ' .. (width - w))
end

local recursion_limit = 20
function M.target_git_item_reveal_to_file(action, recursion_count)
  recursion_count = recursion_count or 0
  if recursion_count > recursion_limit then
    return
  end

  local old_node = api.tree.get_node_under_cursor()
  require 'nvim-tree.actions.dispatch'.dispatch(action)
  local node = api.tree.get_node_under_cursor()
  if node == old_node and node.git_status and node.git_status.dir and next(node.git_status.dir) == nil then
    return
  end

  if node.type == 'directory' then
    if not node.open and node.git_status and node.git_status.dir and next(node.git_status.dir) ~= nil then
      require 'nvim-tree.actions.dispatch'.dispatch('edit')
    end
    M.target_git_item_reveal_to_file(action, recursion_count + 1)
  end
  vim.cmd('norm zz')
end

function M.setup()
  vim.cmd([[
    hi NvimTreeFolderName guifg=#e5c07b
    hi Directory ctermfg=107 guifg=#61afef
    hi NvimTreeOpenedFolderName guifg=#e5c07b
    hi default link NvimTreeFolderIcon Directory
    hi NvimTreeEmptyFolderName guifg=#e5c07b
    hi NvimTreeRootFolder guifg=#e06c75
    hi NvimTreeGitDirty guifg=#e06c75
    hi NvimTreeGitNew guifg=#c678dd

    autocmd DirChanged * lua require('lu5je0.ext.nvimtree').pwd_stack_push()

    function! NvimLocateFile()
      PackerLoad nvim-tree.lua
      lua require("lu5je0.ext.nvimtree").locate_file()
    endfunction

    lua vim.api.nvim_set_keymap('n', '<leader>fe', ':call NvimLocateFile()<cr>', { noremap = true, silent = true })
  ]])

  local opts = {
    noremap = true,
    silent = true,
    desc = 'nvim_tree'
  }
  vim.keymap.set('n', '<leader>e', function()
    require('nvim-tree').toggle(false, true)
  end, opts)
  vim.keymap.set('n', '<leader>fe', require('lu5je0.ext.nvimtree').locate_file, opts)

  local view = require('nvim-tree.view')
  view.View.winopts.signcolumn = 'no'
  view.View.winopts.foldcolumn = '1'

  -- default mappings
  local list = {
    { key = { '<CR>', 'l', 'o', '<2-LeftMouse>' }, cb = ":lua require('lu5je0.ext.nvimtree').open_node()<cr>" },
    { key = { '<BS>', 'h' }, cb = ":lua require('lu5je0.ext.nvimtree').close_node()<cr>" },
    { key = { 'cd' }, cb = ":lua require('lu5je0.ext.nvimtree').cd()<cr>" },
    { key = { 'C' }, action = 'toggle_git_clean' },
    { key = { 'B' }, action = 'toggle_no_buffer' },
    { key = { 't' }, cb = ":lua require('lu5je0.ext.nvimtree').terminal_cd()<cr>" },
    { key = '=', cb = ":lua require('lu5je0.ext.nvimtree').increase_width(2)<cr>" },
    { key = '-', cb = ":lua require('lu5je0.ext.nvimtree').reduce_width(2)<cr>" },
    { key = '+', cb = ":lua require('lu5je0.ext.nvimtree').increase_width(1)<cr>" },
    { key = '_', cb = ":lua require('lu5je0.ext.nvimtree').reduce_width(1)<cr>" },
    { key = ';', action = 'preview', action_cb = M.preview },
    { key = 'x', action = 'toggle_width', action_cb = M.toggle_width },
    { key = 'mk', action = 'create_dir', action_cb = M.create_dir },
    { key = 'D', action = 'delete', action_cb = M.delete_node },
    { key = 'H', cb = ':cd ~<cr>' },
    { key = 'd', cb = '<nop>' },
    { key = 's', action = 'vsplit' },
    { key = 'v', action = 'split' },
    { key = 'S', action = 'search_node' },
    { key = '[f', action = 'first_sibling' },
    { key = ']f', action = 'last_sibling' },
    { key = '<', action = 'prev_sibling' },
    { key = '>', action = 'next_sibling' },
    -- { key = 'f', cb = ":lua require('lu5je0.ext.nvimtree').file_info()<cr>" },
    { key = { 'K', 'F' }, action = 'toggle_file_info' },
    { key = 'f', action = 'live_filter' },
    { key = '.', action = 'run_file_command' },
    -- { key = 'P', action = 'parent_node' },
    { key = 'I', action = 'toggle_dotfiles' },
    { key = 'r', action = 'refresh' },
    { key = 'ma', action = 'create' },
    { key = 'mv', action = 'rename' },
    { key = "dd", action = ("cut") },
    { key = 'yy', action = 'copy' },
    { key = 'p', action = 'paste' },
    { key = 'yn', action = 'copy_name' },
    { key = 'yP', action = 'copy_path' },
    { key = 'yp', action = 'copy_absolute_path' },
    -- { key = '[g', action = 'prev_git_item' },
    -- { key = ']g', action = 'next_git_item' },
    { key = '[g', action = 'prev_git_item_reveal_to_file',
      action_cb = function()
        M.target_git_item_reveal_to_file('prev_git_item')
      end
    },
    { key = ']g', action = 'next_git_item_reveal_to_file',
      action_cb = function()
        M.target_git_item_reveal_to_file('next_git_item')
      end
    },
    { key = 'u', action = 'dir_up' },
    { key = 'o', action = 'system_open' },
    { key = 'q', action = 'close' },
    { key = 'x', action = 'toggle_mark' },
    { key = 'g?', action = 'toggle_help' },
    { key = '<c-o>', action = 'backward', action_cb = M.back },
    { key = { '<tab>', '<c-i>' }, action = 'forward', action_cb = M.forward },
  }

  require('nvim-tree').setup {
    disable_netrw = true,
    hijack_netrw = true,
    open_on_setup = false,
    ignore_ft_on_setup = {},
    open_on_tab = false,
    hijack_cursor = false,
    update_cwd = true,
    filesystem_watchers = {
      enable = true,
      debounce_delay = 1000,
    },
    diagnostics = {
      enable = false,
      icons = {
        hint = '',
        info = '',
        warning = '',
        error = '',
      },
    },
    hijack_directories = {
      enable = false
    },
    update_focused_file = {
      enable = false,
      update_cwd = false,
      ignore_list = {},
    },
    actions = {
      change_dir = {
        enable = true,
        global = true,
      },
      open_file = {
        window_picker = {
          exclude = {
            filetype = { 'notify', 'packer', 'qf', 'confirm', 'popup' },
            buftype = { 'terminal', 'nowrite', 'nofile' },
          }
        }
      }
    },
    git = {
      enable = true,
      ignore = false,
      timeout = 500,
    },
    system_open = {
      cmd = nil,
      args = {},
    },
    filters = {
      dotfiles = true,
      custom = {},
    },
    renderer = {
      full_name = true,
      indent_markers = {
        enable = true,
      },
      icons = {
        webdev_colors = true,
        git_placement = "before",
        padding = " ",
        symlink_arrow = " ➛ ",
        show = {
          file = true,
          folder = true,
          folder_arrow = false,
          git = true,
        },
        glyphs = {
          default = "",
          symlink = "",
          folder = {
            arrow_closed = "",
            arrow_open = "",
            default = "",
            open = "",
            empty = "",
            empty_open = "",
            symlink = "",
            symlink_open = "",
          },
          git = {
            unstaged = "✗",
            staged = "✓",
            unmerged = "",
            renamed = "➜",
            untracked = "",
            deleted = "",
            ignored = "◌",
          },
        },
      },
      special_files = {},
      symlink_destination = false,
    },
    view = {
      width = 27,
      hide_root_folder = false,
      side = 'left',
      mappings = {
        custom_only = true,
        list = list,
      },
      signcolumn = 'auto',
    },
  }

  -- require('lu5je0.ext.nvimtree.hover-popup')

  M.pwd_stack:push(vim.fn.getcwd())
  M.loaded = true

  vim.defer_fn(function()
    if vim.bo.filetype == 'NvimTree' then
      keys_helper.feedkey('<c-w>p')
    end
  end, 0)

  -- 关闭wsl executable检测，性能太低了
  require('nvim-tree.utils').is_wsl_windows_fs_exe = function() return false end
end

return M
