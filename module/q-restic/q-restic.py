#!/usr/bin/env python3
"""按 profile 管理 restic 备份，提供 CLI 和 TUI。

本地 POSIX 文件系统可直接作为仓库；NAS 建议走 SFTP，避免 CIFS soft 挂载的写入语义。
只读操作不占写锁；写锁按仓库区分。运行环境必须在 PATH 中提供 restic。
"""

import argparse
import atexit
import base64
import fcntl
import getpass
import hashlib
import json
import os
import queue
import re
import select
import shutil
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import termios
import threading
import time
import tty
import unicodedata
import warnings
from contextlib import contextmanager
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "q-restic"
CONFIG_FILE = CONFIG_DIR / "config.json"

def die(msg, code=1):
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg):
    print(f"==> {msg}")


def warn(msg):
    print(f"警告: {msg}", file=sys.stderr)


# ── 配置 ──────────────────────────────────────────────────────────────


def detect_host():
    """本机短名，用于默认的 `--host` 过滤。

    用 socket.gethostname() 而不是 `hostname -s`：后者来自 net-tools，而 systemd 服务的
    PATH 里没有它，所以新机器（还没有 config.json，会走到这里）会直接 FileNotFoundError。
    FQDN 取第一段，跟 `hostname -s` 同义。
    """
    return socket.gethostname().split(".")[0] or "localhost"


def expand(path):
    return Path(os.path.expandvars(str(path))).expanduser()


def config_path(path):
    path = expand(path)
    return path if path.is_absolute() else CONFIG_FILE.parent / path


def load_config():
    if not CONFIG_FILE.exists():
        return {"profiles": {}}
    try:
        document = json.loads(CONFIG_FILE.read_text())
    except (OSError, ValueError) as exc:
        die(f"配置文件损坏: {CONFIG_FILE} ({exc})")
    if not isinstance(document, dict):
        die("配置必须是 JSON 对象")
    if not isinstance(document.get("profiles"), dict):
        die("配置需要 profiles 对象")
    for name, profile in document["profiles"].items():
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name) or not isinstance(profile, dict):
            die(f"profile 名称或配置无效: {name!r}")
    return document


def save_config(document):
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".q-restic-config-", dir=CONFIG_FILE.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(document, output, indent=2, ensure_ascii=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(tmp, CONFIG_FILE)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def profile_config(document, name):
    profiles = document["profiles"]
    if name not in profiles:
        die(f"profile 不存在: {name}；可选: {', '.join(profiles) or '无'}")
    cfg = dict(profiles[name])
    sources = cfg.get("sources")
    if (not isinstance(sources, list) or not sources
            or not all(isinstance(path, str) and path.strip() for path in sources)):
        die(f"profile {name} 需要非空 sources 路径列表")
    for key in ("repository", "password_file"):
        if not isinstance(cfg.get(key), str) or not cfg[key].strip():
            die(f"profile {name} 缺少 {key}")
    for key in ("excludes", "mount_dir", "restore_dir"):
        if key in cfg and (not isinstance(cfg[key], str) or not cfg[key]):
            die(f"profile {name} 的 {key} 必须是非空路径")
    hooks = cfg.get("hooks", {})
    if (not isinstance(hooks, dict) or set(hooks) - {"before_backup", "after_backup"}
            or any(not isinstance(argv, list) or not argv
                   or not all(isinstance(arg, str) and arg for arg in argv)
                   for argv in hooks.values())):
        die(f"profile {name} 的 hooks 必须是 before_backup/after_backup 命令参数列表")
    cfg["hooks"] = {name: list(argv) for name, argv in hooks.items()}
    cfg["sources"] = [os.path.abspath(config_path(path)) for path in sources]
    for key in ("password_file", "excludes", "mount_dir", "restore_dir"):
        if key in cfg:
            cfg[key] = str(config_path(cfg[key]))
    repository = os.path.expandvars(cfg["repository"])
    cfg["repository"] = str(config_path(repository).resolve()) if ":" not in repository else repository
    cfg["host"] = cfg.get("host") or detect_host()
    cfg.setdefault("tag", "")
    cfg.setdefault("mount_dir", f"/tmp/restic-mnt/{name}")
    cfg.setdefault("restore_dir", str(HOME / "restic-restore" / name))
    keep = cfg.get("keep", {})
    if (not isinstance(keep, dict) or set(keep) - {"hourly", "daily", "weekly", "monthly", "yearly"}
            or any(type(value) is not int or value < 0 for value in keep.values())):
        die(f"profile {name} 的 keep 必须是非负整数保留数量")
    cfg["keep"] = dict(keep)
    tag = cfg.get("snapshot_tag", f"q-restic:profile:{name}")
    if not isinstance(tag, str) or not tag or any(ch.isspace() or ch == "," for ch in tag):
        die(f"profile {name} 的 snapshot_tag 无效")
    if not isinstance(cfg["host"], str) or not isinstance(cfg["tag"], str):
        die(f"profile {name} 的 host/tag 必须是字符串")
    for other, profile in profiles.items():
        if other == name:
            continue
        if not isinstance(profile.get("repository"), str):
            continue
        other_repo = os.path.expandvars(profile["repository"])
        if other_repo and ":" not in other_repo:
            other_repo = str(config_path(other_repo).resolve())
        other_tag = profile.get("snapshot_tag", f"q-restic:profile:{other}")
        extra_tags = str(profile.get("tag") or "").split(",")
        own_tags = cfg["tag"].split(",")
        if (other_repo == cfg["repository"]
                and (profile.get("host") or detect_host()) == cfg["host"]
                and (tag == other_tag or tag in extra_tags or other_tag in own_tags)):
            die(f"profile {name} 与 {other} 的快照标签冲突")
    cfg["_profile"] = name
    cfg["_profile_tag"] = tag
    return cfg


def command_hint(cfg, command):
    args = ["q-restic"]
    if cfg.get("_profile"):
        args += ["-c", str(CONFIG_FILE), "-p", cfg["_profile"]]
    return shlex.join(args + [command])


# ── restic 调用 ───────────────────────────────────────────────────────


def restic_bin():
    """restic 必须已经在 PATH 里。

    不用 `nix build nixpkgs#restic` 兜底：那会在每次调用时求值 flake，
    在没有网络或 /nix 不可用的场景（systemd 服务）里会失败，也拖慢每次启动；
    而 nix/nixos/modules/restic-home.nix 的两个选项都已经装了 pkgs.restic。
    """
    found = shutil.which("restic")
    if not found:
        die(
            f"PATH 里找不到 restic。当前 PATH={os.environ.get('PATH', '')}\n"
            "  只是临时用：nix profile install nixpkgs#restic\n"
            "  若是定时任务报这句：unit 的 PATH 由 systemd.services.<name>.path 在求值时\n"
            "  生成，跟 environment.systemPackages 无关，光 rebuild 不变；见\n"
            "  nix/nixos/modules/restic-home.nix 里的 path = [ pkgs.restic ]。"
        )
    return found


def restic_env(cfg):
    env = dict(os.environ)
    env["RESTIC_REPOSITORY"] = cfg["repository"]
    env["RESTIC_PASSWORD_FILE"] = str(expand(cfg["password_file"]))
    env["RESTIC_CACHE_DIR"] = str(Path(env.get("XDG_CACHE_HOME") or HOME / ".cache") / "restic")
    env.setdefault("HOME", str(HOME))   # excludes.txt 的 $HOME 靠它，缺了会展开成 /.cache
    env.setdefault("RESTIC_PROGRESS_FPS", "1")
    return env


def snapshot_args(cfg):
    """按主机和 profile 标签过滤快照。只有部分子命令支持快照过滤：
    snapshots/stats/forget/restore/mount 支持，diff/check 不支持（传了会直接报错）。
    """
    args = ["--host", cfg["host"]] if cfg.get("host") else []
    if cfg.get("_profile_tag"):
        args += ["--tag", cfg["_profile_tag"]]
    return args


def run(restic, cfg, args, capture=True, check=False):
    cmd = [restic] + args
    return subprocess.run(
        cmd,
        env=restic_env(cfg),
        capture_output=capture,
        text=True,
        check=check,
    )


class RepositoryNotInitialized(RuntimeError):
    """尚无仓库；读取操作只提示，首次备份负责初始化。"""


def repository_missing(result, cfg):
    if result.returncode == 10:
        return True
    # restic 0.14 没有专用退出码。仅对本地路径同时检查错误和 config 缺失；
    # 不能把密码错误、权限不足或网络失败都当成尚未初始化。
    message = (result.stderr or "").lower()
    if (result.returncode != 1 or ":" in cfg["repository"]
            or "unable to open config file:" not in message
            or "no such file or directory" not in message):
        return False
    try:
        (expand(cfg["repository"]) / "config").stat()
    except FileNotFoundError:
        return True
    except OSError:
        pass
    return False


def run_json(restic, cfg, args, *, strict=False):
    res = run(restic, cfg, args)
    if res.returncode != 0:
        if strict:
            if repository_missing(res, cfg):
                raise RepositoryNotInitialized("仓库未初始化，首次备份会自动创建")
            raise RuntimeError(res.stderr.strip() or res.stdout.strip()
                               or f"restic 退出码 {res.returncode}")
        return None
    try:
        return json.loads(res.stdout)
    except ValueError as exc:
        if strict:
            raise RuntimeError("restic 返回了无效的 JSON") from exc
        return None


def run_stream(restic, cfg, args):
    """直接继承终端，让 restic 自己的进度条可见。"""
    return subprocess.call([restic] + args, env=restic_env(cfg))


def run_visible(restic, cfg, args):
    """跑 restic，边跑边把输出打到当前终端，同时把输出收集起来。

    返回 (退出码, 输出文本)。收集是为了在失败时能识别原因（比如“already locked”）
    并给出该怎么做，而不是只报一句“失败”。
    """
    proc = subprocess.Popen(
        [restic] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=restic_env(cfg),
    )
    lines = []
    for line in proc.stdout:
        lines.append(line.rstrip("\n"))
        print(line, end="")
    return proc.wait(), "\n".join(lines)


def require_password(cfg):
    path = expand(cfg["password_file"])
    if not password_ready(cfg):
        die(f"密码文件不存在或为空: {path}；请在 TUI 中选择「设置密码文件」")
    mode = path.stat().st_mode & 0o777
    if mode & 0o077:
        warn(f"密码文件权限是 {mode:o}，建议 chmod 600 {path}")


def password_ready(cfg):
    try:
        path = expand(cfg["password_file"])
        return path.is_file() and path.stat().st_size > 0
    except OSError:
        return False


def set_password_file(cfg):
    path = expand(cfg["password_file"])
    if path.exists() or path.is_symlink():
        warn(f"密码文件已存在，未修改: {path}")
        return 1
    print("设置本机密码文件；已有仓库请填写原密码，此操作不修改仓库密钥。")
    try:
        with warnings.catch_warnings():
            # getpass 无法关闭回显时禁止退回普通输入。
            warnings.simplefilter("error", getpass.GetPassWarning)
            password = getpass.getpass("仓库密码（不回显）: ")
            confirm = getpass.getpass("再次输入密码: ")
        if not password or "\n" in password or "\r" in password:
            warn("密码不能为空或包含换行")
            return 1
        if password != confirm:
            warn("两次密码不一致，未保存")
            return 1
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".q-restic-password-", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as output:
                output.write(password + "\n")
                output.flush()
                os.fsync(output.fileno())
            # link 的目标若已存在会失败，避免并发或符号链接造成覆盖。
            os.link(tmp, path)
        finally:
            os.unlink(tmp)
        info(f"密码文件已保存: {path}（权限 600）")
        return 0
    except (KeyboardInterrupt, EOFError):
        print("\n已取消")
        return 130
    except (OSError, getpass.GetPassWarning) as exc:
        warn(f"密码文件未保存: {exc}")
        return 1


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


@contextmanager
def writer_lock(cfg):
    global _LOCK_FD
    acquire_lock(cfg)
    try:
        yield
    finally:
        if _LOCK_FD is not None:
            _LOCK_FD.close()
            _LOCK_FD = None


# ── 具体命令 ──────────────────────────────────────────────────────────


def repo_ready(restic, cfg):
    result = run(restic, cfg, ["cat", "config"])
    if result.returncode == 0:
        return True
    if repository_missing(result, cfg):
        return False
    raise RuntimeError(result.stderr.strip() or result.stdout.strip()
                       or f"restic 退出码 {result.returncode}")


def preflight_sftp(cfg, quiet=False):
    """SFTP 目标预检：路径存在且可写，避免跑一半才发现写不进去。

    要自己调 PATH 里的 ssh。找不到就只 warn 跳过，不要 die：预检只是提前发现，
    restic 的 sftp 后端是 Go 原生实现、根本不用 ssh（实测 PATH 清空照样能列快照），
    所以少了它备份也能跑完。
    """
    repo = cfg["repository"]
    if not repo.startswith("sftp:"):
        return
    rest = repo[len("sftp:") :]
    userhost, _, path = rest.partition(":")
    if not userhost or not path:
        return
    ssh = shutil.which("ssh")
    if not ssh:
        warn("PATH 里没有 ssh，跳过 NAS 目标预检（不影响备份，只是少了提前发现）")
        return
    if not quiet:
        info(f"预检 NAS 目标 {userhost}:{path}")
    res = subprocess.run(
        [
            ssh,
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
    try:
        ready = repo_ready(restic, cfg)
    except (OSError, RuntimeError) as exc:
        die(f"无法读取仓库: {exc}")
    if not ready:
        info(f"初始化仓库 {cfg['repository']}")
        if run_stream(restic, cfg, ["init"]) != 0:
            die("仓库初始化失败")


def run_backup_hook(cfg, name):
    argv = cfg.get("hooks", {}).get(name)
    if not argv:
        return 0
    env = dict(os.environ, Q_RESTIC_CONFIG=str(CONFIG_FILE), Q_RESTIC_PROFILE=cfg.get("_profile", ""))
    info(f"执行 {name}")
    try:
        with subprocess.Popen(argv, cwd=CONFIG_FILE.parent, env=env, start_new_session=True) as proc:
            try:
                code = proc.wait()
            except BaseException:
                # 停止整个 hook 进程组，再执行恢复 hook，避免准备子进程继续写入。
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                raise
    except OSError as exc:
        warn(f"{name} 无法执行: {exc}")
        return 1
    if code:
        warn(f"{name} 失败（退出码 {code}）")
    return code if code >= 0 else 128 - code


@contextmanager
def backup_signals(cfg):
    """让带恢复 hook 的备份收到终止信号时也经过 finally。"""
    previous = {}
    def terminate(signum, frame):
        signal.signal(signum, signal.SIG_IGN)
        raise SystemExit(128 + signum)
    if cfg.get("hooks") and threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGTERM, signal.SIGHUP):
            previous[signum] = signal.signal(signum, terminate)
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def do_backup(cfg, dry_run=False):
    restic = restic_bin()
    require_password(cfg)

    args = ["backup"] + cfg["sources"] + ["--exclude-caches"]
    if cfg.get("excludes"):
        args += ["--exclude-file", str(expand(cfg["excludes"]))]
    args += ["--host", cfg["host"]]
    for tag in dict.fromkeys(filter(None, (cfg.get("tag"), cfg.get("_profile_tag")))):
        args += ["--tag", tag]
    if dry_run:
        args += ["--dry-run", "--verbose"]
        info(f"试运行 {', '.join(cfg['sources'])} → {cfg['repository']}")
        code = run_stream(restic, cfg, args)
        info("dry-run 结束，仓库未改动")
        return code
    with writer_lock(cfg), backup_signals(cfg):
        try:
            code = run_backup_hook(cfg, "before_backup")
            if code == 0:
                preflight_sftp(cfg)
                ensure_repo(restic, cfg)
                info(f"备份 {', '.join(cfg['sources'])} → {cfg['repository']}")
                code = run_stream(restic, cfg, args)
        finally:
            after_code = run_backup_hook(cfg, "after_backup")
        if after_code:
            warn("备份恢复步骤失败，跳过旧版本清理；请检查 after_backup 输出")
            return code or after_code
        if code not in (0, 3):
            # 没建快照（含仓库不存在/被锁/密码错），别动旧版本。
            return code
        if code == 3:
            # 3 = 快照已建，但有文件读不到。**这种情况下也要清理**：否则一个长期读不到的
            # 文件（root 600 之类）会让 prune 永远不跑，保留策略静默失效、旧版本无限堆积。
            # 已知代价：这些文件在旧版本里的最后副本会随这次 prune 一起消失，
            # 所以退出码保持 3（即使清理也失败，仍如实报告备份不完整）。
            warn("备份不完整（有文件读不到），仍按保留策略清理旧版本")
        forget_code = do_forget(restic, cfg, stream=True)
        if forget_code != 0:
            warn(f"快照已创建，但旧版本清理失败（退出码 {forget_code}）")
            return code or forget_code
        info("完成" if code == 0 else "备份不完整（有文件读不到），已按保留策略清理旧版本")
        return code


def keep_args(cfg):
    keep = cfg["keep"]
    args = []
    for name in ("hourly", "daily", "weekly", "monthly", "yearly"):
        count = int(keep.get(name, 0) or 0)
        if count > 0:
            args += [f"--keep-{name}", str(count)]
    return args


def retention_removals(groups):
    """沿用 restic 的分组和时间桶，只取消「桶数不足时额外保留最老版本」。

    只凭 oldest 理由保留的版本才进入删除列表；还有 daily/weekly 等正常理由的
    必须留下。预览结构不完整时拒绝删除，避免把格式变化误当成可删版本。
    """
    oldest = {f"oldest {name} snapshot" for name in
              ("hourly", "daily", "weekly", "monthly", "yearly")}
    removals = {}
    try:
        if not isinstance(groups, list):
            raise ValueError("预览不是列表")
        for group in groups:
            kept = {snap["id"]: snap for snap in group["keep"]}
            removed = {snap["id"]: snap for snap in group.get("remove") or []}
            reasons = {}
            for reason in group["reasons"]:
                snap = reason["snapshot"]
                sid = snap.get("id")
                if sid is None:
                    # restic 0.14 的理由不带 ID，只能按完整快照内容唯一匹配。
                    candidates = [key for key, item in kept.items()
                                  if {k: v for k, v in item.items() if k not in ("id", "short_id")} == snap]
                    if len(candidates) != 1:
                        raise ValueError("保留理由无法唯一匹配快照")
                    sid = candidates[0]
                if sid in reasons:
                    raise ValueError("保留理由重复")
                reasons[sid] = reason["matches"]
            if not kept or kept.keys() != reasons.keys() or kept.keys() & removed.keys():
                raise ValueError("保留列表与理由不一致")
            for sid, matches in reasons.items():
                if not isinstance(matches, list) or not matches or not all(
                    isinstance(match, str) for match in matches
                ):
                    raise ValueError("保留理由无效")
                if all(match in oldest for match in matches):
                    removed[sid] = kept[sid]
            if not kept.keys() - removed.keys():
                raise ValueError("每组至少需要保留一个版本")
            for sid in kept.keys() | removed.keys():
                if not isinstance(sid, str) or len(sid) != 64 or any(
                    c not in "0123456789abcdef" for c in sid
                ):
                    raise ValueError("快照 ID 无效")
            removals.update(removed)
    except (KeyError, TypeError, ValueError, AttributeError) as exc:
        raise RuntimeError(f"清理预览格式无效，未删除任何版本: {exc}") from exc
    return list(removals.values())


def do_forget(restic, cfg, stream=True, dry_run=False):
    keep = keep_args(cfg)
    if not keep:
        warn("保留策略全为 0，跳过 forget（等同于全部保留）")
        return 0
    info("应用保留策略（不额外保留最老版本）: " + " ".join(keep))
    preview = run(restic, cfg, ["forget", "--dry-run", "--json"] + keep + snapshot_args(cfg))
    code = preview.returncode
    if code:
        warn(preview.stderr.strip() or preview.stdout.strip() or f"restic 退出码 {code}")
    else:
        try:
            # 空仓库时 restic 0.18 不输出 JSON；另查列表确认，不能把异常空输出当成成功。
            if not preview.stdout.strip() and not snapshots(restic, cfg):
                removals = []
            else:
                removals = retention_removals(json.loads(preview.stdout))
        except (ValueError, RuntimeError) as exc:
            warn(f"清理预览失败，未删除任何版本: {exc}")
            return 1
        if not removals:
            info("没有需要清理的旧版本")
            return 0
        info(f"{'将清理' if dry_run else '清理'} {len(removals)} 个旧版本")
        for snap in removals:
            print(f"  {snap['id'][:8]}  {snap.get('time', '')}")
        if dry_run:
            info("清理预览结束，仓库未改动")
            return 0
        # 只删除预览中确定的完整 ID，不再叠加保留参数，以免 oldest 规则再次生效。
        args = ["forget"] + [snap["id"] for snap in removals] + ["--prune"] + snapshot_args(cfg)
        code = run_stream(restic, cfg, args) if stream else run(restic, cfg, args).returncode
    if code == 11:
        warn("仓库被锁定，清理未完成。等待其他 restic 操作结束；若是残留锁，"
             f"运行 `{command_hint(cfg, 'unlock')}` 后再运行 `{command_hint(cfg, 'forget')}`")
    return code


def do_check(cfg):
    restic = restic_bin()
    require_password(cfg)
    info("整个仓库完整性校验（读 5% 数据，包含其它 profile）")
    # check 不支持 --host，不要加主机过滤
    return subprocess.call(
        [restic, "check", "--read-data-subset=5%"], env=restic_env(cfg)
    )


def snap_time_key(snap):
    """restic 给纳秒精度的时间戳，Python 3.9 的 fromisoformat 不接受，
    所以截到秒做字典序排序（同一主机的快照时区一致）。"""
    return str(snap.get("time", ""))[:19]


def snapshots(restic, cfg):
    data = run_json(restic, cfg, ["snapshots", "--json"] + snapshot_args(cfg), strict=True)
    if not isinstance(data, list):
        raise RuntimeError("restic 返回的版本列表格式无效")
    return sorted(data, key=snap_time_key)


def snapshot_stats(restic, cfg):
    return run_json(restic, cfg, ["stats", "--json", "latest"] + snapshot_args(cfg))


def repo_stats(restic, cfg, *, strict=False):
    """当前 profile 所有快照引用的数据占用（raw-data，不看 latest）。"""
    return run_json(restic, cfg, ["stats", "--json", "--mode", "raw-data"] + snapshot_args(cfg),
                    strict=strict)


def do_status(cfg):
    restic = restic_bin()
    require_password(cfg)
    try:
        snaps = snapshots(restic, cfg)
    except RepositoryNotInitialized as exc:
        info(f"profile {cfg.get('_profile', '')} · 仓库 {cfg['repository']}")
        print(f"{exc}。运行 `{command_hint(cfg, 'backup')}` 开始。")
        return 0
    except (OSError, RuntimeError) as exc:
        warn(f"读取仓库失败: {exc}")
        return 1
    info(f"profile {cfg.get('_profile', '')} · 仓库 {cfg['repository']}")
    if not snaps:
        print(f"还没有任何版本。跑一次 `{command_hint(cfg, 'backup')}` 开始。")
        return 0
    print(f"{'ID':<10} {'时间':<20} {'数据量':>10} {'新增':>10}  标签")
    print("-" * 68)
    for snap in snaps:
        print(
            f"{snap['short_id']:<10} {snap['time'][:19].replace('T', ' '):<20} "
            f"{human_size(snap_size(snap)):>10} {human_size(snap_added(snap)):>10}  "
            f"{','.join(snap.get('tags') or [])}"
        )
    latest = run_json(restic, cfg, ["stats", "--json", "latest"] + snapshot_args(cfg))
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
            f"当前 profile 数据占用 {human_size(repo.get('total_size', 0))}"
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
        [restic, "mount", str(target)] + snapshot_args(cfg), env=restic_env(cfg)
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
                [restic, "mount", str(target)] + snapshot_args(cfg),
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


def restore_root(cfg, snap=None):
    """恢复出来的目录树根（相对 --target）。

    restic restore 把快照里的绝对路径原样铺到 --target 下，所以树根是那条
    `/home/<用户名>` 去掉开头的斜杠。**别写死用户名**：优先用快照自己的 paths
    （那是备份时写进快照的，最准），拿不到再退回配置里的 sources。
    """
    paths = (snap or {}).get("paths") or cfg["sources"]
    return str(expand(paths[0])).lstrip("/") if len(paths) == 1 else ""


def do_restore(cfg, snapshot, target=None):
    """恢复到指定目录。默认目录来自配置的 restore_dir。

    不默认写 /tmp：备份源是整个 home（可能上百 G），而 /tmp 在根文件系统上，
    既可能撑爆根分区，恢复出来的东西也不在合理的位置。
    """
    restic = restic_bin()
    require_password(cfg)
    if cfg.get("_profile_tag"):
        available = snapshots(restic, cfg)
        matches = available[-1:] if snapshot == "latest" else [
            snap for snap in available if snap["id"].startswith(snapshot)
        ]
        if len(matches) != 1:
            die(f"当前 profile 中未找到唯一的版本: {snapshot}")
        snapshot = matches[0]["id"]
    dest = expand(target) if target else expand(cfg["restore_dir"]) / snapshot
    info(f"恢复 {snapshot} 到 {dest}")
    root = restore_root(cfg)
    info(f"恢复完成后文件在以 {dest}/{root}/ 为根的目录树里" if root
         else f"恢复完成后文件在 {dest}/ 里")
    return subprocess.call(
        [restic, "restore", snapshot, "--target", str(dest)] + snapshot_args(cfg),
        env=restic_env(cfg),
    )


def do_unlock(cfg):
    """清掉残留锁。

    restic 在进程被强杀（SIGKILL，或 prune 跑到一半被 Ctrl-C）时会留下锁，
    之后 backup 和 forget --prune 都会因为拿不到排他锁而失败。
    仓库走的是 restic 自己的锁机制，和 q-restic 那层 flock 无关。
    """
    restic = restic_bin()
    require_password(cfg)
    with writer_lock(cfg):
        result = run(restic, cfg, ["list", "locks"])
        if result.returncode != 0:
            warn(f"读取仓库锁失败（退出码 {result.returncode}）: "
                 + (result.stderr.strip() or result.stdout.strip()))
            return result.returncode
        locks = result.stdout.strip()
        if not locks:
            info("仓库没有锁，无需清理")
            return 0
        count = len(locks.splitlines())
        info(f"发现 {count} 把仓库锁，仅清理残留锁（保留活动锁）")
        return run_stream(restic, cfg, ["unlock"])


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
        """等一个按键。

        **必须在 suspend() 之后、resume() 之前调用**：子进程的输出打在普通屏上，
        先 resume() 就会切回备用屏把那些输出盖掉，用户只能看到一个空屏。
        suspend() 把终端还原成了 cooked 模式（read 要等回车），这里临时切 cbreak，
        否则提示里的“任意键”不成立。
        """
        print(f"\n{DIM}{prompt}{RESET}", end="", flush=True)
        tty.setcbreak(self.fd)
        try:
            read_key(self.fd)
        finally:
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
        print()


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
    def __init__(self, document, gate=None, *, profile=None):
        self.document = document
        self.profile = profile
        self.cfg = profile_config(document, profile) if profile else {}
        self.gate = gate
        self.restic = None
        self.snaps = []
        self.loading = False
        self.load_error = ""
        self.repo_uninitialized = False
        self.repo_size = None
        self.repo_size_loading = False
        self.repo_size_loaded = False
        self.repo_size_error = ""
        self._requests = {}
        self._results = queue.Queue()
        self._repo_key = self.repo_key()
        self.message = ""
        self.cursor = 0
        self.offset = 0
        self.screen = "profiles" if profile is None else "menu"
        self.history = [("profiles", 0, 0)] if profile else []
        self.active_snap = None
        self.last_size = None

    # -- 数据 --
    def repo_key(self):
        return tuple(self.cfg.get(key) for key in ("repository", "host", "password_file", "_profile_tag"))

    def invalidate_stats(self):
        self._requests.pop("stats", None)
        self.repo_size = None
        self.repo_size_loading = False
        self.repo_size_loaded = False
        self.repo_size_error = ""

    def refresh(self, *, invalidate_stats=True):
        """保留当前列表，后台刷新；切换仓库时清除旧仓库的数据。"""
        if self._repo_key != self.repo_key():
            self._repo_key = self.repo_key()
            self.snaps = []
            self.active_snap = None
            invalidate_stats = True
        if invalidate_stats:
            self.invalidate_stats()
        self._requests.pop("snapshots", None)
        self.loading = False
        self.load_error = ""
        self.repo_uninitialized = False
        if not self.cfg:
            return
        if not password_ready(self.cfg):
            self.load_error = "密码文件未配置，请在菜单中选择「设置密码文件」"
            return
        self.restic = shutil.which("restic")
        if not self.restic:
            self.load_error = "PATH 里找不到 restic，请先安装"
            return
        self.loading = True
        self._start_request("snapshots", snapshots)

    def _start_request(self, kind, loader):
        request = self._requests[kind] = object()
        cfg = dict(self.cfg)

        def worker():
            try:
                result, error = loader(self.restic, cfg), ""
            except RepositoryNotInitialized as exc:
                result, error = None, exc
            except Exception as exc:
                result, error = None, str(exc) or type(exc).__name__
            self._results.put((kind, request, result, error))

        threading.Thread(target=worker, daemon=True).start()

    def start_stats_load(self):
        """进入版本列表后按需统计，同一次会话内复用结果。"""
        if (self.screen != "snapshots" or self.loading or self.load_error or self.repo_uninitialized
                or self.repo_size_loaded or self.repo_size_loading):
            return
        self.repo_size_loading = True
        self._start_request("stats", lambda r, c: repo_stats(r, c, strict=True))

    def poll_data(self):
        """只在主线程更新界面数据，忽略已过期的后台结果。"""
        while True:
            try:
                kind, request, result, error = self._results.get_nowait()
            except queue.Empty:
                break
            if self._requests.get(kind) is not request:
                continue
            del self._requests[kind]
            if kind == "snapshots":
                self.loading = False
                self.repo_uninitialized = isinstance(error, RepositoryNotInitialized) and not self.snaps
                if self.repo_uninitialized:
                    result, error = [], ""
                    self.invalidate_stats()
                self.load_error = str(error) if error else ""
                if error:
                    continue
                old_ids = [snap.get("id", snap["short_id"]) for snap in self.snaps]
                new_ids = [snap.get("id", snap["short_id"]) for snap in result]
                if old_ids != new_ids:
                    self.invalidate_stats()
                if (self.screen == "snap_actions" and self.active_snap is not None
                        and self.active_snap.get("id", self.active_snap["short_id"]) not in new_ids):
                    self.go_back()
                    self.active_snap = None
                    self.set_message("该版本已不在仓库中")
                if self.screen == "snapshots":
                    if not self.snaps:
                        self.cursor = max(0, len(result) - 1)
                    else:
                        selected = old_ids[min(self.cursor, len(old_ids) - 1)]
                        self.cursor = (new_ids.index(selected) if selected in new_ids
                                       else min(self.cursor, max(0, len(result) - 1)))
                self.snaps = result
            else:
                size = result.get("total_size") if isinstance(result, dict) else None
                if not error and (not isinstance(size, int) or size < 0):
                    error = "restic 返回的总占用格式无效"
                self.repo_size = None if error else size
                self.repo_size_error = str(error) if error else ""
                self.repo_size_loading = False
                self.repo_size_loaded = True
        self.start_stats_load()

    def start_load(self):
        """启动时只读取版本列表，总占用等进入列表后再统计。"""
        if self.screen != "profiles":
            self.refresh(invalidate_stats=False)

    def select_profile(self, name):
        try:
            cfg = profile_config(self.document, name)
        except SystemExit:
            self.set_message("profile 配置无效，请编辑配置文件")
            return
        self.history = [("profiles", self.cursor, self.offset)]
        self.profile, self.cfg = name, cfg
        self.screen, self.cursor, self.offset = "menu", 0, 0
        self.message = ""
        self._requests.clear()
        self.snaps, self.active_snap = [], None
        self._repo_key = self.repo_key()
        self.refresh()

    def latest(self):
        return self.snaps[-1] if self.snaps else None

    def set_message(self, text):
        self.message = text

    # -- 渲染 --
    def header(self, width):
        title = "q-restic" + (f" · {self.profile}" if self.profile and self.screen != "profiles" else "")
        title = fit(title, max(8, width // 2))
        if self.screen == "profiles":
            right = f"{len(self.document['profiles'])} 个 profile"
        elif self.loading:
            right = "刷新版本中…" if self.snaps else "读取仓库中…"
        elif self.load_error:
            right = "刷新失败 · 显示已有版本" if self.snaps else "读取仓库失败"
        elif self.repo_uninitialized:
            right = "仓库未初始化"
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
        if self.screen == "profiles":
            return f"配置文件: {CONFIG_FILE}"
        if self.screen == "menu":
            return self.cfg["repository"]
        if self.screen == "snapshots":
            if self.repo_uninitialized:
                return "首次备份将自动初始化仓库"
            size = ("统计中…" if not self.load_error and not self.repo_size_loaded else
                    human_size(self.repo_size) if self.repo_size is not None else "不可用")
            return f"总占用 {size} · 选中版本后按 Enter 查看操作"
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
        error = f"读取仓库失败: {self.load_error}" if self.load_error else ""
        if not error and self.screen == "snapshots" and self.repo_size_error:
            error = f"统计占用失败: {self.repo_size_error}"
        if error:
            for chunk in wrap_text(error + "；返回主菜单后重新进入版本列表重试", width - 2):
                lines.append(f"  {YELLOW}{chunk}{RESET}")
        lines.append(rule)
        if self.message:
            lines.append(f"  {YELLOW}{fit(self.message, width - 3)}{RESET}")
            return lines
        base = [("↑↓/jk", "移动"), ("enter", "选择")]
        if self.screen in ("menu", "profiles"):
            action = "退出" if self.screen == "profiles" else "选择 profile"
            ladders = [base + [("q", action)], base, [("jk", "移动"), ("enter", "选择")]]
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
    def profile_items(self):
        return [
            {"label": name, "desc": str(profile.get("repository") or "未配置仓库"),
             "run": lambda name=name: self.select_profile(name)}
            for name, profile in self.document["profiles"].items()
        ] + [{"label": "编辑配置文件", "desc": str(CONFIG_FILE), "run": self.act_edit_policy}]

    def menu_items(self):
        return [
            {"label": "立即备份", "desc": ("初始化仓库并创建首个快照" if self.repo_uninitialized
                                          else "创建当前 profile 的快照，完成后按保留策略清理"),
             "run": self.act_backup},
            {"label": "试运行", "desc": "只扫描并列出版本差异，不写入仓库",
             "run": self.act_dry_run},
            {"label": "版本列表",
             "desc": ("读取仓库中…" if self.loading
                      else "读取失败，进入后可重试" if self.load_error
                      else "仓库未初始化，先执行一次备份" if self.repo_uninitialized
                      else f"共 {len(self.snaps)} 个版本，可浏览 / 恢复 / 对比 / 删除"),
             "goto": "snapshots"},
            {"label": "挂载并浏览", "desc": "后台只读挂载，用文件管理器打开",
             "run": self.act_mount},
            {"label": "卸载挂载点", "desc": f"卸载 {self.cfg['mount_dir']}",
             "run": self.act_unmount},
            {"label": "编辑保留策略", "desc": f"当前 {self.keep_summary()}",
             "run": self.act_edit_policy},
            {"label": "编辑排除清单", "desc": self.cfg.get("excludes") or "未配置 excludes",
             "run": self.act_edit_excludes},
            {"label": "设置密码文件",
             "desc": ("已设置 · " if password_ready(self.cfg) else "未设置 · ") + self.cfg["password_file"],
             "run": self.act_set_password},
        ]

    def snapshot_items(self):
        items = []
        for snap in self.snaps:
            added = snap_added(snap)
            items.append(
                {
                    "badge": snap["short_id"],
                    "label": snap["time"][:19].replace("T", " "),
                    "size": human_size(snap_size(snap)),
                    "added": f"+{human_size(added)}" if added else "",
                    "desc": ",".join(snap.get("tags") or []),
                    "goto": "snap_actions",
                }
            )
        if not items:
            if self.loading:
                return [{"label": "读取仓库中…", "desc": "正在从 NAS 拉取版本列表", "run": None}]
            if self.load_error:
                items = [{"label": "读取仓库失败", "desc": "返回主菜单后重新进入可重试", "run": None}]
            elif self.repo_uninitialized:
                items = [{"label": "仓库未初始化", "desc": "回到菜单选择「立即备份」创建首个快照", "run": None}]
            else:
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
        if self.screen == "profiles":
            return self.profile_items()
        if self.screen == "menu":
            return self.menu_items()
        if self.screen == "snap_actions":
            return self.snap_action_items()
        return self.snapshot_items()

    def selected_snap(self):
        """操作屏当前针对的版本。

        **不能用 self.cursor 去索引**：在 snap_actions 屏里 cursor 指的是操作项
        （进入时被重置为 0），拿它索引 self.snaps 会永远指向第一个快照，
        于是“恢复/对比/删除这个版本”全作用在错误的版本上。进入操作屏时记下
        真正选中的那个（见 activate）。
        """
        return self.active_snap

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
        sized = [item for item in items if item.get("size")]
        size_w = max((wlen(item["size"]) for item in sized), default=0)
        added_w = max((wlen(item.get("added", "")) for item in sized), default=0)
        label_w = 20 if sized else 24
        avail_w = max(0, width - 3 - badge_w - label_w)
        cols_w = size_w + 1 + (added_w + 1 if added_w else 0)
        min_tag_w = 6      # 拆列后标签至少留这么宽，否则退回把数字挤进 desc
        cols = bool(sized) and avail_w - cols_w >= min_tag_w
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
            desc = item.get("desc", "")
            if item.get("size"):
                if cols:
                    parts = [f"{item['size']:>{size_w}}"]
                    if added_w:
                        parts.append(f"{item.get('added', ''):>{added_w}}")
                    desc = " ".join(parts + [desc])
                else:
                    desc = "  ".join(p for p in (item["size"], item.get("added", ""), desc) if p)
            # 行尾用 reset（聚焦时=KEEP_BG，只清前景/粗体、不动背景），
            # 这样 render() 的 \033[K 能把光标本底色铺满整行；非聚焦行则是完全重置。
            lines.append(
                f"{bg}{prefix}{label} {DIM}{fit(desc, avail_w)}{reset}"
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
    def run_suspended(self, func, *args, wait_on_success=False, refresh_repo=False,
                      failure_prompt="执行失败，按任意键返回", **kwargs):
        """把终端交还给子进程执行 func；**失败时先等一个按键再收回来**。

        否则 resume() 切回备用屏会把子进程打在普通屏上的错误输出盖掉，
        用户只看到一句“备份失败”，永远不知道到底怎么回事。

        `wait_on_success` 给“输出本身就是结果”的命令用（dry-run 的文件清单）：
        它们成功时也要等，否则那份清单会被备用屏瞬间盖掉，只剩底部一句提示。
        （`wait_on_success` 是关键字参数，不会被转发给 func。）
        """
        self.term.suspend()
        try:
            try:
                code = func(*args, **kwargs)
            except SystemExit as exc:
                code = exc.code or 1
            except OSError as exc:
                warn(str(exc))
                code = 1
            if code:
                self.term.wait_key(failure_prompt)
            elif wait_on_success:
                self.term.wait_key("以上是执行结果，按任意键返回")
            return code
        finally:
            self.term.resume()
            if refresh_repo:
                self.refresh()

    def act_set_password(self):
        code = self.run_suspended(set_password_file, self.cfg, refresh_repo=True)
        self.set_message("密码文件已保存" if code == 0 else "密码文件未修改")

    def act_backup(self):
        # 退出码 3 也是“不完整”，不能说成“执行失败”，提示就用中性的
        code = self.run_suspended(do_backup, self.cfg, refresh_repo=True,
                                  failure_prompt="按任意键返回")
        if code == 0:
            self.set_message("备份完成")
        elif code == 3:
            self.set_message("备份不完整：有文件读不到")
        else:
            self.set_message(f"备份或清理失败（退出码 {code}）")

    def act_dry_run(self):
        code = self.run_suspended(do_backup, self.cfg, dry_run=True, wait_on_success=True)
        self.set_message("试运行结束，仓库未改动" if code == 0 else f"试运行失败（退出码 {code}）")

    def act_mount(self, snap_id=None):
        target = expand(self.cfg["mount_dir"])
        if is_mounted(target):
            self.set_message(f"{target} 已在挂载中")
            return
        code = self.run_suspended(do_browse, self.cfg)
        self.set_message(f"已挂载到 {target}/snapshots/" if code == 0 else "挂载失败")

    def act_unmount(self):
        self.term.suspend()
        ok = True
        try:
            do_unmount(self.cfg)
        except SystemExit:
            # do_unmount 用 die() 报错（消息已打到普通屏），先等一个键再收回来，
            # 否则 resume() 会把那条消息盖掉
            ok = False
            self.term.wait_key("卸载失败，按任意键返回")
        finally:
            self.term.resume()
        self.set_message("卸载完成" if ok else "卸载失败")

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
                + snapshot_args(self.cfg),
                env=restic_env(self.cfg),
            )
            if code == 0:
                root = restore_root(self.cfg, snap)
                info(f"恢复完成: {target}/{root}/" if root else f"恢复完成: {target}/")
            else:
                info("恢复失败")
            self.term.wait_key()
        finally:
            self.term.resume()
        self.set_message(f"已恢复到 {target}" if code == 0 else "恢复失败")

    def act_diff(self, snap):
        idx = self.snaps.index(snap)
        if idx == 0:
            self.set_message("这是最早的版本，没有可对比的对象")
            return
        prev = self.snaps[idx - 1]
        self.term.suspend()
        code = 0
        try:
            print(f"{BOLD}对比 {prev['short_id']} → {snap['short_id']}{RESET}")
            # 直接落盘，避免大 diff 堆在内存里；退出编辑器后删除临时文件。
            with tempfile.TemporaryDirectory(prefix="q-restic-diff-") as tmp:
                path = Path(tmp) / f"{prev['short_id']}-{snap['short_id']}.diff"
                with path.open("wb") as output:
                    # diff 不支持 --host；错误留在普通屏上，不混入对比文件。
                    code = subprocess.call(
                        [self.restic, "diff", prev["short_id"], snap["short_id"]],
                        stdout=output,
                        env=restic_env(self.cfg),
                    )
                if code == 0:
                    code = subprocess.call([
                        "nvim", "-R", "-n", "+setlocal filetype=diff nomodifiable",
                        "--", str(path),
                    ])
                if code:
                    self.term.wait_key(f"对比失败（退出码 {code}），按任意键返回")
        except OSError as exc:
            code = 1
            warn(f"无法打开版本对比: {exc}")
            self.term.wait_key("按任意键返回")
        finally:
            self.term.resume()
        self.set_message("对比结束" if code == 0 else f"对比失败（退出码 {code}）")

    def act_forget_snap(self, snap):
        # 记下位置：删完要回到版本列表的同一处（被删的槽位由后面的版本顶上）
        index = self.snaps.index(snap) if snap in self.snaps else 0
        self.term.suspend()
        code = None
        try:
            print(f"要删除版本 {snap['short_id']} ({snap['time'][:19]})")
            if input("确认删除？[y/N] ").strip().lower() != "y":
                # 不要在这里 resume：finally 里会做，重复 resume 会让终端状态错乱
                self.set_message("已取消")
                return
            with writer_lock(self.cfg):
                code, output = run_visible(
                    self.restic,
                    self.cfg,
                    ["forget", snap["id"], "--prune"] + snapshot_args(self.cfg),
                )
            if code:
                print()
                if "already locked" in output:
                    # restic 被强杀时会把锁留下，之后所有要排他锁的操作都这样失败。
                    # 这里给出下一步，而不是只说“失败”。
                    warn("仓库里有其它操作留下的残留锁。确认没有备份在跑后执行：")
                    print("    " + command_hint(self.cfg, "unlock"))
                self.term.wait_key("删除失败，按任意键返回")
        except SystemExit as exc:
            code = exc.code or 1
            self.term.wait_key("删除失败，按任意键返回")
        finally:
            self.term.resume()
            if code is not None:
                self.refresh()

        if code == 0:
            self.snaps = [item for item in self.snaps if item != snap]
            # 这个版本已经不在列表里了，操作屏留在原地会对着一个不存在的快照。
            # 用 go_back() 而不是直接改 self.screen：否则 history 里那条会留着，
            # 之后要点两次 Esc 才能回主菜单。
            self.go_back()
            self.cursor = max(0, min(index, len(self.snaps) - 1))
            self.offset = 0
        self.set_message("已删除" if code == 0 else "删除失败")

    def act_edit_policy(self):
        editor = os.environ.get("EDITOR") or "vi"
        if not CONFIG_FILE.exists():
            save_config(self.document or {"profiles": {}})
        self.term.suspend()
        try:
            if subprocess.call([editor, str(CONFIG_FILE)]):
                self.term.wait_key("编辑器退出失败，按任意键返回")
                return
            document = load_config()
            cfg = profile_config(document, self.profile) if self.profile in document["profiles"] else None
        except SystemExit:
            self.term.wait_key("配置无效，保留原配置，按任意键返回")
            return
        finally:
            self.term.resume()
        self.document = document
        if cfg is None:
            self.profile, self.cfg = None, {}
            self.screen, self.cursor, self.offset = "profiles", 0, 0
            self.history = []
            self._requests.clear()
            self.loading = False
            self.snaps, self.active_snap = [], None
            self.load_error = ""
            self.repo_uninitialized = False
            self.invalidate_stats()
        else:
            self.cfg = cfg
            self.refresh(invalidate_stats=False)
        self.set_message("配置已重新加载")

    def act_edit_excludes(self):
        editor = os.environ.get("EDITOR") or "vi"
        if not self.cfg.get("excludes"):
            self.set_message("请先在配置中设置 excludes 文件路径")
            return
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
            # 离开版本列表时把选中的版本记下来：进入操作屏后 cursor 归零指向操作项，
            # 那边再用 cursor 索引 self.snaps 就会错到第一个版本上
            if self.screen == "snapshots" and self.snaps:
                self.active_snap = self.snaps[min(self.cursor, len(self.snaps) - 1)]
            self.screen = item["goto"]
            # 进版本列表默认停在最新的那个（最常用），其它屏从第一项开始
            self.cursor = max(0, len(self.snaps) - 1) if item["goto"] == "snapshots" else 0
            self.offset = 0
            if self.screen == "snapshots":
                if self.load_error:
                    self.refresh()
                elif self.repo_size_error:
                    self.invalidate_stats()
            self.start_stats_load()
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
        if self.screen == "profiles":
            self._requests.clear()
            self.loading = False
            self.invalidate_stats()
            self.load_error = ""
            self.repo_uninitialized = False
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
                    self.poll_data()
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
        prog="q-restic", description="按 profile 管理 restic 备份；无子命令时打开 TUI",
    )

    def options(target):
        target.add_argument("-c", "--config", default=argparse.SUPPRESS,
                            help="配置文件（默认 ~/.config/q-restic/config.json）")
        target.add_argument("-p", "--profile", default=argparse.SUPPRESS,
                            help="profile 名称；CLI 仓库操作必须指定")

    options(parser)
    sub = parser.add_subparsers(dest="command")

    def command(name, **kwargs):
        target = sub.add_parser(name, **kwargs)
        options(target)
        return target

    command("backup", help="备份当前 profile 并清理旧快照")
    command("dry-run", help="试运行，不写入备份数据")
    command("status", aliases=["snapshots", "list"], help="列出当前 profile 的版本与占用")
    command("check", help="校验整个仓库（包含其它 profile）")
    command("unlock", help="清理整个仓库的残留锁")
    cmd = command("forget", help="清理当前 profile 的旧快照")
    cmd.add_argument("--dry-run", action="store_true", help="只预览清理列表")
    command("config", help="打印配置 JSON；指定 -p 时打印该 profile 的有效配置")
    command("edit-config", help="编辑配置文件")
    command("edit-excludes", help="编辑当前 profile 的排除清单")
    command("set-password", help="交互设置当前 profile 的密码文件，不覆盖已有文件")
    for name in ("mount", "browse", "unmount"):
        cmd = command(name, help="挂载浏览或卸载当前 profile")
        cmd.add_argument("dir", nargs="?", help="挂载目录")
    cmd = command("restore", help="恢复当前 profile 中的版本")
    cmd.add_argument("snapshot", help="版本 ID 或 latest")
    cmd.add_argument("dir", nargs="?", help="恢复目标目录")
    return parser


def main():
    global CONFIG_FILE
    parser = build_parser()
    args = parser.parse_args()
    path = getattr(args, "config", None)
    if path:
        CONFIG_FILE = expand(path).resolve()
        if not CONFIG_FILE.is_file():
            parser.error(f"配置文件不存在: {CONFIG_FILE}")
    name = getattr(args, "profile", None)
    if args.command and args.command not in ("config", "edit-config") and not name:
        parser.error("CLI 仓库操作必须通过 -p/--profile 指定 profile")
    document = load_config()
    cfg = profile_config(document, name) if name else None
    if args.command == "config":
        value = {key: val for key, val in cfg.items() if not key.startswith("_")} if cfg else document
        print(json.dumps(value, indent=2, ensure_ascii=False))
        return 0
    if args.command == "edit-config":
        if not CONFIG_FILE.exists():
            save_config(document)
        return subprocess.call([os.environ.get("EDITOR") or "vi", str(CONFIG_FILE)])
    if args.command == "edit-excludes":
        if not cfg.get("excludes"):
            die("当前 profile 未配置 excludes")
        return subprocess.call([os.environ.get("EDITOR") or "vi", cfg["excludes"]])
    if args.command == "set-password":
        return set_password_file(cfg)
    if args.command == "backup":
        return do_backup(cfg)
    if args.command == "dry-run":
        return do_backup(cfg, dry_run=True)
    if args.command in ("status", "snapshots", "list"):
        return do_status(cfg)
    if args.command == "check":
        return do_check(cfg)
    if args.command == "forget":
        require_password(cfg)
        if args.dry_run:
            return do_forget(restic_bin(), cfg, dry_run=True)
        with writer_lock(cfg):
            return do_forget(restic_bin(), cfg)
    if args.command == "unlock":
        return do_unlock(cfg)
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
    gate = KittyIMEGate()
    gate.install()
    try:
        gate.disable()
        return App(gate=gate, document=document, profile=name).run()
    finally:
        gate.restore()


if __name__ == "__main__":
    sys.exit(main())
