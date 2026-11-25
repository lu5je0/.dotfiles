{
  lib,
  ibus,
  fetchFromGitHub,
  python3,
}:

# workaround: gnome-shell-ibus-preedit-crash
# 1.5.34 会提前释放组字文本的样式列表，导致 GNOME Shell 崩溃。nixpkgs 升级后移除。
# https://github.com/ibus/ibus/commit/5bbe88a1936246185a65f76e58cc85871401e59a
if lib.versionAtLeast ibus.version "1.5.35" then
  ibus
else
  ibus.overrideAttrs (
    finalAttrs: old: {
      version = "1.5.35";
      src = fetchFromGitHub {
        owner = "ibus";
        repo = "ibus";
        tag = finalAttrs.version;
        hash = "sha256-Wd4z3NMwh9kEu18aLbdF4vGg2gOqBJbpURbinFq6fnM=";
      };

      # GTK 修复已合入上游；1.5.35 删除了旧路径补丁针对的 Python 2 代码。
      patches = builtins.filter (
        patch:
        !(builtins.elem (patch.name or null) [
          "fix-gtk-crashes.patch"
          "fix-paths.patch"
        ])
      ) old.patches;
      configureFlags = old.configureFlags ++ [
        "--with-python-overrides-dir=${placeholder "out"}/${python3.sitePackages}/gi/overrides"
      ];
      postPatch = old.postPatch + ''
        substituteInPlace meson.config --replace-fail 'IBUS_RELEASED=0' 'IBUS_RELEASED=1'
        substituteInPlace data/dconf/Makefile.am --replace-fail 'dconf update;' 'true;'
        substituteInPlace setup/ibus-setup.in \
          --replace-fail 'exec ''${PYTHON:-@PYTHON@}' 'exec ${
            (python3.withPackages (ps: [ ps.pygobject3 ])).interpreter
          }'
      '';
    }
  )
