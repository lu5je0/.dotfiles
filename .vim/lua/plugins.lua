-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
return require('packer').startup(function()
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'
  use {'akinsho/bufferline.nvim', config = function() require("config/bufferline") end}
  use 'kyazdani42/nvim-web-devicons'

  -- Use specific branch, dependency and run lua file after load
  use {'glepnir/galaxyline.nvim', branch = 'main', config = function() require("config/galaxyline") end}
  use {'jiangmiao/auto-pairs'}
  use {'schickling/vim-bufonly'}
  use {'theniceboy/vim-calc'}
  use {'rootkiter/vim-hexedit'}
  use {'mattn/vim-gist'}
  use {'mattn/webapi-vim'}

  -- Post-install/update hook with neovim command
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate', config = function() require("config/treesitter") end}
  use {'chr4/nginx.vim'}
  use {'cespare/vim-toml'}
  use {'elzr/vim-json'}
  use {'lu5je0/vim-java-bytecode'}
  use {'MTDL9/vim-log-highlighting'}
  use {'SirVer/ultisnips', ft = {'markdown'}}
  use {'othree/eregex.vim'}
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
  -- use 'lambdalisue/fern-hijack.vim'
  -- use {'lambdalisue/nerdfont.vim'}
  -- use {'lu5je0/fern-renderer-nerdfont.vim'}
  -- use {'lambdalisue/glyph-palette.vim'}
  -- use {'lambdalisue/fern-git-status.vim'}
  -- use {'yuki-yano/fern-preview.vim'}
  -- use {'lambdalisue/fern.vim', config = function() vim.cmd('runtime plug-config/fern.vim') end}

  use {'Yggdroot/LeaderF', run = './install.sh', config = function() vim.cmd('runtime plug-config/leaderf.vim') end}

  use {'mg979/vim-visual-multi'}
  use {'sgur/vim-textobj-parameter'}
  use {'mhinz/vim-signify'}
  use {'voldikss/vim-translator'}
  use {'tpope/vim-fugitive'}
  use {'rbong/vim-flog'}
  use {'lu5je0/vim-terminal-help', config = function() vim.cmd('runtime plug-config/terminal.vim') end}
  use {'skywind3000/asynctasks.vim'}
  use {'skywind3000/asyncrun.vim'}
  use {'skywind3000/asyncrun.extra'}
  use {'mbbill/undotree'}
  use {'junegunn/vim-peekaboo'}
  use {'tpope/vim-surround'}
  use {'liuchengxu/vista.vim', config = function() vim.cmd('runtime plug-config/vista.vim') end}
  use {'machakann/vim-highlightedyank'}
  use {'lambdalisue/suda.vim'}
  use {'iamcco/markdown-preview.nvim', run = 'cd app && yarn install', cmd = 'MarkdownPreview'}
  -- use {'neoclide/coc.nvim', branch = 'release', config = function() vim.cmd('runtime plug-config/coc.vim') end}
  use {'liuchengxu/vim-which-key', config = function() vim.cmd('runtime whichkey.vim') end}
  -- if g:coc_enable == 1
  --     call s:lazy_load('neoclide/coc.nvim')
  -- else
  --     use 'ervandew/supertab'
  -- endif

end)
