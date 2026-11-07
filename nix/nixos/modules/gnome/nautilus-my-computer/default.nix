{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  gettext,
  glib,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "nautilus-my-computer";
  version = "0.13.4";

  src = fetchFromGitHub {
    owner = "yannmasoch";
    repo = "nautilus-my-computer";
    rev = "9b19850ab1559877d4f96dd2b05d4124cc04ed1a";
    hash = "sha256-5Pjd6L6sig/ZM8m3Y/13DSbppF11x3hvMlMsu+8kU50=";
  };

  nativeBuildInputs = [
    gettext
    glib
    python3
  ];

  makeFlags = [ "PREFIX=${placeholder "out"}" ];

  postInstall = ''
    # 扩展入口会把自身目录加入 Python 搜索路径。Pycairo 使用与 nautilus-python 相同的解释器版本。
    ln -s ${python3.pkgs.pycairo}/${python3.sitePackages}/cairo "$out/share/nautilus-python/extensions/cairo"
  '';

  meta = {
    description = "Drive and network mount overview for Nautilus";
    homepage = "https://github.com/yannmasoch/nautilus-my-computer";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
