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

# Managed top-level files, symlinked for the same reason as the directories:
# pi only reads models.json (ModelConfig.load uses readFile; nothing in pi or the
# installed plugins writes it). The files pi does write -- models-store.json and
# commandcode-models.json -- are siblings resolved from dirname(modelsPath), so
# they stay in ~/.pi/agent/ and never reach the symlink.
#
# simple-perm.json is read-only for the extension as well: its own writes go to
# simple-perm.local.json. keybindings.json has exactly one write path in pi --
# migrateKeybindingsConfigFile(), which rewrites the file only when it still
# contains legacy pre-namespaced ids (cursorUp, expandTools, ...); keep
# namespaced ids in it and the symlink is never written through.
MANAGED_FILES=(models.json simple-perm.json keybindings.json)

link_file() {
	local src="$1" target="$2"
	if [ -L "$target" ]; then
		echo "skip: $target already linked"
	elif [ ! -e "$target" ]; then
		ln -s "$src" "$target"
		echo "linked $target -> $src"
	elif cmp -s "$src" "$target"; then
		# Upgrading from an unmanaged copy: identical, so replacing it loses nothing.
		rm "$target"
		ln -s "$src" "$target"
		echo "replaced identical file with symlink: $target"
	else
		echo "conflict: $target differs from dotfiles (left untouched)"
		conflict=1
	fi
}

for name in "${MANAGED_FILES[@]}"; do
	[ -e "$SRC/$name" ] || continue
	link_file "$SRC/$name" "$AGENT_DIR/$name"
done

# settings.jsonc is parsed with comments/trailing commas removed before merging.
# The live settings.json is shared with pi itself: pi writes runtime keys such as
# lastChangelogVersion, defaultProvider/defaultModel, packages, theme. Merging
# (instead of symlinking) keeps the dotfiles-managed subset in git while leaving
# pi-owned keys untouched. For each managed key, dotfiles wins: `packages` is
# replaced wholesale, so the list here is the authoritative plugin set. Keys not
# present here (defaultModel, theme, ...) are left as pi wrote them.
PYTHONPATH="$SRC${PYTHONPATH:+:$PYTHONPATH}" python3 -B - "$SRC/settings.jsonc" "$AGENT_DIR/settings.json" <<'EOF'
import json, os, sys
import jsonc

src, dst = sys.argv[1], sys.argv[2]
if not os.path.exists(src):
    sys.exit(0)
managed = jsonc.load(open(src))
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

# Reconcile npm packages against the authoritative list. Only direct dependencies
# in pi's npm/package.json are removal candidates; never scan node_modules, which
# also contains dependencies needed by retained plugins. Use npm for removal:
# pi remove also edits settings and fails if the merged list no longer has it.
if command -v pi >/dev/null 2>&1 && [ -f "$SRC/settings.jsonc" ]; then
	# Command substitution propagates parser failures under set -e, unlike process
	# substitution. Finish the plan before executing any package operation.
	package_plan="$(PYTHONPATH="$SRC${PYTHONPATH:+:$PYTHONPATH}" python3 -B - "$SRC/settings.jsonc" "$AGENT_DIR/npm" <<'PYTHON'
import json, os, re, sys
import jsonc

settings, npm_root = sys.argv[1], sys.argv[2]
managed = jsonc.load(open(settings))
if "packages" not in managed:
    sys.exit(0)
packages = managed["packages"]
if not isinstance(packages, list):
    raise ValueError("packages must be an array")
declared = {}
for pkg in packages:
    source = pkg if isinstance(pkg, str) else pkg["source"]
    if not source.startswith("npm:"):
        continue
    spec = source[len("npm:"):]
    # Strip the version/range suffix without eating a leading scope '@'.
    name = re.sub(r"@[^@/]*$", "", spec) or spec
    declared[name] = spec
manifest = os.path.join(npm_root, "package.json")
installed = json.load(open(manifest)).get("dependencies", {}) if os.path.exists(manifest) else {}
for name in sorted(installed.keys() - declared.keys()):
    print("remove\t" + name)
for name, spec in declared.items():
    if not os.path.isdir(os.path.join(npm_root, "node_modules", name)):
        print("install\t" + spec)
PYTHON
	)"
	obsolete=()
	missing=()
	while IFS=$'\t' read -r action spec; do
		[ -n "$spec" ] || continue
		case "$action" in
			remove) obsolete+=("$spec") ;;
			install) missing+=("$spec") ;;
		esac
	done <<< "$package_plan"
	if [ ${#obsolete[@]} -gt 0 ]; then
		echo "uninstalling pi packages: ${obsolete[*]}"
		npm uninstall --prefix "$AGENT_DIR/npm" --legacy-peer-deps --no-audit --no-fund -- "${obsolete[@]}"
	else
		echo "skip: no undeclared pi packages"
	fi
	if [ ${#missing[@]} -gt 0 ]; then
		echo "installing pi packages: ${missing[*]}"
		for spec in "${missing[@]}"; do
			pi install "npm:$spec" >/dev/null 2>&1 || echo "warn: failed to install npm:$spec"
		done
	else
		echo "skip: pi packages already installed"
	fi
fi

exit $conflict
