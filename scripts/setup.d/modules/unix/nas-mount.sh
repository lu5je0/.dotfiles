#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != Linux ]; then
    echo "skip: 仅支持 Linux（cifs + systemd automount），当前 $(uname -s)"
    exit 0
fi

NAS_HOST="${NAS_HOST:-192.168.1.10}"
NAS_USER="${NAS_USER:-admin}"
NAS_PASS="${NAS_PASS:-lu5je0}"
SHARES=(st2000 mg08 share)

FSTAB=/etc/fstab
BACKUP=/etc/fstab.nas-mount.bak
BEGIN_MARK='# >>> dotfiles nas-mount >>>'
END_MARK='# <<< dotfiles nas-mount <<<'
OPTS="username=$NAS_USER,password=$NAS_PASS,uid=$(id -u),gid=$(id -g),vers=3.1.1,_netdev,soft,noatime,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=600,x-systemd.mount-timeout=15"

# 挂载点：确保存在，并在「确认未挂载」的前提下锁成 root:root 555，
# 这样 automount 没起来时写入直接 EACCES，不会静默落到本地盘。
# autofs 挂上后路径查找命中 autofs 的 root inode，底层权限被遮住，不影响触发挂载。
# 挂载状态下改权限会打到 NAS 共享根目录上，所以 mountpoint 判断是硬前提。
for s in "${SHARES[@]}"; do
    d="/mnt/$s"
    if [ -e "$d" ] && [ ! -d "$d" ]; then
        echo "error: $d 已存在且不是目录" >&2
        exit 1
    fi
    if [ ! -d "$d" ]; then
        echo "mkdir $d"
        sudo mkdir -p "$d"
    fi

    if mountpoint -q "$d"; then
        echo "skip: $d 已有挂载，不动权限"
        continue
    fi

    if [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
        echo "warn: $d 未挂载但非空，挂载后这些文件会被遮住" >&2
    fi

    if [ "$(stat -c '%U:%G %a' "$d")" = "root:root 555" ]; then
        echo "skip: $d 权限已就位"
    else
        sudo chown root:root "$d"
        sudo chmod 555 "$d"
        echo "protected $d (root:root 555)"
    fi
done

# 生成候选 fstab：剔掉旧的 marker block 和任何指向这些挂载点的历史行，再追加新 block
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

targets=" "
for s in "${SHARES[@]}"; do targets+="/mnt/$s "; done

awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v t="$targets" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    /^[[:space:]]*#/ { print; next }
    NF >= 2 && index(t, " " $2 " ") { next }
    { print }
' "$FSTAB" >"$tmp"

{
    echo "$BEGIN_MARK"
    for s in "${SHARES[@]}"; do
        echo "//$NAS_HOST/$s  /mnt/$s  cifs  $OPTS  0 0"
    done
    echo "$END_MARK"
} >>"$tmp"

# 校验通过才落盘，避免把坏的 fstab 写进系统
if ! findmnt --verify --tab-file "$tmp" >/dev/null 2>&1; then
    echo "error: 生成的 fstab 校验失败，未做任何改动" >&2
    findmnt --verify --tab-file "$tmp" >&2 || true
    exit 1
fi

if cmp -s "$tmp" "$FSTAB"; then
    echo "skip: $FSTAB 已是最新"
else
    sudo cp -a "$FSTAB" "$BACKUP"
    sudo install -o root -g root -m 644 "$tmp" "$FSTAB"
    echo "updated $FSTAB (backup: $BACKUP)"
fi

# 迁移：干掉被 automount 取代的旧 service
if [ -e /etc/systemd/system/wsl-mount.service ] || [ -e /usr/lib/systemd/system/wsl-mount.service ]; then
    echo "removing legacy wsl-mount.service"
    sudo systemctl disable --now wsl-mount.service || true
    sudo rm -f /etc/systemd/system/wsl-mount.service /usr/lib/systemd/system/wsl-mount.service
fi
sudo systemctl reset-failed wsl-mount.service 2>/dev/null || true

sudo systemctl daemon-reload

units=()
for s in "${SHARES[@]}"; do
    units+=("$(systemd-escape -p --suffix=automount "/mnt/$s")")
done
sudo systemctl start "${units[@]}"

ok=1
for u in "${units[@]}"; do
    state="$(systemctl is-active "$u" 2>/dev/null || true)"
    printf '  %-22s %s\n' "$u" "$state"
    [ "$state" = active ] || ok=0
done

if ! findmnt --verify --fstab >/dev/null 2>&1; then
    echo "error: $FSTAB 校验失败" >&2
    exit 1
fi

if [ "$ok" != 1 ]; then
    echo "error: 有 automount 未启动" >&2
    exit 1
fi

echo "done: 访问 /mnt/{$(
    IFS=,
    echo "${SHARES[*]}"
)} 时自动挂载，闲置 600s 自动卸载"
