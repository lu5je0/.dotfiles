"""Expose immutable Nix profile launchers through a directory GNOME monitors."""

import argparse
import fcntl
import getpass
import hashlib
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile


def digest(content):
    return hashlib.sha256(content).hexdigest()


def atomic_write(path, content):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
            os.fchmod(stream.fileno(), 0o644)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def icon_index(share):
    candidates = {}
    for root in (share / "icons", share / "pixmaps"):
        for path in files_under(root):
            if path.suffix.lower() not in (".svg", ".png", ".xpm") or not path.is_file():
                continue
            # Prefer package hicolor application icons; scalable icons retain quality at any size.
            parts = path.relative_to(share).parts
            sizes = [int(part.split("x")[0]) for part in parts
                     if "x" in part and all(number.isdigit() for number in part.split("x"))]
            rank = ("hicolor" not in parts, "apps" not in parts,
                    "scalable" not in parts, path.suffix != ".svg", -max(sizes, default=0), str(path))
            for name in (path.stem, path.name):
                if name not in candidates or rank < candidates[name][0]:
                    candidates[name] = (rank, path.resolve())
    return {name: path for name, (_, path) in candidates.items()}


def files_under(root):
    # Profile subdirectories can themselves be links to a package in the store.
    visited = set()
    for directory, directories, files in os.walk(root, followlinks=True):
        real = os.path.realpath(directory)
        if real in visited:
            directories[:] = []
            continue
        visited.add(real)
        directories.sort()
        for name in sorted(files):
            yield Path(directory) / name


def rewrite_icons(text, icons):
    output = []
    for line in text.splitlines(keepends=True):
        key, separator, value = line.partition("=")
        if separator and key.strip() == "Icon":
            name = value.strip()
            icon = icons.get(name)
            if icon is None and Path(name).is_absolute() and Path(name).is_file():
                icon = Path(name).resolve()
            if icon is not None:
                escaped = str(icon).replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
                line = f"Icon={escaped}\n"
        output.append(line)
    return "".join(output).encode("utf-8")


def owned(path, expected):
    # A user replacing or editing a generated launcher takes ownership of it.
    return (expected is not None and not path.is_symlink() and path.is_file()
            and digest(path.read_bytes()) == expected)


def sync(profiles, data_home, state_home, excluded=(), force=False, desktop_database=None):
    applications = data_home / "applications"
    state = state_home / "nix-profile-applications"
    applications.mkdir(parents=True, exist_ok=True)
    state.mkdir(parents=True, exist_ok=True)
    if applications.is_symlink():
        raise ValueError(f"{applications}: must be a real directory")

    with (state / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        manifest_path = state / "manifest.json"
        previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        while True:
            generations = [profile.resolve() for profile in profiles]
            identity = {"version": 2, "generations": list(map(str, generations)), "excluded": sorted(excluded)}
            if (not force and previous.get("identity") == identity
                    and previous.get("mime_cache_ready")
                    and (desktop_database is None or (applications / "mimeinfo.cache").is_file())):
                return False
            entries = {}
            icons = {}
            for generation in reversed(generations):
                icons.update(icon_index(generation / "share"))
            for generation in generations:
                share = generation / "share"
                for source in files_under(share / "applications"):
                    if source.suffix != ".desktop" or not source.is_file():
                        continue
                    desktop_id = source.relative_to(share / "applications").as_posix().replace("/", "-")
                    if desktop_id in excluded or desktop_id in entries:
                        continue
                    entries[desktop_id] = rewrite_icons(source.read_text(encoding="utf-8"), icons)

            managed = previous.get("entries", {})
            updated = {}
            for destination in applications.glob("*.desktop"):
                if (destination.is_symlink() and destination.name not in entries
                        and (not destination.exists() or destination.name in excluded)
                        and os.readlink(destination) in [str(profile / "share/applications" / destination.name)
                                                        for profile in profiles]):
                    destination.unlink()
            for desktop_id, content in entries.items():
                destination = applications / desktop_id
                # Adopt direct profile links, preserving links to any other source.
                legacy = (destination.is_symlink() and os.readlink(destination)
                          in [str(profile / "share/applications" / desktop_id) for profile in profiles])
                if os.path.lexists(destination) and not legacy and not owned(destination, managed.get(desktop_id)):
                    print(f"{desktop_id}: preserving existing user launcher", file=sys.stderr)
                    continue
                content_hash = digest(content)
                if not owned(destination, content_hash):
                    atomic_write(destination, content)
                updated[desktop_id] = content_hash

            for desktop_id, expected in managed.items():
                destination = applications / desktop_id
                if desktop_id not in updated and owned(destination, expected):
                    destination.unlink()

            previous = {"identity": identity, "entries": updated, "mime_cache_ready": desktop_database is None}
            atomic_write(manifest_path, (json.dumps(previous, indent=2) + "\n").encode())
            if desktop_database is not None:
                # User launchers mask system entries, so their MIME registrations must be indexed too.
                subprocess.run([str(desktop_database), str(applications)], check=True)
                previous["mime_cache_ready"] = True
                atomic_write(manifest_path, (json.dumps(previous, indent=2) + "\n").encode())
            # Reconcile another switch that happened during this pass without a timer or sleep.
            if [profile.resolve() for profile in profiles] == generations:
                return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exclude", type=Path)
    parser.add_argument("--desktop-database", type=Path, required=True)
    parser.add_argument("--systemctl", type=Path, help="refresh configured icon overrides after a switch")
    parser.add_argument("--force", action="store_true", help="resync even if the generation is unchanged")
    args = parser.parse_args()
    excluded = json.loads(args.exclude.read_text()) if args.exclude else []
    changed = sync([Path.home() / ".nix-profile", Path("/etc/profiles/per-user") / getpass.getuser(),
          Path("/run/current-system/sw")],
         Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")),
         Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")),
         excluded, args.force, args.desktop_database)
    if changed and args.systemctl:
        subprocess.run([str(args.systemctl), "--user", "--no-block", "try-restart",
                        "desktop-icon-overrides.service"], check=True)


if __name__ == "__main__":
    main()
