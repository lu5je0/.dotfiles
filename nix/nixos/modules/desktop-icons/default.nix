{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.desktopIconOverrides;
  desktopId = name: if lib.hasSuffix ".desktop" name then name else "${name}.desktop";
  overrides = pkgs.writeText "desktop-icon-overrides.json" (
    builtins.toJSON (lib.mapAttrs' (name: icon: lib.nameValuePair (desktopId name) "${icon}") cfg)
  );
in
{
  options.programs.desktopIconOverrides = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    example = lib.literalExpression ''
      {
        "io.github.yucling.open-orpheus" = ./icons/netease-cloud-music.svg;
        "org.gnome.Nautilus" = ./icons/files.png;
      }
    '';
    description = ''
      桌面启动项 ID 到图标文件的映射，ID 可省略 .desktop 后缀。
      对图形会话用户生效，保留原启动项的命令、动作和其他属性。
      已有手工创建的同名用户启动项不会被覆盖，冲突会记入用户服务日志。
    '';
  };

  config = {
    assertions = [
      {
        assertion = lib.all (name: builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" name != null) (
          builtins.attrNames cfg
        );
        message = "programs.desktopIconOverrides 的键必须是桌面启动项 ID，不能包含路径。";
      }
      {
        assertion =
          let
            ids = map desktopId (builtins.attrNames cfg);
          in
          builtins.length ids == builtins.length (lib.unique ids);
        message = "programs.desktopIconOverrides 不能同时配置同一 ID 的有后缀和无后缀形式。";
      }
    ];

    # 空配置也运行，以便删除最后一条配置后清理生成的覆盖。
    systemd.user.services.desktop-icon-overrides = {
      description = "Apply desktop application icon overrides";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python3 ${./desktop-icons.py} ${overrides}";
      };
    };
  };
}
