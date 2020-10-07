set mouse=a
set hlsearch " 高亮搜索结果
set ignorecase " 搜索时忽略大小写
set incsearch " 每输入一个字符就跳转到对应的结果
set noerrorbells " 关闭错误响声
set clipboard+=unnamed " 使用系统剪切板
set splitbelow " 默认在下侧分屏
set splitright " 默认在右侧分屏
set t_Co=256 " 开启256颜色支持
set nowrap " 默认不启用拆行
set autoindent
set number
set laststatus=2
" set cursorline
" 缩进
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab

set encoding=utf8
set fileencoding=utf-8
set fileencodings=ucs-bom,utf-8,gb18030,utf-16,big5,ISO-8859,latin1
syntax on
set foldmethod=syntax
set foldlevelstart=99 " 打开文件默认不折叠
set termguicolors

" make the backspace work like in most other programs
set backspace=indent,eol,start
