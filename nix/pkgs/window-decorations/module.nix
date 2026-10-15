{ ... }:

{
  programs.dconf.profiles.user.databases = [
    {
      # 圆角、阴影和应用筛选由 JSON 规则接管；禁止上游写入全局 GTK CSS。
      settings."org/gnome/shell/extensions/smooth-shell-corners".remove-native-radius = false;
      locks = [
        "/org/gnome/shell/extensions/smooth-shell-corners/remove-native-radius"
      ];
    }
  ];
}
