from contextlib import ExitStack
import ctypes
import errno
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile


SOURCE_ATTRIBUTE = "com.lu5je0.nix-profile-source"
RENAME_SWAP = 0x2
RENAME_EXCL = 0x4


def source_marker(bundle):
    if bundle.is_symlink() or not bundle.is_dir():
        return None
    result = subprocess.run(
        ["/usr/bin/xattr", "-p", SOURCE_ATTRIBUTE, bundle],
        capture_output=True,
    )
    return result.stdout.rstrip(b"\n") if result.returncode == 0 else None


def publish(staged, destination, replace):
    # The app remains complete at its launch path even during upgrades.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    flag = RENAME_SWAP if replace else RENAME_EXCL
    if rename(os.fsencode(staged), os.fsencode(destination), flag) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)


def sync(profile, applications, rsync):
    # Stick to one immutable generation while the profile symlink can change.
    sources = profile.resolve(strict=True) / "Applications"
    apps = {app.name: app for app in sources.glob("*.app") if app.is_dir()}
    if not apps and not applications.exists():
        return
    if applications.is_symlink():
        raise ValueError(f"{applications}: expected a real directory")
    applications.mkdir(parents=True, exist_ok=True)

    for name, app in apps.items():
        destination = applications / name
        marker = source_marker(destination)
        if os.path.lexists(destination) and marker is None:
            print(f"Skipping existing application: {destination}", file=sys.stderr)
            continue

        source = app.resolve(strict=True)
        if marker == os.fsencode(source):
            continue

        with tempfile.TemporaryDirectory(prefix=".sync-", dir=applications) as temporary:
            staged = Path(temporary) / name
            subprocess.run(
                [rsync, "--archive", "--copy-unsafe-links", "--chmod=u+w",
                 "--no-owner", "--no-group", f"{source}/", f"{staged}/"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/xattr", "-w", SOURCE_ATTRIBUTE, source, staged],
                check=True,
            )
            if marker is not None and source_marker(destination) != marker:
                continue
            publish(staged, destination, replace=marker is not None)

    for installed in applications.glob("*.app"):
        if installed.name not in apps and source_marker(installed) is not None:
            shutil.rmtree(installed)


def profile_state(profiles):
    generation = None
    directories = set()
    for profile in profiles:
        path = profile
        visited = set()
        while path not in visited:
            visited.add(path)
            try:
                target = path.readlink()
            except OSError as error:
                if error.errno not in (errno.EINVAL, errno.ENOENT, errno.ENOTDIR):
                    raise
                if path == profile or error.errno != errno.EINVAL:
                    directories.add(next(parent for parent in path.parents if parent.is_dir()))
                if generation is None and path.is_dir():
                    generation = path.resolve()
                break
            directories.add(path.parent)
            path = Path(os.path.normpath(path.parent / target))
    return generation, directories


def watch(profiles, applications, rsync):
    previous = None
    while True:
        generation, directories = profile_state(profiles)
        with ExitStack() as resources:
            queue = select.kqueue()
            resources.callback(queue.close)
            changes = []
            try:
                for directory in directories:
                    descriptor = os.open(directory, os.O_EVTONLY | os.O_DIRECTORY)
                    resources.callback(os.close, descriptor)
                    changes.append(select.kevent(
                        descriptor,
                        filter=select.KQ_FILTER_VNODE,
                        flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                        fflags=(select.KQ_NOTE_WRITE | select.KQ_NOTE_RENAME
                                | select.KQ_NOTE_DELETE | select.KQ_NOTE_REVOKE),
                    ))
            except (FileNotFoundError, NotADirectoryError):
                continue
            queue.control(changes, 0)
            # A generation could change while its directories are being opened.
            if profile_state(profiles) != (generation, directories):
                continue
            if generation is not None and generation != previous:
                sync(generation, applications, rsync)
            previous = generation
            queue.control(None, 1)


def main():
    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
    profiles = [home / ".nix-profile", state / "nix/profile"]
    watch(profiles, home / "Applications/Nix Profile Apps", sys.argv[1])


if __name__ == "__main__":
    main()
