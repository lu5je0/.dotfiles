# 代理设置
alias proxy='export http_proxy=http://${HTTP_PROXY:-127.0.0.1:1080}; export https_proxy=http://${HTTP_PROXY:-127.0.0.1:1080};'
alias unproxy='unset http_proxy; unset https_proxy'
alias pc='proxychains4 -q'
