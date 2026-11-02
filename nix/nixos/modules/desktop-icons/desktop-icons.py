"""Override desktop icons in the user's XDG data directory, preserving launchers."""

import json
import os
from pathlib import Path
import sys
import tempfile


def replace_icon(text, icon):
    # Desktop Entry string values escape backslashes and whitespace controls.
    icon = str(icon).replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    output = []
    in_main = found = False
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_main = stripped == "[Desktop Entry]"
            output.append(line)
            if in_main:
                found = True
                if not line.endswith("\n"):
                    output.append("\n")
                output.append(f"Icon={icon}\n")
        elif not (in_main and line.partition("=")[0].strip() == "Icon"):
            output.append(line)
    if not found:
        raise ValueError("missing [Desktop Entry] section")
    return "".join(output)


def find_launcher(desktop_id, data_dirs):
    for directory in data_dirs:
        applications = directory / "applications"
        direct = applications / desktop_id
        if direct.is_file():
            return direct
        # Desktop IDs flatten subdirectories with '-', per the desktop entry spec.
        for entry in sorted(applications.rglob("*.desktop")):
            if str(entry.relative_to(applications)).replace("/", "-") == desktop_id:
                return entry
    return None


def owns_link(destination, generated):
    return destination.is_symlink() and os.readlink(destination) == str(generated)


def apply(overrides, data_home, state_home, data_dirs):
    applications = data_home / "applications"
    generated_dir = state_home / "desktop-icon-overrides" / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    generated_dir.mkdir(parents=True, exist_ok=True)
    errors = False

    for generated in generated_dir.glob("*.desktop"):
        if generated.name not in overrides:
            destination = applications / generated.name
            if owns_link(destination, generated):
                destination.unlink()
            generated.unlink()

    for desktop_id, icon in overrides.items():
        destination = applications / desktop_id
        generated = generated_dir / desktop_id
        if os.path.lexists(destination) and not owns_link(destination, generated):
            print(f"{desktop_id}: existing user launcher left unchanged: {destination}", file=sys.stderr)
            errors = True
            continue
        # Never read our own override as the upstream launcher.
        source = find_launcher(desktop_id, [p for p in data_dirs if p != data_home])
        if source is None:
            if owns_link(destination, generated):
                destination.unlink()
            generated.unlink(missing_ok=True)
            print(f"{desktop_id}: application not installed; skipping", file=sys.stderr)
            continue
        try:
            if not Path(icon).is_file():
                raise ValueError(f"icon not found: {icon}")
            text = replace_icon(source.read_text(encoding="utf-8"), icon)
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=generated_dir, delete=False) as temporary:
                temporary.write(text)
            os.replace(temporary.name, generated)
            if not owns_link(destination, generated):
                destination.symlink_to(generated)
        except (OSError, ValueError) as error:
            print(f"{desktop_id}: {error}", file=sys.stderr)
            errors = True
    return int(errors)


def main():
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    data_dirs = [Path(p) for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p]
    overrides = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    return apply(overrides, data_home, state_home, data_dirs)


if __name__ == "__main__":
    sys.exit(main())
