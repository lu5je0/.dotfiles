{ ... }:

{
  # nh (nix-community/nh) 官方 NixOS 模块。
  # enable 自带 systemPackages = [ pkgs.nh ]，并把 NH_FLAKE 写进 /etc/set-environment，
  # 于是 `nh os switch` 无需再指定 flake 路径。
  programs.nh = {
    enable = true;
    # 必须用字面路径：nh 不展开 $HOME（实测 `NH_FLAKE='$HOME/.dotfiles'` 会去找
    # "/tmp/$HOME/.dotfiles"）。$HOME 的展开依赖 login shell，systemd/脚本拿不到。
    flake = "/home/lu5je0/.dotfiles";
  };

  # 自动清理交给 nix/modules/base.nix 的 nix.gc（weekly + 14d）。
  # 若在此启用 programs.nh.clean.enable，模块会警告它与 nix.gc.automatic 冲突。
}
