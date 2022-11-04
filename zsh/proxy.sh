USER_HTTP_PROXY=${USER_HTTP_PROXY:-'http://127.0.0.1:1080'}
USER_SOCKS_PROXY=${USER_SOCKS_PROXY:-'socks5://127.0.0.1:1080'}

proxy() {
  export http_proxy=$USER_HTTP_PROXY
  export HTTP_PROXY=$USER_HTTP_PROXY
  export https_proxy=$USER_HTTP_PROXY
  export HTTPS_PROXY=$USER_HTTP_PROXY
}

unproxy() {
  unset http_proxy
  unset HTTP_PROXY
  unset https_proxy
  unset HTTPS_PROXY
}

git_ssh_proxy() {
  if [ "$(uname)" = "Darwin" ]; then
    gsed -i "s/# ProxyCommand/ProxyCommand/" ~/.ssh/config
    gsed -i -E "s/ProxyCommand nc -v -x [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ProxyCommand nc -v -x ${USER_SOCKS_PROXY}/" ~/.ssh/config
  else
    sed -i "s/# ProxyCommand/ProxyCommand/" ~/.ssh/config
    sed -i -E "s/ProxyCommand nc -v -x [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ProxyCommand nc -v -x ${USER_SOCKS_PROXY}/" ~/.ssh/config
  fi
}

git_ssh_unproxy() {
  if [ "$(uname)" = "Darwin" ]; then
    gsed -i "s/ProxyCommand/# ProxyCommand/" ~/.ssh/config
  else
    sed -i "s/ProxyCommand/# ProxyCommand/" ~/.ssh/config
  fi
}
