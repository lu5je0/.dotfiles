{
  callPackage,
  lib,
  stdenv,
  makeWrapper,
  electron,
  mpv,
  python3,
  rsync,
}:

let
  # 私有仓库，走 SSH（fetchFromGitHub 匿名 HTTPS 会 404）
  src = builtins.fetchGit {
    url = "ssh://git@github.com/lu5je0/emby-local-player.git";
    rev = "81f9c46cc9eca4dd1a1c1383e8e5900fa4e33119";
    shallow = true;
  };
  pythonEnv = python3.withPackages (ps: [ ps.requests ]);
in
if stdenv.hostPlatform.isDarwin then
  callPackage "${src}/package.nix" { }
else
  stdenv.mkDerivation {
    pname = "emby-ext-player";
    version = "1.0.0";
    inherit src;

    nativeBuildInputs = [ makeWrapper ];

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      appdir="$out/libexec/emby-ext-player"
      mkdir -p "$appdir/electron-app" "$appdir/etlp-python-embed-win32"

      cp electron-app/{main.js,preload.js,userscript.js,icon.png,package.json} \
        "$appdir/electron-app/"

      # 使用 Nix 的 Python，只拷贝服务和配置。
      cp -r etlp-python-embed-win32/{embyExtServer.py,embyToLocalPlayer.zip,embyToLocalPlayer_config.ini,embyToLocalPlayer_diff.ini,embyToLocalPlayer_example.ini,utils} \
        "$appdir/etlp-python-embed-win32/"
      find "$appdir" -name __pycache__ -type d -exec rm -rf {} +

      cat > "$appdir/launcher" <<'EOF'
      #!/usr/bin/env bash
      set -euo pipefail
      src="@out@/libexec/emby-ext-player"
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/emby-ext-player"

      # Python 服务在运行目录写入补丁和临时文件，升级时保留用户 ini。
      mkdir -p "$state"
      ini="etlp-python-embed-win32/embyToLocalPlayer_config.ini"
      ${lib.getExe rsync} -r --checksum --chmod=u+w --exclude="/$ini" \
        "$src/electron-app" "$src/etlp-python-embed-win32" "$state/"
      ${lib.getExe rsync} --ignore-existing --chmod=u+w "$src/$ini" "$state/$ini"

      exec "${lib.getExe electron}" --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations \
        "$state/electron-app" "$@"
      EOF
      substituteInPlace "$appdir/launcher" \
        --replace-fail "@out@" "$out"
      chmod +x "$appdir/launcher"

      makeWrapper "$appdir/launcher" "$out/bin/emby-ext-player" \
        --prefix PATH : "${
          lib.makeBinPath [
            mpv
            pythonEnv
          ]
        }"

      install -Dm644 electron-app/icon.png \
        "$out/share/icons/hicolor/256x256/apps/emby-ext-player.png"

      mkdir -p "$out/share/applications"
      cat > "$out/share/applications/emby-ext-player.desktop" <<EOF
      [Desktop Entry]
      Type=Application
      Name=EmbyExtPlayer
      Comment=Emby web player wrapper that plays with mpv
      Exec=$out/bin/emby-ext-player
      Icon=emby-ext-player
      Categories=AudioVideo;
      Terminal=false
      EOF

      runHook postInstall
    '';

    meta = {
      description = "Emby web player wrapper that plays with mpv";
      homepage = "https://github.com/lu5je0/emby-local-player";
      license = lib.licenses.mit;
      mainProgram = "emby-ext-player";
      platforms = lib.platforms.linux;
    };
  }
