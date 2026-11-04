#!@bash@

# 仅为本次重建追加缓存；保留原有 NIX_CONFIG 和所有 nh 参数。
case "${1-} ${2-}" in
  "os build"|"os switch")
    if cache_info=$("@curl@" -fsS --max-time 1 \
      http://192.168.1.100:17500/nix-cache-info 2>/dev/null) \
      && [[ "$cache_info" == *"StoreDir: /nix/store"* ]]; then
      export NIX_CONFIG="${NIX_CONFIG-}"$'\n'"extra-substituters = http://192.168.1.100:17500?priority=30"
      echo 'nh: 使用 huskar 局域网缓存' >&2
    else
      echo 'nh: huskar 缓存不可用，使用原有缓存' >&2
    fi
    ;;
esac

exec "@nh@" "$@"
