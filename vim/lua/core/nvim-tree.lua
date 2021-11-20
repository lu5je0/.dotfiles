local M = {}

function M.setup()
  vim.cmd[[
    let g:nvim_tree_icons = {
      \ 'default': '',
      \ 'symlink': '',
      \ 'git': {
        \   'unstaged': "✗",
        \   'staged': "✓",
        \   'unmerged': "",
        \   'renamed': "➜",
        \   'untracked': "★",
        \   'deleted': "",
        \   'ignored': "◌"
        \   },
        \ 'folder': {
          \   'arrow_open': " ",
          \   'arrow_closed': " ",
          \   'default': "",
          \   'open': "",
          \   'empty': "",
          \   'empty_open': "",
          \   'symlink': "",
          \   'symlink_open': "",
          \   }
          \ }
    let g:nvim_tree_show_icons = {
        \ 'git': 1,
        \ 'folders': 1,
        \ 'files': 1,
        \ 'folder_arrows': 1,
        \ }

    highlight NvimTreeFolderName guifg=#e5c07b
    highlight NvimTreeOpenedFolderName guifg=#e5c07b
    highlight NvimTreeEmptyFolderName guifg=#e5c07b
    highlight NvimTreeRootFolder guifg=#e06c75

    nnoremap <leader>e :NvimTreeToggle<CR><c-w>p
    nnoremap <leader>r :NvimTreeRefresh<CR>
    nnoremap <leader>fe :NvimTreeFindFile<CR>
  ]]
  vim.g.nvim_tree_special_files = {}
  vim.g.nvim_tree_add_trailing = 1
  vim.g.nvim_tree_indent_markers = 1


  require('nvim-tree.view').View.winopts.signcolumn = 'yes:1'

  local tree_cb = require'nvim-tree.config'.nvim_tree_callback
  -- default mappings
  local list = {
    { key = {"<CR>", "l", "o", "<2-LeftMouse>"}, cb = tree_cb("edit") },
    { key = {"cd", "C"}, cb = ":lua require('core/nvim-tree').cd()<cr>"},
    { key = "S",                        cb = tree_cb("vsplit") },
    { key = "s",                        cb = tree_cb("split") },
    -- { key = "<C-t>",                        cb = tree_cb("tabnew") },
    { key = "<",                            cb = tree_cb("prev_sibling") },
    { key = ">",                            cb = tree_cb("next_sibling") },
    { key = "P",                            cb = tree_cb("parent_node") },
    { key = {"<BS>", 'h'},                         cb = tree_cb("close_node") },
    { key = "p",                        cb = tree_cb("preview") },
    { key = "K",                            cb = tree_cb("first_sibling") },
    { key = "J",                            cb = tree_cb("last_sibling") },
    -- { key = "I",                            cb = tree_cb("toggle_ignored") },
    { key = "I",                            cb = tree_cb("toggle_dotfiles") },
    { key = "r",                            cb = tree_cb("refresh") },
    { key = "ma",                            cb = tree_cb("create") },
    { key = "D",                            cb = tree_cb("remove") },
    { key = "mv",                        cb = tree_cb("rename") },
    -- { key = "x",                            cb = tree_cb("cut") },
    { key = "yy",                            cb = tree_cb("copy") },
    { key = "p",                            cb = tree_cb("paste") },
    { key = "yn",                            cb = tree_cb("copy_name") },
    { key = "yP",                            cb = tree_cb("copy_path") },
    { key = "yp",                           cb = tree_cb("copy_absolute_path") },
    { key = "[g",                           cb = tree_cb("prev_git_item") },
    { key = "]g",                           cb = tree_cb("next_git_item") },
    { key = "U",                            cb = tree_cb("dir_up") },
    { key = "s",                            cb = tree_cb("system_open") },
    { key = "q",                            cb = tree_cb("close") },
    { key = "g?",                           cb = tree_cb("toggle_help") },
  }

  require('nvim-tree').setup {
    disable_netrw       = true,
    hijack_netrw        = true,
    open_on_setup       = false,
    ignore_ft_on_setup  = {},
    auto_close          = false,
    open_on_tab         = false,
    hijack_cursor       = true,
    update_cwd          = true,
    update_to_buf_dir   = {
      enable = false,
      auto_open = true,
    },
    diagnostics = {
      enable = false,
      icons = {
        hint = "",
        info = "",
        warning = "",
        error = "",
      }
    },
    -- update_focused_file = {
    --   enable      = false,
    --   update_cwd  = false,
    --   ignore_list = {}
    -- },
    system_open = {
      cmd  = nil,
      args = {}
    },
    filters = {
      dotfiles = true,
      custom = {'.git'}
    },
    view = {
      width = 25,
      height = 30,
      hide_root_folder = false,
      side = 'left',
      auto_resize = false,
      mappings = {
        custom_only = false,
        list = list
      }
    }
  }
end

function M.cd()
  print("begin" .. vim.api.nvim_eval("getcwd()"))
  require'nvim-tree'.on_keypress('cd')
  print("end" .. vim.api.nvim_eval("getcwd()"))
end

return M
