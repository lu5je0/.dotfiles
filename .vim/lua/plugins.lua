-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
return require('packer').startup(function()
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'

  use {
      'akinsho/bufferline.nvim', 
      config = function() require("config/bufferline") end
  }

  use 'kyazdani42/nvim-web-devicons'

  -- Use specific branch, dependency and run lua file after load
  use {
      'glepnir/galaxyline.nvim',
      branch = 'main',
      config = function() require("config/galaxyline") end,
  }

  use {'jiangmiao/auto-pairs'}
  use {'schickling/vim-bufonly'}

  use {
      'theniceboy/vim-calc',
      opt = true,
      keys = '<leader>a'
  }

  use {
      'rootkiter/vim-hexedit',
      opt = true,
      ft = 'bin',
      keys = '<leader>vh'
  }

  use {'mattn/vim-gist'}
  use {'mattn/webapi-vim'}
  use {'kyazdani42/nvim-tree.lua'}

  -- Post-install/update hook with neovim command
  use {
      'nvim-treesitter/nvim-treesitter', 
      run = ':TSUpdate',
      config = function() require("config/treesitter") end
  }

  use {'chr4/nginx.vim'}
  use {'cespare/vim-toml'}
  use {'elzr/vim-json'}
  use {'lu5je0/vim-java-bytecode'}
  use {'MTDL9/vim-log-highlighting'}

  use {
      'SirVer/ultisnips',
      opt = true,
      ft = 'markdown'
  }

  use {
      'othree/eregex.vim',
      opt = true,
      keys = '<leader>/',
      cmd = 'S'
  }

  use 'dstein64/vim-startuptime'
  use 'yianwillis/vimcdoc'
  use 'chrisbra/vim-diff-enhanced'
  use 'tpope/vim-commentary'
  use 'lu5je0/vim-snippets'
  use 'kana/vim-textobj-user'
  use 'tpope/vim-repeat'
  use 'vim-scripts/ReplaceWithRegister'
  use 'tommcdo/vim-exchange'
  use 'lu5je0/vim-base64'

  -- themes
  use 'tomasiser/vim-code-dark'
  use 'lu5je0/vim-one'
  use 'gruvbox-community/gruvbox'
  use 'hzchirs/vim-material'
  use 'ayu-theme/ayu-vim'
  use 'w0ng/vim-hybrid'

  -- " fern
  use {'lambdalisue/fern-hijack.vim'}
  use {
      'lambdalisue/fern.vim', 
      opt = true, 
      cmd = {'Fern'}, 
      requires = {
          {'yuki-yano/fern-preview.vim', opt = true},
          {'lambdalisue/nerdfont.vim', opt = true},
          {'lu5je0/fern-renderer-nerdfont.vim', opt = true},
          {'lambdalisue/glyph-palette.vim', opt = true},
          {'lambdalisue/fern-git-status.vim', opt = true}
      },
      config = function() vim.cmd('runtime plug-config/fern.vim') end
  }

  use {'Yggdroot/LeaderF',
      run = './install.sh', 
      opt = true,
      cmd = {'Leaderf'},
      config = function() vim.cmd('runtime plug-config/leaderf.vim') end
  }

  use {'mg979/vim-visual-multi',
      opt = true,
      keys = {'<c-n>', '<m-n>'}
  }

  use {'sgur/vim-textobj-parameter'}
  use {'mhinz/vim-signify'}
  use {'voldikss/vim-translator'}

  use {
      'tpope/vim-fugitive',
      opt = true,
      cmd = {'Git'}
  }

  use {'rbong/vim-flog'}

  use {
      'lu5je0/vim-terminal-help', 
      config = function() vim.cmd('runtime plug-config/terminal.vim') end,
      opt = true,
      keys = {'<m-i>', '<d-i>'}
  }

  use {
      'skywind3000/asyncrun.vim',
      opt = true,
      cmd = 'AsyncRun',
      requires = {
          {'skywind3000/asynctasks.vim', opt = true},
          {'skywind3000/asyncrun.extra', opt = true}
      },
  }

  use {'mbbill/undotree'}
  use {'junegunn/vim-peekaboo'}
  use {'tpope/vim-surround'}

  use {'liuchengxu/vista.vim', 
      config = function() vim.cmd('runtime plug-config/vista.vim') end,
      opt = true,
      keys = {'<leader>i'}
  }

  use {'machakann/vim-highlightedyank'}

  use {
      'lambdalisue/suda.vim',
      opt = true,
      cmd = {'SudaRead', 'SudaWrite'}
  }

  use {
      'iamcco/markdown-preview.nvim', 
      run = 'cd app && yarn install', 
      opt = true,
      cmd = 'MarkdownPreview'
  }
  -- use {'neoclide/coc.nvim', branch = 'release', config = function() vim.cmd('runtime plug-config/coc.vim') end}
  use {'liuchengxu/vim-which-key', 
      config = function() vim.cmd('runtime whichkey.vim') end,
      opt = true,
      keys = {'<leader>'}
  }

  -- if g:coc_enable == 1
  --     call s:lazy_load('neoclide/coc.nvim')
  -- else
  --     use 'ervandew/supertab'
  -- endif

end)
