local loader = require('lu5je0.ext.loader')
local lazy_load = loader.lazy_load

-- bufferline (custom, replaces akinsho/bufferline.nvim)
lazy_load({
  name = 'bufferline',
  config = function()
    require('lu5je0.ext.bufferline')
  end,
  event = { 'UIEnter' },
})

-- tree-sidebar
lazy_load({
  name = 'tree-sidebar',
  config = function()
    require('lu5je0.ext.tree-sidebar').setup()
  end,
  keys = {
    { mode = { 'n' }, '<leader>e' },
    { mode = { 'n' }, '<leader>E' },
    { mode = { 'n' }, '<leader>fe' },
    { mode = { 'n' }, '<leader>fg' },
    { mode = { 'n' }, '<leader>gs' },
    { mode = { 'n' }, '<leader>fb' },
    { mode = { 'n' }, '<leader>fs' },
    { mode = { 'n' }, '<leader>s' },
  },
})

-- im
lazy_load({
  name = 'im',
  config = function()
    if vim.fn.has('gui') == 0 then
      require('lu5je0.misc.im.im').setup()
    end
  end,
  event = { 'InsertEnter', 'CursorHold', 'VimEnter' },
  keys = {
    { mode = { 'n' }, '<leader>vi' },
  }
})

-- json-helper
lazy_load({
  name = 'json-helper',
  config = function()
    require('lu5je0.misc.json-helper').setup()
  end,
  cmd = { 'Json', 'JsonCompress', 'JsonExtract', 'JsonCopyPath', 'JsonFormat', 'JsonSortByKey', 'Jq', 'JsonFixNonStringKey' }
})

-- junkfile
lazy_load({
  name = 'junkfile',
  config = function()
    require('lu5je0.misc.junkfile').setup()
  end,
  cmd = { 'JunkFileNew', 'JunkFileSaveAs' }
})

-- formatter
lazy_load({
  name = 'formatter',
  config = function()
    local formatter = require('lu5je0.misc.formatter.formatter')
    formatter.setup {
      format_priority = {
        [{ 'javascript' }] = { formatter.FORMAT_TOOL_TYPE.LSP, formatter.FORMAT_TOOL_TYPE.EXTERNAL },
        [{ 'json' }] = { formatter.FORMAT_TOOL_TYPE.EXTERNAL, formatter.FORMAT_TOOL_TYPE.LSP },
        [{ 'bash', 'sh', 'python', 'yaml' }] = { formatter.FORMAT_TOOL_TYPE.EXTERNAL, formatter.FORMAT_TOOL_TYPE.LSP },
      },
      external_formatter = {
        json = {
          format = function()
            vim.cmd [[ JsonFormat ]]
          end,
          range_format = function()
          end,
        },
        sql = {
          format = function()
            vim.cmd(':%!sql-formatter -l mysql')
          end,
          range_format = function()
          end,
        },
        [{ 'bash', 'sh' }] = {
          format = function()
            vim.cmd(':%!shfmt -i ' .. vim.bo.shiftwidth)
          end,
          range_format = function()
          end,
        },
        [{ 'python' }] = {
          format = function()
            vim.cmd(':%!black -q -')
          end,
          range_format = function()
          end,
        },
        html = {
          format = function()
            vim.cmd(':%!prettier --parser html')
          end,
          range_format = function()
            vim.cmd(":'<,'>%!prettier --parser html")
          end,
        },
        [{ 'xml' }] = {
          format = function()
            vim.cmd(':%!xmllint - --format')
          end,
          range_format = function()
          end,
        },
        [{ 'yaml' }] = {
          format = function()
            vim.cmd(':%!prettier --parser yaml')
          end,
          range_format = function()
            vim.cmd(":'<,'>%!prettier --parser yaml")
          end,
        },
        [{ 'markdown' }] = {
          format = function()
            vim.cmd(':%!prettier --parser markdown')
          end,
          range_format = function()
            vim.cmd(":'<,'>%!prettier --parser markdown")
          end,
        },
        [{ 'javascript' }] = {
          format = function()
            vim.cmd(':%!prettier --parser babel')
          end,
          range_format = function()
            vim.cmd(":'<,'>%!prettier --parser babel")
          end,
        }
      }
    }
  end,
  keys = {
    { mode = { 'n', 'x' }, '<leader>cf' },
    { mode = { 'n', 'x' }, '<leader>cF' },
  },
})

-- var-naming-converter
lazy_load({
  name = 'var-naming-converter',
  config = function()
    require('lu5je0.misc.var-naming-converter').key_mapping()
  end,
  keys = {
    { mode = { 'x', 'n' }, '<leader>cn' },
  },
})

-- code-runner
lazy_load({
  name = 'code-runner',
  config = function()
    require('lu5je0.misc.code-runner').key_mapping()
    require('lu5je0.misc.code-runner').create_command()
  end,
  keys = {
    { mode = { 'n' }, '<leader>rr' },
    { mode = { 'n' }, '<leader>rd' },
  },
  cmd = { 'LuaDevOn', 'LuaDevOff' }
})

-- quit-prompt
lazy_load({
  name = 'quit-prompt',
  config = function()
    require('lu5je0.misc.quit-prompt').setup()
  end,
  keys = {
    { mode = { 'n' }, '<leader>q' },
    { mode = { 'n' }, '<leader>Q' },
  }
})

lazy_load({
  name = 'redir',
  config = function()
    require('lu5je0.misc.redir')
  end,
  cmd = { 'Redir' },
  complete = true,
})

lazy_load({
  name = 'base64',
  config = function()
    require('lu5je0.misc.base64').create_command()
  end,
  cmd = { 'Base64Decode', 'Base64Encode' }
})

lazy_load({
  name = 'gmt',
  config = function()
    require('lu5je0.misc.gmt').create_command()
  end,
  cmd = { 'TimestampToggle' }
})

lazy_load({
  name = 'timestamp',
  config = function()
    require('lu5je0.misc.timestamp').setup()
  end,
  cmd = { 'TimestampModify', 'TimestampShow', 'TimestampReplaceAll' }
})

lazy_load({
  name = 'set-operation',
  config = function()
    require('lu5je0.misc.set-operation').setup()
  end,
  cmd = { 'SetOperation' }
})

lazy_load({
  name = 'line-tools',
  config = function()
    require('lu5je0.misc.line-tools').setup()
  end,
  cmd = { 'KeepLines', 'DelLines', 'KeepMatchs' }
})

lazy_load({
  name = 'comment',
  config = function()
    require('lu5je0.core.comment').setup()
  end,
  keys = {
    { mode = { 'x' }, 'gc' },
  }
})

lazy_load({
  name = 'calculator',
  config = function()
    require('lu5je0.misc.calculator').setup()
  end,
  keys = {
    { mode = { 'n' }, '<leader>a' },
    { mode = { 'x' }, '<leader>a' },
  }
})

lazy_load({
  name = 'translator',
  config = function()
    require('lu5je0.misc.translator').setup({
      width = 50
    })
  end,
  keys = {
    { mode = { 'n', 'x' }, '<leader>ww' },
    { mode = { 'n', 'x' }, '<leader>wr' },
  }
})

lazy_load({
  name = 'boole',
  config = function()
    require('lu5je0.ext.boole').setup({
      mappings = {},
      -- User defined loops
      additions = {
        -- { 'Foo', 'Bar' },
      },
      allow_caps_additions = {
        -- enable -> disable
        -- Enable -> Disable
        -- ENABLE -> DISABLE
        { 'enable', 'disable' },
      },
    })
  end,
  keys = {
    { mode = { 'n' }, '<c-a>' },
    { mode = { 'n' }, '<c-x>' },
  }
})

lazy_load({
  name = 'git',
  config = function()
    require('lu5je0.ext.git').setup({
      log_width = 30,
      win_height = 0.5,
      win_height_expanded = 0.9,
      project_log = {
        max_commits = 1000,
      },
      line_log = {},
      git_status = {}
    })
  end,
  keys = {
    { mode = { 'x' }, '<leader>gl' },
    { mode = { 'n' }, '<leader>gl' },
    { mode = { 'n' }, '<leader>gL' },
    -- { mode = { 'n' }, '<leader>gs' },
    { mode = { 'n' }, '<leader>gb' },
  },
  cmd = { 'GitStatusLog' }
})

-- lazy_load({
--   config = function()
--     require('lu5je0.ext.plugins_helper').load_plugin('nvim-ufo')
--   end,
--   keys = {
--     { mode = { 'n' }, 'zc' },
--     { mode = { 'n' }, 'zo' },
--     { mode = { 'n' }, 'zM' },
--     { mode = { 'n' }, 'zR' },
--     { mode = { 'n' }, 'zl' },
--     defer = 60,
--   },
--   event = { 'CursorHold' }
-- })

-- snippets
-- require('lu5je0.core.snippets').setup()

require('lu5je0.core.statusline').setup()

-- require('lu5je0.misc.dirbuf-hijack').setup()
require('lu5je0.misc.oil-hijack').setup()

require('lu5je0.misc.time-machine').setup()

-- patch
require('lu5je0.patch.fix-untitled-buffer-diagnostic')

return loader
