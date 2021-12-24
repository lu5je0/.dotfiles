let g:python_vimspector = {
    \   "launch": {
    \     "adapter": "debugpy",
    \     "configuration": {
    \       "request": "launch",
    \       "python3": "/usr/bin/python3",
    \       "program": expand("%:p"),
    \       "console": "externalTerminal",
    \       "stopOnEntry": v:true,
    \       "justMyCode": v:true,
    \       "breakpoints": {
    \         "exception": {
    \           "caught": "",
    \           "uncaught": ""
    \         }
    \       }
    \     }
    \   }
    \ }

nmap <expr> <buffer> <leader>rd filereadable(getcwd() .. '/' .. '.vimspector.json') ?
            \ ": call vimspector#Launch()\<cr>" :
            \ ":call vimspector#LaunchWithConfigurations(get(g:, 'python_vimspector'))\<cr>"
