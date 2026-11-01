{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  glib,
}:

let
  uuid = "touchpad-speed-control@ritesh";
in
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-touchpad-speed-control";
  version = "5";

  src = fetchFromGitHub {
    owner = "ritesh-777";
    repo = "touchpad-speed-control";
    rev = "5ee3ad069e6b2c5dfa4d3cce7636cdab9bcf4578";
    hash = "sha256-ItvRgKEj6ZVYMEDEVwLfnKkpoYISQt9sdLUKhmB8tug=";
  };

  nativeBuildInputs = [ glib ];

  # NixOS 从 /etc/environment.d 声明式加载 WSF，没有 wsf enable 写入的用户文件。
  # 以 gnome-shell 是否实际映射预加载库为准。
  postPatch = ''
    substituteInPlace extension.js \
      --replace-fail 'return enabled && libraryMapped;' 'return libraryMapped;'
  '';

  buildPhase = ''
    runHook preBuild
    rm -f schemas/gschemas.compiled
    glib-compile-schemas --strict schemas
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    extensionDir="$out/share/gnome-shell/extensions/${uuid}"
    mkdir -p "$extensionDir"
    cp extension.js prefs.js metadata.json icon.png icon.svg "$extensionDir/"
    cp -r schemas "$extensionDir/"
    runHook postInstall
  '';

  passthru.extensionUuid = uuid;

  meta = {
    description = "Per-application touchpad scroll speed control for GNOME on Wayland";
    homepage = "https://github.com/ritesh-777/touchpad-speed-control";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
