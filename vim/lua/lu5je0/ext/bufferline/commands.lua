local M = {}

function M.setup()
  vim.api.nvim_create_user_command('BufferLinePickSplit', function()
    require('lu5je0.ext.bufferline.pick').start({
      on_choose = function(bufnr)
        vim.cmd('vert sbuffer ' .. bufnr)
      end,
    })
  end, { force = true })

  vim.api.nvim_create_user_command('BufferLinePick', function()
    require('lu5je0.ext.bufferline.pick').start()
  end, { force = true })

  vim.api.nvim_create_user_command('BufferLineCloseLeft', function()
    require('lu5je0.ext.bufferline.actions').close_left()
  end, { force = true })

  vim.api.nvim_create_user_command('BufferLineCloseRight', function()
    require('lu5je0.ext.bufferline.actions').close_right()
  end, { force = true })

  vim.api.nvim_create_user_command('BufferLineCloseOthers', function()
    require('lu5je0.ext.bufferline.actions').close_others()
  end, { force = true })

  vim.api.nvim_create_user_command('BufferLineCycleNext', function()
    require('lu5je0.ext.bufferline.actions').cycle(1)
  end, { force = true })

  vim.api.nvim_create_user_command('BufferLineCyclePrev', function()
    require('lu5je0.ext.bufferline.actions').cycle(-1)
  end, { force = true })
end

return M
