#!/usr/bin/env bash
set -euo pipefail

SRC="$DOTFILES_DIR/pi"
AGENT_DIR="$HOME/.pi/agent"

mkdir -p "$AGENT_DIR"

conflict=0
for dir in "$SRC"/*/; do
	[ -d "$dir" ] || continue
	name="$(basename "$dir")"
	target="$AGENT_DIR/$name"
	if [ -L "$target" ]; then
		echo "skip: $target already linked"
	elif [ -e "$target" ]; then
		echo "conflict: $target exists and is not a symlink"
		conflict=1
	else
		ln -s "${dir%/}" "$target"
		echo "linked $target -> ${dir%/}"
	fi
done

python3 - "$SRC/settings.json" "$AGENT_DIR/settings.json" <<'EOF'
import json, os, sys

src, dst = sys.argv[1], sys.argv[2]
if not os.path.exists(src):
    sys.exit(0)
managed = json.load(open(src))
current = json.load(open(dst)) if os.path.exists(dst) else {}
changed = [k for k, v in managed.items() if current.get(k) != v]
if changed:
    current.update({k: managed[k] for k in changed})
    with open(dst, "w") as f:
        json.dump(current, f, indent=2)
        f.write("\n")
    print("settings.json: merged " + ", ".join(changed))
else:
    print("skip: settings already managed")
EOF

exit $conflict
