{ ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # 本机切源选择由独立 TUI 保存，不随仓库同步；缺省使用原有缓存。
  nix.extraOptions = ''
    !include /etc/nix/source.conf
  '';
}
