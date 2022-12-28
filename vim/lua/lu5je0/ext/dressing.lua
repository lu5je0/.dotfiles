require('dressing').setup({
  input = {
    -- Set to false to disable the vim.ui.input implementation
    enabled = true,

    -- Default prompt string
    default_prompt = "",

    -- Can be 'left', 'right', or 'center'
    prompt_align = "left",

    -- When true, <Esc> will close the modal
    insert_only = true,

    -- When true, input will start in insert mode.
    start_in_insert = false,

    -- These are passed to nvim_open_win
    anchor = "SW",

    border = "single",
    -- 'editor' and 'win' will default to being centered
    relative = "cursor",

    -- These can be integers or a float between 0 and 1 (e.g. 0.4 for 40%)
    prefer_width = 40,
    width = nil,
    -- min_width and max_width can be a list of mixed types.
    -- min_width = {20, 0.2} means "the greater of 20 columns or 20% of total"
    max_width = { 140, 0.9 },
    min_width = { 20, 0.2 },

    buf_options = {},
    win_options = {
      -- Window transparency (0-100)
      winblend = 0,
      -- Disable line wrapping
      wrap = false,
    },

    -- Set to `false` to disable
    mappings = {
      n = {
        ["<esc>"] = false,
        ["<c-c>"] = "Close",
        ["<cr>"] = "Confirm",
      },
      i = {
        ["<esc>"] = false,
        ["<c-c>"] = false,
        ["<cr>"] = "Confirm",
        ["<up>"] = "HistoryPrev",
        ["<down>"] = "HistoryNext",
      },
    },

    override = function(var)
      -- This is the config that will be passed to nvim_open_win.
      -- Change values here to customize the layout
      -- p
      var.row = 4
      return var
    end,

    -- see :help dressing_get_config
    get_config = nil,
  },
})

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('dressing', { clear = true }),
  pattern = 'DressingInput',
  callback = function()
    vim.keymap.del('i', '<esc>', { buffer = true })
    require('lu5je0.core.keys').feedkey('$')
    vim.cmd('set winhighlight=NormalFloat:Normal,FloatBorder:Comment')
  end,
})
