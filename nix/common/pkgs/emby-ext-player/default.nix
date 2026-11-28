{ callPackage }:

let
  # 私有仓库，走 SSH（fetchFromGitHub 匿名 HTTPS 会 404）
  src = builtins.fetchGit {
    url = "ssh://git@github.com/lu5je0/emby-local-player.git";
    rev = "c89ad3c6eaf414b4a1fe9e3d58ad35e0a27ef5b6";
    shallow = true;
  };
in
callPackage "${src}/package.nix" { }
