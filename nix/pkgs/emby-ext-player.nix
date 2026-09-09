{
  lib,
  stdenv,
  makeWrapper,
  electron,
  mpv,
  python3,
}:

let
  pythonEnv = python3.withPackages (ps: [ ps.requests ]);
in
stdenv.mkDerivation rec {
  pname = "emby-ext-player";
  version = "1.0.0";

  # 私有仓库，走 SSH（fetchFromGitHub 匿名 HTTPS 会 404）
  src = builtins.fetchGit {
    url = "ssh://git@github.com/lu5je0/emby-local-player.git";
    rev = "859e430a369a2dc232e02231593bf4019cbad81d";
    shallow = true;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    appdir="$out/libexec/emby-ext-player"
    mkdir -p "$appdir/electron-app" "$appdir/etlp-python-embed-win32"

    cp electron-app/{main.js,preload.js,userscript.js,icon.png,package.json} \
      "$appdir/electron-app/"

    # Linux 不用 python_embed（系统 python3）、Windows 调试脚本与 log.txt
    cp -r etlp-python-embed-win32/{embyExtServer.py,embyToLocalPlayer.zip,embyToLocalPlayer_config.ini,embyToLocalPlayer_diff.ini,embyToLocalPlayer_example.ini,utils} \
      "$appdir/etlp-python-embed-win32/"
    find "$appdir" -name __pycache__ -type d -exec rm -rf {} +

    cat > "$appdir/launcher" <<'EOF'
    #!/usr/bin/env bash
    set -euo pipefail
    src="@out@/libexec/emby-ext-player"
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/emby-ext-player"

    # store 只读而 Python 服务需要可写 cwd（ini 补丁、.tmp），故先同步到 state 目录再启动；
    # config.json 不在源里，天然跨更新保留；ini 可能有用户手改项，按 setup.sh 语义保留
    mkdir -p "$state"
    ini="$state/etlp-python-embed-win32/embyToLocalPlayer_config.ini"
    keep=""
    if [ -e "$ini" ]; then
      keep="$(mktemp)"
      cp "$ini" "$keep"
    fi
    cp -rT "$src/electron-app" "$state/electron-app"
    cp -rT "$src/etlp-python-embed-win32" "$state/etlp-python-embed-win32"
    if [ -n "$keep" ]; then
      cp "$keep" "$ini"
      rm -f "$keep"
    fi
    chmod -R u+w "$state"

    # ozone 参数必须在命令行上（见项目 AGENTS.md 血泪坑 7）
    exec "@electron@" --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations \
      "$state/electron-app" "$@"
    EOF
    substituteInPlace "$appdir/launcher" \
      --replace-fail "@out@" "$out" \
      --replace-fail "@electron@" "${electron}/bin/electron"
    chmod +x "$appdir/launcher"

    makeWrapper "$appdir/launcher" "$out/bin/emby-ext-player" \
      --prefix PATH : "${lib.makeBinPath [ mpv pythonEnv ]}"

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
