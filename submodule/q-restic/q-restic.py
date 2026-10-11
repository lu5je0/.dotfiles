#!/usr/bin/env python3
"""q-restic —— 把 home 增量备份到 NAS 的 restic 前端，带 TUI。

设计要点:
  * 仓库走 SFTP 而不是直接写 CIFS 挂载点。restic 依赖 fsync + rename 原子性，
    而 fstab 里的 CIFS 用了 soft + cache=strict，NAS 卡顿时会返回 EIO 而不是等待，
    这正是会写坏仓库的语义。NAS 侧 /mnt/mg08 是 ext4，POSIX 语义完整。
  * 不加 --one-file-system。/home 下没有嵌套挂载点，加了只会平白跳过东西。
  * 只读操作（status / mount / browse / unmount）不占用备份锁，
    所以备份跑着的时候照样能查状态、能挂载浏览。
  * restic 必须已经在 PATH 里（不再用 nix build 兜底），由 nix/modules/restic-home.nix
    把 pkgs.restic 装进系统 profile。
"""

import argparse
import atexit
import base64
import fcntl
import hashlib
import json
import os
import select
import shutil
import signal
import subprocess
import sys
import termios
import threading
import time
import tty
import unicodedata
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "q-restic"
CONFIG_FILE = CONFIG_DIR / "config.json"

DEFAULT_CONFIG = {
    "repository": "sftp:lu5je0@192.168.1.10:/mnt/mg08/backups/restic/huskar",
    "password_file": str(HOME / ".config/restic/password"),
    "source": str(HOME),
    "excludes": str(PROJECT_DIR / "excludes.txt"),
    "host": "",
    "tag": "home",
    "mount_dir": "/tmp/restic-mnt",
    "restore_dir": str(HOME / "restic-restore"),
    "keep": {"hourly": 0, "daily": 7, "weekly": 4, "monthly": 1, "yearly": 0},
}


def die(msg, code=1):
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg):
    print(f"==> {msg}")


def warn(msg):
    print(f"警告: {msg}", file=sys.stderr)


# ── 配置 ──────────────────────────────────────────────────────────────


def load_config():
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))  # deep copy
    if CONFIG_FILE.exists():
        try:
            disk = json.loads(CONFIG_FILE.read_text())
        except (OSError, ValueError) as exc:
            die(f"配置文件损坏: {CONFIG_FILE} ({exc})")
        for key, value in disk.items():
            if key == "keep" and isinstance(value, dict):
                cfg["keep"].update(value)
            else:
                cfg[key] = value
    if not cfg.get("host"):
        cfg["host"] = subprocess.run(
            ["hostname", "-s"], capture_output=True, text=True
        ).stdout.strip() or "localhost"
    return cfg


def save_config(cfg):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")


def expand(path):
    return Path(os.path.expandvars(str(path))).expanduser()


# ── restic 调用 ───────────────────────────────────────────────────────


def restic_bin():
    """restic 必须已经在 PATH 里。

    不用 `nix build nixpkgs#restic` 兜底：那会在每次调用时求值 flake，
    在没有网络或 /nix 不可用的场景（systemd 服务）里会失败，也拖慢每次启动；
    而 nix/modules/restic-home.nix 已经把 pkgs.restic 装进系统 profile。
    """
    found = shutil.which("restic")
    if not found:
        die(
            "PATH 里找不到 restic。\n"
            "  系统配置已包含它，跑一次 sudo nixos-rebuild switch 即可；\n"
            "  或临时安装：nix profile install nixpkgs#restic"
        )
    return found


def restic_env(cfg):
    env = dict(os.environ)
    env["RESTIC_REPOSITORY"] = cfg["repository"]
    env["RESTIC_PASSWORD_FILE"] = str(expand(cfg["password_file"]))
    env["RESTIC_CACHE_DIR"] = str(Path(env.get("XDG_CACHE_HOME") or HOME / ".cache") / "restic")
    env.setdefault("RESTIC_PROGRESS_FPS", "1")
    return env


def host_args(cfg):
    """按主机过滤快照。注意只有部分子命令支持 --host：
    snapshots/stats/forget/restore/mount 支持，diff/check 不支持（传了会直接报错）。
    """
    return ["--host", cfg["host"]] if cfg.get("host") else []


def run(restic, cfg, args, capture=True, check=False):
    cmd = [restic] + args
    return subprocess.run(
        cmd,
        env=restic_env(cfg),
        capture_output=capture,
        text=True,
        check=check,
    )


def run_json(restic, cfg, args):
    res = run(restic, cfg, args)
    if res.returncode != 0:
        return None
    try:
        return json.loads(res.stdout)
    except ValueError:
        return None


def run_stream(restic, cfg, args):
    """直接继承终端，让 restic 自己的进度条可见。"""
    return subprocess.call([restic] + args, env=restic_env(cfg))


def require_password(cfg):
    path = expand(cfg["password_file"])
    if not path.is_file():
        die(
            f"密码文件不存在: {path}\n"
            f"创建方法:\n"
            f"  install -d -m700 {path.parent}\n"
            f"  printf '%s' '你的仓库密码' > {path}\n"
            f"  chmod 600 {path}"
        )
    mode = path.stat().st_mode & 0o777
    if mode & 0o077:
        warn(f"密码文件权限是 {mode:o}，建议 chmod 600 {path}")


# ── 防并发（只保护会写仓库的流程）──────────────────────────────────────

_LOCK_FD = None


def acquire_lock(cfg):
    """按仓库区分锁：同一仓库串行，不同目标可并行。

    路径必须与执行环境无关 —— 交互 shell 有 XDG_RUNTIME_DIR，
    systemd 服务里没有，用它做前缀会让两边拿到不同的锁。
    """
    global _LOCK_FD
    digest = hashlib.sha256(cfg["repository"].encode()).hexdigest()[:12]
    lock_path = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / f"q-restic.{digest}.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    _LOCK_FD = open(lock_path, "w")
    try:
        fcntl.flock(_LOCK_FD, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        die(f"另一次备份正在运行（{lock_path}），本次退出")


# ── 具体命令 ──────────────────────────────────────────────────────────


def repo_ready(restic, cfg):
    return run(restic, cfg, ["cat", "config"]).returncode == 0


def preflight_sftp(cfg, quiet=False):
    """SFTP 目标预检：路径存在且可写，避免跑一半才发现写不进去。"""
    repo = cfg["repository"]
    if not repo.startswith("sftp:"):
        return
    rest = repo[len("sftp:") :]
    userhost, _, path = rest.partition(":")
    if not userhost or not path:
        return
    if not quiet:
        info(f"预检 NAS 目标 {userhost}:{path}")
    res = subprocess.run(
        [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=yes",
            userhost,
            f"mkdir -p '{path}' && test -w '{path}'",
        ],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        die(f"NAS 目标不可写或不可达: {userhost}:{path}\n  排查: ssh {userhost}")


def ensure_repo(restic, cfg):
    if not repo_ready(restic, cfg):
        info(f"初始化仓库 {cfg['repository']}")
        if run_stream(restic, cfg, ["init"]) != 0:
            die("仓库初始化失败")


def do_backup(cfg, dry_run=False):
    restic = restic_bin()
    require_password(cfg)
    acquire_lock(cfg)
    preflight_sftp(cfg)
    ensure_repo(restic, cfg)

    args = ["backup", cfg["source"], "--exclude-file", str(expand(cfg["excludes"])), "--exclude-caches"]
    args += ["--host", cfg["host"], "--tag", cfg["tag"]]
    if dry_run:
        args += ["--dry-run", "--verbose"]
        info(f"试运行 {cfg['source']} → {cfg['repository']}")
        code = run_stream(restic, cfg, args)
        info("dry-run 结束，仓库未改动")
        return code
    info(f"备份 {cfg['source']} → {cfg['repository']}")
    if run_stream(restic, cfg, args) != 0:
        return 1
    do_forget(restic, cfg, stream=True)
    info("完成")
    return 0


def keep_args(cfg):
    keep = cfg["keep"]
    args = []
    for name in ("hourly", "daily", "weekly", "monthly", "yearly"):
        count = int(keep.get(name, 0) or 0)
        if count > 0:
            args += [f"--keep-{name}", str(count)]
    return args


def do_forget(restic, cfg, stream=True):
    args = ["forget"] + keep_args(cfg) + ["--prune"] + host_args(cfg)
    if not keep_args(cfg):
        warn("保留策略全为 0，跳过 forget（等同于全部保留）")
        return 0
    info("应用保留策略: " + " ".join(keep_args(cfg)))
    if stream:
        return run_stream(restic, cfg, args)
    return run(restic, cfg, args).returncode


def do_check(cfg):
    restic = restic_bin()
    require_password(cfg)
    info("仓库完整性校验（读 5% 数据）")
    # check 不支持 --host，不要加主机过滤
    return subprocess.call(
        [restic, "check", "--read-data-subset=5%"], env=restic_env(cfg)
    )


def snap_time_key(snap):
    """restic 给纳秒精度的时间戳，Python 3.9 的 fromisoformat 不接受，
    所以截到秒做字典序排序（同一主机的快照时区一致）。"""
    return str(snap.get("time", ""))[:19]


def snapshots(restic, cfg):
    data = run_json(restic, cfg, ["snapshots", "--json"] + host_args(cfg))
    return sorted(data or [], key=snap_time_key)


def snapshot_stats(restic, cfg):
    return run_json(restic, cfg, ["stats", "--json", "latest"] + host_args(cfg))


def repo_stats(restic, cfg):
    """全仓库的实际占用（raw-data，不看 latest）。"""
    return run_json(restic, cfg, ["stats", "--json", "--mode", "raw-data"] + host_args(cfg))


def do_status(cfg):
    restic = restic_bin()
    require_password(cfg)
    snaps = snapshots(restic, cfg)
    info(f"仓库 {cfg['repository']}")
    if not snaps:
        print("还没有任何版本。跑一次 `q-restic backup` 开始。")
        return 0
    print(f"{'ID':<10} {'时间':<20} {'数据量':>10} {'新增':>10}  标签")
    print("-" * 68)
    for snap in snaps:
        print(
            f"{snap['short_id']:<10} {snap['time'][:19].replace('T', ' '):<20} "
            f"{human_size(snap_size(snap)):>10} {human_size(snap_added(snap)):>10}  "
            f"{','.join(snap.get('tags') or [])}"
        )
    latest = run_json(restic, cfg, ["stats", "--json", "latest"] + host_args(cfg))
    repo = repo_stats(restic, cfg)
    print()
    if latest:
        print(
            f"共 {len(snaps)} 个版本；最新版本文件总量 "
            f"{human_size(latest.get('total_size', 0))}"
            f"（{latest.get('total_file_count', 0)} 个文件）"
        )
    if repo:
        print(
            f"仓库实际占用 {human_size(repo.get('total_size', 0))}"
            f"（压缩比 {repo.get('compression_ratio', 0):.2f}x，"
            f"未压缩 {human_size(repo.get('total_uncompressed_size', 0))}）"
        )
    return 0


def snap_size(snap):
    """该版本源数据的总量。注意 restic 的 summary 里没有 total_size，
    那个名字只存在于 `restic stats` 的输出。"""
    return (snap.get("summary") or {}).get("total_bytes_processed", 0)


def snap_added(snap):
    """该版本实际写进仓库的字节数（已压缩）。"""
    summary = snap.get("summary") or {}
    return summary.get("data_added_packed", summary.get("data_added", 0))


def human_size(num):
    step = 1024.0
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(num) < step or unit == "TiB":
            return f"{num:.0f} {unit}" if unit == "B" else f"{num:.1f} {unit}"
        num /= step


# ── 挂载 / 浏览 ───────────────────────────────────────────────────────


def mount_point(cfg, override=None):
    return expand(override or cfg["mount_dir"])


def require_fuse():
    if not shutil.which("fusermount3") and not shutil.which("fusermount"):
        die("找不到 fusermount3/fusermount，无法挂载（FUSE 未装或不在 PATH）")
    if not os.access("/dev/fuse", os.R_OK):
        die("/dev/fuse 不可读，FUSE 内核模块没加载？")


def is_mounted(path):
    try:
        return subprocess.run(
            ["mountpoint", "-q", str(path)], capture_output=True
        ).returncode == 0
    except FileNotFoundError:
        return False


def do_mount(cfg, override=None):
    restic = restic_bin()
    require_password(cfg)
    require_fuse()
    target = mount_point(cfg, override)
    target.mkdir(parents=True, exist_ok=True)
    if is_mounted(target):
        die(f"{target} 已经是挂载点，先跑 q-restic unmount")
    info(f"只读挂载到 {target}（前台，Ctrl-C 结束）")
    info(f"版本目录: {target}/snapshots/   卸载: q-restic unmount")
    return subprocess.call(
        [restic, "mount", str(target)] + host_args(cfg), env=restic_env(cfg)
    )


def do_browse(cfg, override=None):
    restic = restic_bin()
    require_password(cfg)
    require_fuse()
    target = mount_point(cfg, override)
    target.mkdir(parents=True, exist_ok=True)
    if not is_mounted(target):
        state = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "q-restic"
        state.mkdir(parents=True, exist_ok=True)
        logf = state / "mount.log"
        info(f"后台挂载到 {target}（日志: {logf}）")
        with open(logf, "w") as handle:
            subprocess.Popen(
                [restic, "mount", str(target)] + host_args(cfg),
                env=restic_env(cfg),
                stdout=handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        for _ in range(60):
            if is_mounted(target):
                break
            time.sleep(0.25)
        if not is_mounted(target):
            die(f"挂载失败，看日志: {logf}")
    snapdir = target / "snapshots"
    info(f"用文件管理器打开 {snapdir}/")
    if shutil.which("xdg-open"):
        subprocess.Popen(
            ["xdg-open", str(snapdir)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    info("卸载: q-restic unmount")
    return 0


def do_restore(cfg, snapshot, target=None):
    """恢复到指定目录。默认目录来自配置的 restore_dir。

    不默认写 /tmp：备份源是整个 home（可能上百 G），而 /tmp 在根文件系统上，
    既可能撑爆根分区，恢复出来的东西也不在合理的位置。
    """
    restic = restic_bin()
    require_password(cfg)
    dest = expand(target) if target else expand(cfg["restore_dir"]) / snapshot
    info(f"恢复 {snapshot} 到 {dest}")
    info(f"恢复完成后文件在以 {dest}/home/lu5je0/ 为根的目录树里")
    return subprocess.call(
        [restic, "restore", snapshot, "--target", str(dest)] + host_args(cfg),
        env=restic_env(cfg),
    )


def do_unmount(cfg, override=None):
    target = mount_point(cfg, override)
    if not is_mounted(target):
        info(f"{target} 未挂载，无需卸载")
        return 0
    for cmd in (["fusermount3", "-u"], ["fusermount", "-u"], ["umount"]):
        if shutil.which(cmd[0]) and subprocess.call(cmd + [str(target)]) == 0:
            info(f"已卸载 {target}")
            return 0
    die(f"卸载失败，可能还有程序在用 {target}")


# ── kitty IME 闸门 ────────────────────────────────────────────
# 这个 kitty fork 支持按 window 彻底旁路输入法（见 fork 的 AGENTS.md
# 「特性：按 window 彻底禁用输入法」）：
#
#   OSC 1337 ; SetUserVar=tui-bridge=<base64 of {"id":1,"module":"ime",
#                                             "method":"normal"|"insert","params":{}}> BEL
#
# `normal` 关闸（IME 完全收不到按键，无候选窗、无 preedit），`insert` 开闸。
# 字节与 nvim 的 osc backend、zsh 的 vi-im-switch 完全一致，kitty 在 C 层
# （vt-parser.c）直接识别，不经过任何子进程。
#
# 关键约束：kitty 是**旁路** IME 而不是切输入源，留着关闸状态出去，用户手动
# 切输入源也救不回来（逃生阀是 kitty.conf 里的 `ctrl+b>i enable_ime`）。
# 所以每条退出路径都必须开闸：正常退出、异常、SIGTERM/SIGHUP/SIGQUIT，
# 以及 Ctrl-Z 挂起期间。
#
# q-restic 全程只做导航、不需要输入法，关闸后 j/k/g/G 也不会被输入法吃掉。

IME_OSC = {
    method: "\x1b]1337;SetUserVar=tui-bridge="
    + base64.b64encode(
        json.dumps(
            {"id": 1, "module": "ime", "method": method, "params": {}},
            separators=(",", ":"),
        ).encode()
    ).decode()
    + "\x07"
    for method in ("normal", "insert")
}


def tmux_wrap(osc):
    """tmux 会吞掉 OSC 1337，必须用 DCS passthrough 包一层（内层 ESC 加倍）。

    依赖 tmux 的 `set -g allow-passthrough on`。和 nvim/zsh 侧同一套包装。
    """
    return "\x1bPtmux;" + osc.replace("\x1b", "\x1b\x1b") + "\x1b\\"


def terminal_is_kitty():
    """是否在会认这个 OSC 的 kitty 窗口里。

    只认 xterm-kitty，避免往其它终端乱写私有序列。tmux 会把 TERM 改成自己的
    terminfo，所以要问 tmux 客户端真实的终端名（与 nvim 的 is_kitty() 同一套判断）。
    """
    if os.environ.get("TERM") == "xterm-kitty":
        return True
    if not os.environ.get("TMUX"):
        return False
    tmux = shutil.which("tmux")
    if not tmux:
        return False
    try:
        result = subprocess.run(
            [tmux, "display-message", "-p", "#{client_termname}"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.stdout.strip() == "xterm-kitty"


class KittyIMEGate:
    """进入 TUI 时关掉 kitty 的 IME 闸门，退出时开闸。

    "退出"含正常退出、抛异常、收到终止信号与 Ctrl-Z 挂起，因为关着闸出去
    用户就再也打不出中文了。所有路径都幂等，重复调用安全。
    """

    def __init__(self, enabled=True):
        self.supported = bool(enabled) and terminal_is_kitty()
        self.armed = False          # 闸门当前是否由我们关着
        # Q_RESTIC_IME_DEBUG=<file> 时把每次开关记一笔，方便验证退出路径
        self.log_path = os.environ.get("Q_RESTIC_IME_DEBUG")
        self._installed = False

    # -- 输出 --

    def _emit(self, method):
        osc = IME_OSC[method]
        if os.environ.get("TMUX"):
            osc = tmux_wrap(osc)
        if self.log_path:
            try:
                with open(self.log_path, "a") as handle:
                    handle.write(f"{time.monotonic():.3f} {method} armed={self.armed}\n")
            except OSError:
                pass
        # 直接写 fd 1：TUI 的 stdout 是缓冲的，而且解释器退出阶段也可能已经不可用，
        # 这条序列晚到或丢失就意味着用户打不出字。
        try:
            os.write(sys.stdout.fileno(), osc.encode())
        except (OSError, ValueError):
            pass

    # -- 状态 --

    def disable(self):
        """关闸（幂等）。"""
        if not self.supported or self.armed:
            return
        self.armed = True
        self._emit("normal")

    def restore(self):
        """开闸。没关过就什么都不做，可重复调用。"""
        if not self.supported or not self.armed:
            return
        self.armed = False
        self._emit("insert")

    def reassert(self):
        """重新关闸：子进程（nvim、restic）可能已经把闸门改成开着的。"""
        if not self.supported:
            return
        self.armed = True
        self._emit("normal")

    # -- 生命周期 --

    def install(self):
        """把开闸挂到所有能挂的退出路径上。"""
        if not self.supported or self._installed:
            return
        self._installed = True
        atexit.register(self.restore)
        for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT):
            self._set_handler(sig, self._on_fatal)
        # Ctrl-Z：挂起期间 shell 要能正常用，所以先开闸，resume 后再关闸
        if hasattr(signal, "SIGTSTP"):
            self._set_handler(signal.SIGTSTP, self._on_suspend)

    @staticmethod
    def _set_handler(sig, handler):
        try:
            signal.signal(sig, handler)
        except (OSError, ValueError):
            pass  # 非主线程或平台不支持

    def _on_fatal(self, signum, _frame):
        self.restore()
        # 还原默认处置再自杀，退出码/信号语义与未拦截时保持一致
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)

    def _on_suspend(self, signum, _frame):
        self.restore()
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)      # 真的挂起；收到 SIGCONT 后从这里继续
        signal.signal(signum, self._on_suspend)
        self.reassert()


# ── TUI 基础设施（对齐 setup.py 的实现方式）─────────────────────────────


def frame_size():
    size = shutil.get_terminal_size(fallback=(80, 24))
    return size, max(20, size.columns)


def wlen(text):
    """终端显示宽度：CJK 算 2 列。"""
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def fit(text, width):
    if width <= 0:
        return ""
    if wlen(text) <= width:
        return text
    out, used = [], 0
    for ch in text:
        step = 2 if unicodedata.east_asian_width(ch) in "WF" else 1
        if used + step > width - 1:
            break
        out.append(ch)
        used += step
    return "".join(out) + "…"


def pad(text, width):
    return text + " " * max(0, width - wlen(text))


def split_wide(text, width):
    """把一段按显示宽度硬切（给放不下的长 token 用）。"""
    parts, current, used = [], "", 0
    for ch in text:
        step = 2 if unicodedata.east_asian_width(ch) in "WF" else 1
        if used + step > width and current:
            parts.append(current)
            current, used = "", 0
        current += ch
        used += step
    if current:
        parts.append(current)
    return parts


def wrap_text(text, width):
    """fit() 的折行版：不断内容，只换行。

    空格处可以断；单个超宽 token（比如 sftp URL）用 split_wide() 硬切。
    """
    if width <= 0:
        return [text]
    lines = []
    for paragraph in str(text).split("\n"):
        current = ""
        for word in paragraph.split():
            candidate = f"{current} {word}" if current else word
            if wlen(candidate) <= width:
                current = candidate
                continue
            if current:
                lines.append(current)
                current = ""
            if wlen(word) > width:
                chunks = split_wide(word, width)
                lines.extend(chunks[:-1])
                current = chunks[-1]
            else:
                current = word
        lines.append(current)
    return lines


if sys.stdout.isatty() and not os.environ.get("NO_COLOR"):
    RESET, BOLD, DIM = "\033[0m", "\033[1m", "\033[2m"
    CYAN, GREEN, YELLOW, RED, MAGENTA = (
        "\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[35m"
    )
    CURSOR_BG, KEEP_BG = "\033[48;5;237m", "\033[22;39m"
else:
    RESET = BOLD = DIM = CYAN = GREEN = YELLOW = RED = MAGENTA = ""
    CURSOR_BG = KEEP_BG = ""


class Terminal:
    """进/出备用屏 + cbreak 的上下文管理器。"""

    def __init__(self, gate=None):
        self.fd = sys.stdin.fileno()
        self.saved = None
        # IME 闸门：每次把终端从子进程手里收回来都要重新关一次
        self.gate = gate

    def __enter__(self):
        self.saved = termios.tcgetattr(self.fd)
        sys.stdout.write("\033[?1049h\033[?25l")
        sys.stdout.flush()
        tty.setcbreak(self.fd)
        return self

    def __exit__(self, *exc):
        termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()
        return False

    def suspend(self):
        """临时把终端交还给子进程（跑 restic、开编辑器）。"""
        termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()

    def resume(self):
        sys.stdout.write("\033[?1049h\033[?25l")
        sys.stdout.flush()
        tty.setcbreak(self.fd)
        if self.gate:
            # 子进程自己动过闸门（nvim 退出时会发 insert 开闸），拿回终端时重关一次
            self.gate.reassert()

    def wait_key(self, prompt="按任意键返回"):
        print(f"\n{DIM}{prompt}{RESET}", end="", flush=True)
        read_key(self.fd)


def read_char(fd):
    data = os.read(fd, 1)
    if not data:
        return ""
    length = 1
    lead = data[0]
    if lead >= 0xF0:
        length = 4
    elif lead >= 0xE0:
        length = 3
    elif lead >= 0xC0:
        length = 2
    while len(data) < length:
        if not select.select([fd], [], [], 0.1)[0]:
            break
        data += os.read(fd, 1)
    return data.decode("utf-8", "replace")


# 方向键 / Home / End / PgUp / PgDn 的 CSI 序列（ESC [ 或 ESC O 之后的部分）
CSI_KEYS = {
    "A": "UP", "B": "DOWN", "C": "RIGHT", "D": "LEFT",
    "H": "HOME", "F": "END",
    "1~": "HOME", "4~": "END", "7~": "HOME", "8~": "END",
    "5~": "PGUP", "6~": "PGDN", "3~": "DELETE",
}


def read_key(fd):
    def pending(timeout):
        return bool(select.select([fd], [], [], timeout)[0])

    char = read_char(fd)
    if char == "\x1b":
        if not pending(0.02):
            return "ESC"
        if os.read(fd, 1) not in (b"[", b"O") or not pending(0.02):
            return "ESC"
        # 收齐 CSI 序列剩余字节：可能是 "A"，也可能是 "5~" / "1;5C" 这类
        seq = ""
        while len(seq) < 8 and pending(0.02):
            seq += os.read(fd, 1).decode("utf-8", "replace")
            if seq[-1].isalpha() or seq[-1] == "~":
                break
        return CSI_KEYS.get(seq, "")
    if char in ("\r", "\n"):
        return "ENTER"
    if char in ("\x7f", "\x08"):
        return "BACKSPACE"
    if char == " ":
        return "SPACE"
    return char


# ── TUI 界面 ──────────────────────────────────────────────────────────


class App:
    def __init__(self, cfg, gate=None):
        self.cfg = cfg
        self.gate = gate
        self.restic = restic_bin()
        self.snaps = []
        self.loading = False
        self.message = ""
        self.cursor = 0
        self.offset = 0
        self.screen = "menu"
        self.history = []
        self.last_size = None

    # -- 数据 --
    def refresh(self):
        """同步刷新（执行完动作之后用）。"""
        self.snaps = snapshots(self.restic, self.cfg)
        self.loading = False

    def start_load(self):
        """后台拉版本列表：启动时不要卡在 SFTP 往返上，先把界面画出来。

        这里不再调 `restic stats latest`。它冷缓存下要 4 秒多（要遍历 44 万个文件），
        而界面需要的信息（最新版本数据量）在 `snapshots --json` 的 summary 里已经有了。
        """
        self.loading = True

        def worker():
            try:
                self.snaps = snapshots(self.restic, self.cfg)
            except Exception as exc:  # 后台线程里抛异常会静默丢失
                self.message = f"读取仓库失败: {exc}"
            finally:
                self.loading = False

        threading.Thread(target=worker, daemon=True).start()

    def latest(self):
        return self.snaps[-1] if self.snaps else None

    def set_message(self, text):
        self.message = text

    # -- 渲染 --
    def header(self, width):
        title = "q-restic"
        if self.loading:
            right = "读取仓库中…"
        else:
            right = f"{len(self.snaps)} 个版本"
            if self.latest():
                right += f" · 最新 {self.latest()['time'][:16].replace('T', ' ')}"
        for candidate in (right, f"{len(self.snaps)} 个版本", ""):
            if wlen(title) + wlen(candidate) + 3 <= width:
                right = candidate
                break
        gap = " " * max(1, width - 2 - wlen(title) - wlen(right))
        return [
            f"  {BOLD}{CYAN}{title}{RESET}{gap}{DIM}{right}{RESET}",
            f"  {DIM}{'─' * (width - 2)}{RESET}",
        ]

    def detail_text(self):
        """当前屏的上下文说明。渲染在底部，见 footer()。"""
        if self.screen == "menu":
            text = self.cfg["repository"]
            latest = self.latest()
            if latest:
                text += f" · 最新版本数据量 {human_size(snap_size(latest))}"
            return text
        if self.screen == "snapshots":
            return "选中一个版本后按 Enter，进入该版本的操作"
        snap = self.selected_snap()
        if snap is None:
            return ""
        return (
            f"{snap['short_id']} · {snap['time'][:19].replace('T', ' ')} · "
            f"{human_size(snap_size(snap))} · {snap_size(snap)} bytes"
        )

    def footer(self, width):
        rule = f"  {DIM}{'─' * (width - 2)}{RESET}"
        lines = [""]
        # 上下文说明放底部：仓库 URL 这行很长，挤在头部会把正文往下压，
        # 放底部且折行（wrap_text）后既不影响正文，也不会被截断。
        detail = self.detail_text()
        if detail:
            for chunk in wrap_text(detail, width - 2):
                lines.append(f"  {DIM}{chunk}{RESET}")
        lines.append(rule)
        if self.message:
            lines.append(f"  {YELLOW}{fit(self.message, width - 3)}{RESET}")
            return lines
        base = [("↑↓/jk", "移动"), ("enter", "选择")]
        if self.screen == "menu":
            ladders = [base + [("q", "退出")], base, [("jk", "移动"), ("enter", "选择")]]
        else:
            ladders = [
                base + [("g/G", "首尾"), ("esc", "返回")],
                base + [("esc", "返回")],
                [("jk", "移动"), ("enter", "选择"), ("esc", "返回")],
            ]
        # 逐级降级，直到能完整放下（setup.py 的 hints() 用的同一思路）
        for keys in ladders + [[(k, "") for k, _ in ladders[-1]]]:
            plain = " · ".join(f"{k} {v}".strip() for k, v in keys)
            if wlen(plain) <= width - 4:
                break
        text = f" {DIM}·{RESET} ".join(
            f"{BOLD}{k}{RESET}" + (f"{DIM} {v}{RESET}" if v else "") for k, v in keys
        )
        # 不要再对 text 调 fit：它已经含 ANSI 转义，转义字节会被当成可见宽度而提前截断。
        # 宽度控制靠上面的阶梯降级完成。
        lines.append(f"  {text}")
        return lines

    # -- 列表项 --
    def menu_items(self):
        return [
            {"label": "立即备份", "desc": "增量上传到 NAS，完成后按保留策略清理",
             "run": self.act_backup},
            {"label": "试运行", "desc": "只扫描并列出版本差异，不写入仓库",
             "run": self.act_dry_run},
            {"label": "版本列表",
             "desc": ("读取仓库中…" if self.loading
                      else f"共 {len(self.snaps)} 个版本，可浏览 / 恢复 / 对比 / 删除"),
             "goto": "snapshots"},
            {"label": "挂载并浏览", "desc": "后台只读挂载，用文件管理器打开",
             "run": self.act_mount},
            {"label": "卸载挂载点", "desc": f"卸载 {self.cfg['mount_dir']}",
             "run": self.act_unmount},
            {"label": "校验仓库完整性", "desc": "读 5% 数据（慢）",
             "run": self.act_check},
            {"label": "编辑保留策略", "desc": f"当前 {self.keep_summary()}",
             "run": self.act_edit_policy},
            {"label": "编辑排除清单", "desc": str(expand(self.cfg["excludes"])),
             "run": self.act_edit_excludes},
        ]

    def snapshot_items(self):
        items = []
        for snap in self.snaps:
            desc = human_size(snap_size(snap))
            if snap.get("tags"):
                desc += "  " + ",".join(snap["tags"])
            items.append(
                {
                    "badge": snap["short_id"],
                    "label": snap["time"][:19].replace("T", " "),
                    "desc": desc,
                    "goto": "snap_actions",
                }
            )
        if not items:
            if self.loading:
                return [{"label": "读取仓库中…", "desc": "正在从 NAS 拉取版本列表", "run": None}]
            items = [{"label": "还没有任何版本", "desc": "先回上一层跑一次备份", "run": None}]
        return items

    def snap_action_items(self):
        snap = self.selected_snap()
        if snap is None:
            return [{"label": "返回", "desc": "", "goto": "snapshots"}]
        return [
            {"label": "挂载浏览", "desc": "后台只读挂载整个仓库并用文件管理器打开",
             "run": self.act_mount},
            {"label": "恢复这个版本",
             "desc": f"选目录后恢复（默认 {self.cfg['restore_dir']}）",
             "run": lambda: self.act_restore(snap)},
            {"label": "与上一版对比", "desc": "列出相对上一个版本的增删改",
             "run": lambda: self.act_diff(snap)},
            {"label": "删除这个版本",
             "desc": f"{snap['short_id']} · {snap['time'][:19].replace('T', ' ')}",
             "run": lambda: self.act_forget_snap(snap)},
            {"label": "返回", "desc": "", "goto": "snapshots"},
        ]

    def current_items(self):
        if self.screen == "menu":
            return self.menu_items()
        if self.screen == "snap_actions":
            return self.snap_action_items()
        return self.snapshot_items()

    def selected_snap(self):
        if not self.snaps:
            return None
        return self.snaps[max(0, min(self.cursor, len(self.snaps) - 1))]

    def body(self, height, width):
        items = self.current_items()
        self.cursor = max(0, min(self.cursor, len(items) - 1))
        if self.cursor < self.offset:
            self.offset = self.cursor
        elif self.cursor >= self.offset + height:
            self.offset = self.cursor - height + 1
        self.offset = max(0, min(self.offset, max(0, len(items) - height)))

        # 短 ID 列只在版本列表里有意义，主菜单/操作列表不占这一列
        badge_w = 9 if any(item.get("badge") for item in items) else 0
        label_w = 24
        desc_w = max(0, width - 3 - badge_w - label_w)
        lines = []
        for idx in range(self.offset, min(len(items), self.offset + height)):
            item = items[idx]
            focused = idx == self.cursor
            bg = CURSOR_BG if focused else ""
            reset = KEEP_BG if focused else RESET
            pointer = f"{BOLD}{CYAN}▌{reset}" if focused else " "
            prefix = f"{pointer} "
            label = pad(fit(item["label"], label_w), label_w)
            if badge_w:
                badge = pad(item.get("badge", ""), badge_w)
                if focused:
                    badge = f"{BOLD}{CYAN}{badge}{reset}"
                prefix += badge
            if focused:
                label = f"{BOLD}{label}{reset}"
            # 行尾用 reset（聚焦时=KEEP_BG，只清前景/粗体、不动背景），
            # 这样 render() 的 \033[K 能把光标本底色铺满整行；非聚焦行则是完全重置。
            lines.append(
                f"{bg}{prefix}{label} {DIM}{fit(item.get('desc', ''), desc_w)}{reset}"
            )
        return lines + [""] * max(0, height - len(lines))

    def keep_summary(self):
        keep = self.cfg["keep"]
        parts = [f"{v} {k[0]}" for k, v in keep.items() if int(v or 0) > 0]
        return " ".join(parts) or "全部保留"

    def render(self):
        size, width = frame_size()
        height = max(6, size.lines)
        header = self.header(width)
        footer = self.footer(width)
        # 底部区高度不定（说明行可能折成多行），按实际行数算正文高度，不要写死。
        # 末尾的 -1 是 render() 裁掉的那一行（最后一行的换行不进屏幕）。
        body_h = max(1, height - 1 - len(header) - len(footer))
        lines = header + self.body(body_h, width) + footer
        resized = self.last_size != size
        self.last_size = size
        # 每行开头先 RESET。聚焦行的底色要靠行尾的 \033[K 填满，
        # 所以那一行不能自己清背景，必须由下一行重置，否则底色会串到下一行。
        frame = "".join(f"\033[0m{line}\033[K\n" for line in lines[: max(1, height - 1)])
        if resized:
            frame = "\033[2J" + frame
        sys.stdout.write("\033[H" + frame)
        sys.stdout.flush()

    # -- 动作 --
    def run_suspended(self, func, *args, **kwargs):
        self.term.suspend()
        try:
            return func(*args, **kwargs)
        finally:
            self.term.resume()
            self.refresh()

    def act_backup(self):
        code = self.run_suspended(do_backup, self.cfg)
        self.set_message("备份完成" if code == 0 else f"备份失败（退出码 {code}）")

    def act_dry_run(self):
        code = self.run_suspended(do_backup, self.cfg, dry_run=True)
        self.set_message("试运行结束，仓库未改动" if code == 0 else f"试运行失败（退出码 {code}）")

    def act_check(self):
        self.run_suspended(do_check, self.cfg)
        self.set_message("校验结束")

    def act_mount(self, snap_id=None):
        target = expand(self.cfg["mount_dir"])
        if is_mounted(target):
            self.set_message(f"{target} 已在挂载中")
            return
        self.term.suspend()
        try:
            do_browse(self.cfg)
        except SystemExit as exc:
            self.set_message(f"挂载失败（退出码 {exc.code}）")
        finally:
            self.term.resume()
        self.set_message(f"已挂载到 {target}/snapshots/")

    def act_unmount(self):
        self.term.suspend()
        try:
            do_unmount(self.cfg)
        finally:
            self.term.resume()
        self.set_message("卸载完成")

    @staticmethod
    def free_space(path):
        """取 path 所在分区的剩余空间；目录还不存在就往上找最近的已存在祖先。"""
        probe = path
        while not probe.exists() and probe != probe.parent:
            probe = probe.parent
        try:
            return shutil.disk_usage(probe).free
        except OSError:
            return None

    def act_restore(self, snap):
        """恢复到用户指定的目录。不默认写 /tmp：home 可能有上百 G，
        而 /tmp 在根文件系统上，既可能撑爆根也没意义。"""
        default = expand(self.cfg["restore_dir"]) / snap["short_id"]
        need = snap_size(snap)
        self.term.suspend()
        code = 1
        target = default
        try:
            info(f"恢复版本 {snap['short_id']}（{human_size(need)}）")
            entered = input(f"恢复到哪个目录？[默认 {default}] ").strip()
            target = expand(entered) if entered else default

            free = self.free_space(target)
            if free is not None and need and free < need:
                warn(
                    f"{target} 所在分区只剩 {human_size(free)}，"
                    f"小于该版本数据量 {human_size(need)}"
                )
                if input("仍要继续？[y/N] ").strip().lower() != "y":
                    self.set_message("已取消")
                    return

            code = subprocess.call(
                [self.restic, "restore", snap["short_id"], "--target", str(target)]
                + host_args(self.cfg),
                env=restic_env(self.cfg),
            )
        finally:
            self.term.resume()
        if code == 0:
            info(f"恢复完成: {target}/home/lu5je0/")
        self.term.wait_key()
        self.set_message(f"已恢复到 {target}" if code == 0 else "恢复失败")

    def act_diff(self, snap):
        idx = self.snaps.index(snap)
        if idx == 0:
            self.set_message("这是最早的版本，没有可对比的对象")
            return
        prev = self.snaps[idx - 1]
        self.term.suspend()
        try:
            print(f"对比 {prev['short_id']} → {snap['short_id']}")
            # diff 不支持 --host
            subprocess.call(
                [self.restic, "diff", prev["short_id"], snap["short_id"]],
                env=restic_env(self.cfg),
            )
        finally:
            self.term.resume()
        self.term.wait_key()
        self.set_message("对比结束")

    def act_forget_snap(self, snap):
        self.term.suspend()
        try:
            print(f"要删除版本 {snap['short_id']} ({snap['time'][:19]})")
            if input("确认删除？[y/N] ").strip().lower() != "y":
                # 不要在这里 resume：finally 里会做，重复 resume 会让终端状态错乱
                self.set_message("已取消")
                return
            code = subprocess.call(
                [self.restic, "forget", snap["id"], "--prune"] + host_args(self.cfg),
                env=restic_env(self.cfg),
            )
        finally:
            self.term.resume()
            self.refresh()
        self.set_message("已删除" if code == 0 else "删除失败")

    def act_edit_policy(self):
        editor = os.environ.get("EDITOR") or "vi"
        path = CONFIG_FILE
        if not path.exists():
            save_config(self.cfg)
        self.term.suspend()
        try:
            subprocess.call([editor, str(path)])
        finally:
            self.term.resume()
        self.cfg = load_config()
        self.refresh()
        self.set_message("保留策略已重新加载")

    def act_edit_excludes(self):
        editor = os.environ.get("EDITOR") or "vi"
        path = expand(self.cfg["excludes"])
        self.term.suspend()
        try:
            subprocess.call([editor, str(path)])
        finally:
            self.term.resume()
        self.set_message("排除清单已保存，下次备份生效")

    # -- 主循环 --
    def move(self, delta):
        items = self.current_items()
        if items:
            self.cursor = max(0, min(len(items) - 1, self.cursor + delta))

    def activate(self):
        items = self.current_items()
        if not items:
            return None
        item = items[self.cursor]
        if item.get("goto"):
            # 记住当前屏的位置，Esc 返回时才能停回原处
            self.history.append((self.screen, self.cursor, self.offset))
            self.screen = item["goto"]
            # 进版本列表默认停在最新的那个（最常用），其它屏从第一项开始
            self.cursor = max(0, len(self.snaps) - 1) if item["goto"] == "snapshots" else 0
            self.offset = 0
            return None
        handler = item.get("run")
        if handler:
            handler()
        return None

    def go_back(self):
        """返回上一层，并恢复到离开时的光标位置。菜单层再返回就是退出。"""
        if not self.history:
            return "quit"
        self.screen, self.cursor, self.offset = self.history.pop()
        return None

    def handle(self, key):
        items = self.current_items()
        if key in ("q", "ESC"):
            return self.go_back()
        if key in ("j", "DOWN"):
            self.move(1)
        elif key in ("k", "UP"):
            self.move(-1)
        elif key in ("g", "HOME"):
            self.cursor = 0
        elif key in ("G", "END"):
            self.cursor = max(0, len(items) - 1)
        elif key == "PGDN":
            self.move(10)
        elif key == "PGUP":
            self.move(-10)
        elif key in ("ENTER", "RIGHT", "l"):
            return self.activate()
        elif key in ("LEFT", "h"):
            return self.go_back()
        return None

    def run(self):
        # 后台加载，界面立刻画出来；select 带超时，加载完成后能自行重绘
        self.start_load()
        with Terminal(self.gate) as term:
            self.term = term
            wake_r, wake_w = os.pipe()
            os.set_blocking(wake_w, False)
            previous = signal.signal(signal.SIGWINCH, lambda *_: None)
            signal.set_wakeup_fd(wake_w)
            try:
                self.render()
                while True:
                    ready = select.select([term.fd, wake_r], [], [], 0.15)[0]
                    if wake_r in ready:
                        os.read(wake_r, 4096)
                    if term.fd in ready:
                        key = read_key(term.fd)
                        self.message = ""
                        if self.handle(key) == "quit":
                            return 0
                    self.render()
            finally:
                signal.set_wakeup_fd(-1)
                signal.signal(signal.SIGWINCH, previous)
                os.close(wake_r)
                os.close(wake_w)

# ── CLI ───────────────────────────────────────────────────


def build_parser():
    parser = argparse.ArgumentParser(
        prog="q-restic",
        description="把 home 增量备份到 NAS 的 restic 前端（不带参数则打开 TUI）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  q-restic                 打开 TUI\n"
            "  q-restic backup          立即备份\n"
            "  q-restic dry-run         试运行，看会传什么\n"
            "  q-restic status          列出版本和占用\n"
            "  q-restic browse          挂载并用文件管理器打开\n"
            "  q-restic restore <ID>    恢复某个版本（默认到 restore_dir）\n"
            "  q-restic unmount         卸载\n"
        ),
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("backup", help="立即备份（含保留策略清理）")
    sub.add_parser("dry-run", help="试运行，不写仓库")
    sub.add_parser("status", help="列出版本 + 占用")
    sub.add_parser("check", help="仓库完整性校验")
    sub.add_parser("forget", help="按保留策略清理旧版本")
    sub.add_parser("config", help="打印当前配置")
    sub.add_parser("edit-config", help="用 $EDITOR 打开配置文件")
    sub.add_parser("edit-excludes", help="用 $EDITOR 打开排除清单")

    for name, help_text in (
        ("mount", "前台只读挂载"),
        ("browse", "后台挂载并用文件管理器打开"),
        ("unmount", "卸载"),
    ):
        cmd = sub.add_parser(name, help=help_text)
        cmd.add_argument("dir", nargs="?", help="挂载点（默认取配置里的 mount_dir）")

    cmd = sub.add_parser("restore", help="恢复某个版本到指定目录")
    cmd.add_argument("snapshot", help="版本 ID（用 short_id 即可）")
    cmd.add_argument(
        "dir", nargs="?",
        help="目标目录（默认 <restore_dir>/<版本ID>；不默认写 /tmp）",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    cfg = load_config()

    if args.command == "config":
        if not CONFIG_FILE.exists():
            save_config(cfg)
            # 走 stderr：stdout 必须留给纯 JSON，否则 `q-restic config | jq` 会解析失败
            print(f"已写入默认配置 {CONFIG_FILE}", file=sys.stderr)
        print(json.dumps(cfg, indent=2, ensure_ascii=False))
        return 0

    if args.command == "edit-config":
        if not CONFIG_FILE.exists():
            save_config(cfg)
        return subprocess.call([os.environ.get("EDITOR") or "vi", str(CONFIG_FILE)])

    if args.command == "edit-excludes":
        return subprocess.call([os.environ.get("EDITOR") or "vi", str(expand(cfg["excludes"]))])

    if args.command == "backup":
        return do_backup(cfg)
    if args.command == "dry-run":
        return do_backup(cfg, dry_run=True)
    if args.command == "status":
        return do_status(cfg)
    if args.command == "check":
        return do_check(cfg)
    if args.command == "forget":
        require_password(cfg)
        acquire_lock(cfg)
        return do_forget(restic_bin(), cfg)
    if args.command == "mount":
        return do_mount(cfg, args.dir)
    if args.command == "browse":
        return do_browse(cfg, args.dir)
    if args.command == "unmount":
        return do_unmount(cfg, args.dir)
    if args.command == "restore":
        return do_restore(cfg, args.snapshot, args.dir)

    if not sys.stdin.isatty():
        parser.print_help()
        return 1

    # 进 TUI 前关掉 kitty 的 IME 闸门，离开时开闸。finally 盖住正常与异常退出，
    # install() 再补上信号与 Ctrl-Z 那几条路径。
    gate = KittyIMEGate()
    gate.install()
    try:
        gate.disable()
        return App(cfg, gate).run()
    finally:
        gate.restore()


if __name__ == "__main__":
    sys.exit(main())
