{ lib, buildNpmPackage, fetchzip, glib }:

buildNpmPackage {
  pname = "gnome-shell-extension-window-decorations";
  version = "0.1.3";

  # 按实际分数缩放密度渲染，避免 GLSLEffect 整数离屏缩放导致文字模糊。
  # 应用规则读取 ~/.config/gnome-window-decorations/config.json，保存后热更新。
  src = fetchzip {
    url = "https://codeload.github.com/sssxks/smooth-shell-corners/tar.gz/b8e3aaa8240b2e9ccadf25d421eca2384ea503dc";
    extension = "tar.gz";
    hash = "sha256-ncBkyjZco2BUJ/yWJeyziPKbGtpXnykt2ioZ5nVmTNU=";
  };
  npmDepsHash = "sha256-DTEALGyR+pkCfYaa2R87GSXggZP60Ew3n6c2FNq6CFI=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmInstall = true;
  nativeBuildInputs = [ glib ];
  patches = [ ./per-app-rules.patch ];
  postPatch = ''
    cp ${./app-rules.ts} src/settings/app-rules.ts
    cp ${./rule-config.ts} src/settings/rule-config.ts
    mkdir -p src/tools
    cp ${./config-apps.ts} src/tools/config-apps.ts
    cp ${./app-rules.test.mjs} tests/unit/app-rules.test.mjs
  '';

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test tests/unit/*.test.mjs
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/gnome-shell/extensions"
    cp -r dist "$out/share/gnome-shell/extensions/smooth-shell-corners@xks"
    install -Dm755 ${./setup.sh} "$out/bin/window-decorations-setup"
    substituteInPlace "$out/bin/window-decorations-setup" \
      --replace-fail '@extensionDir@' "$out/share/gnome-shell/extensions/smooth-shell-corners@xks"
    ln -s window-decorations-setup "$out/bin/codex-window-decorations-setup"
    install -Dm755 ${./window-decorations.sh} "$out/bin/window-decorations"
    runHook postInstall
  '';

  passthru.extensionUuid = "smooth-shell-corners@xks";
  meta = {
    description = "Per-application window corners and shadows on GNOME Wayland";
    homepage = "https://github.com/sssxks/smooth-shell-corners";
    license = lib.licenses.gpl3Plus;
    mainProgram = "window-decorations";
    platforms = lib.platforms.linux;
  };
}
