{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [
        "*"
        # G304 同时声明键盘能力，会被通配规则接管；排除以免与 arcglyph 争抢鼠标设备。
        "-046d:4074"
      ];
      settings = {
        main = {
          capslock = "esc";
          leftalt = "layer(meta_vim)";
        };
        "meta_vim:A" = {
          h = "left";
          j = "down";
          k = "up";
          l = "right";
        };
      };
    };
  };
}
