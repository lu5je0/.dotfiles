
" arthas.vim - Simple syntax highlighting for Arthas commands
" File: ~/.config/nvim/syntax/arthas.vim

if exists("b:current_syntax")
  finish
endif

" 关键命令（Arthas 内置命令）
syn keyword arthasCommand
  \ dashboard thread jad classloader sc sm
  \ watch trace monitor tt
  \ ognl getstatic vmtool heapdump
  \ sysprop sysenv logger
  \ stop reset version help cls clear
  \ cat pwd session jobs kill

" 选项（支持短选项、长选项和 `--`）
syn match arthasOption /\(^\|\s\)\zs\(--[A-Za-z][A-Za-z0-9-]*\|--\|-[A-Za-z]\+\)\ze\(\s\|$\)/

" Java 类名（简单匹配：大写字母开头的点分格式）
syn match arthasClassName /\v<[A-Z][a-zA-Z0-9_]*(\.[A-Za-z0-9_]+)*>/

" 方法名（字母开头，含下划线/数字）
syn match arthasMethodName /\v<[a-z][a-zA-Z0-9_]*>/ contained

" 字符串（单引号和双引号）
syn region arthasString start=+"+ end=+"+ skip=+\\"+
syn region arthasString start=+'+ end=+'+ skip=+\\'+

" OGNL 表达式中的花括号内容（如 '{params, returnObj}'）
syn region arthasOgnlExpr start=/{/ end=/}/ contains=arthasString,arthasSpecial

" 特殊符号（如 * ? 等通配符）
syn match arthasSpecial /[*?]/

" 注释（// 开头）
syn match arthasComment /\/\/.*$/
highlight link arthasComment Comment

" 高亮链接
highlight link arthasCommand      Keyword
highlight link arthasOption       Identifier
highlight link arthasClassName    Type
highlight link arthasMethodName   Function
highlight link arthasString       String
highlight link arthasOgnlExpr     PreProc
highlight link arthasSpecial      Special

let b:current_syntax = "arthas"
