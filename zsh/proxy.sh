proxy() {
    if [[ $(uname -r) == *WSL2* ]]; then
        # export HOST_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{ print $2 }')
        # export HOST_IP=$(cat /mnt/wsl/resolv.conf | grep nameserver | awk '{ print $2 }')
        export HOST_IP='p775.local'
    fi

    export http_proxy="http://${HOST_IP:-127.0.0.1}:${HTTP_PROXY_PORT:-1080}"
    export HTTP_PROXY="http://${HOST_IP:-127.0.0.1}:${HTTP_PROXY_PORT:-1080}"

    export https_proxy="http://${HOST_IP:-127.0.0.1}:${HTTP_PROXY_PORT:-1080}"
    export HTTPS_PROXY="http://${HOST_IP:-127.0.0.1}:${HTTP_PROXY_PORT:-1080}"
}

git_ssh_proxy() {
    if [[ $(uname -r) == *WSL2* ]]; then
        # export HOST_IP=$(cat /etc/resolv.conf | grep nameserver | awk '{ print $2 }')
        # export HOST_IP=$(cat /mnt/wsl/resolv.conf | grep nameserver | awk '{ print $2 }')
        export HOST_IP='p775.local'
    fi

    if [ "$(uname)" = "Darwin" ]; then
        gsed -i "s/# ProxyCommand/ProxyCommand/" ~/.ssh/config
        gsed -i -E "s/ProxyCommand nc -v -x [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ProxyCommand nc -v -x ${HOST_IP:-127.0.0.1}:${SOCKS5_PROXY_PORT:-1080}/" ~/.ssh/config
    else
        sed -i "s/# ProxyCommand/ProxyCommand/" ~/.ssh/config
        sed -i -E "s/ProxyCommand nc -v -x [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ProxyCommand nc -v -x ${HOST_IP:-127.0.0.1}:${SOCKS5_PROXY_PORT:-1080}/" ~/.ssh/config
    fi
}

git_ssh_unproxy() {
    if [ "$(uname)" = "Darwin" ]; then
        gsed -i "s/ProxyCommand/# ProxyCommand/" ~/.ssh/config
    else
        sed -i "s/ProxyCommand/# ProxyCommand/" ~/.ssh/config
    fi
}

unproxy() {
    unset http_proxy
    unset HTTP_PROXY

    unset https_proxy
    unset HTTPS_PROXY


}

