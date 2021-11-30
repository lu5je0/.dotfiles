let g:python_vimspector = { 
    \   "launch": { 
    \     "adapter": "debugpy", 
    \     "configuration": { 
    \       "request": "launch", 
    \       "python3": "/usr/bin/python3", 
    \       "program": expand("%:p"),
    \       "console": "externalTerminal",
    \       "stopOnEntry": v:true,
    \       "breakpoints": {
    \         "exception": {
    \           "caught": "",
    \           "uncaught": ""
    \         }
    \       } 
    \     }
    \   }
    \ }

nmap <leader>rd :call vimspector#LaunchWithConfigurations(get(g:, 'python_vimspector'))<cr>
