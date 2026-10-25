{ gtk-frdp, fetchFromGitLab }:

# nixpkgs 的 2026-04-24 快照缺少上游 040b75d5 的指针初始化修复：
# frdp_register_pointer 使用未初始化的 rdpPointer，服务端更新指针时会释放野指针崩溃。
# 固定到包含修复的源码；nixpkgs 自带此修复后移除覆盖。
gtk-frdp.overrideAttrs {
  version = "0-unstable-2026-07-24";
  src = fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "GNOME";
    repo = "gtk-frdp";
    rev = "83854a24e31d1c07519f6e4393fe280d3b59e080";
    hash = "sha256-6f0irRBkpmOYrhXkeSR6ni55SJiltOfYRiwZy5V/VrE=";
  };
}
