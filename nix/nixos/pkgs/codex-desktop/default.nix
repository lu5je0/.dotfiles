{ pkgs, flake }:

# 官方 Linux 桌面包由上游适配 NixOS，启动命令为 chatgpt。
# 安装：nix profile add path:~/.dotfiles#codex-desktop
# 更新：先修改根 flake.nix 中 llm-agents 的提交，再 nix flake update llm-agents，最后 nix profile upgrade codex-desktop
# Git flake 只包含已跟踪的文件；新增补丁脚本须先 git add，否则 profile 升级读不到。
let
  upstream = flake.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt;
  patched = upstream.override {
    chatgpt-unwrapped = upstream.unwrapped.overrideAttrs (old: {
      # workaround: codex-ime-first-key
      # 修复 preedit 首键光标与自动聚焦重复插入首字母；原因与升级检查见脚本。
      postInstall = (old.postInstall or "") + ''
        ${pkgs.python3}/bin/python3 ${./patch-preedit-caret.py} \
          "$out/lib/chatgpt/resources/app.asar"
      '';
    });
  };
in
patched.overrideAttrs (old: {
  # 单独为 Codex 固定 Wayland，不依赖会话的 NIXOS_OZONE_WL。
  postInstall = (old.postInstall or "") + ''
    wrapProgram "$out/bin/chatgpt" --add-flags "--ozone-platform=wayland"
  '';
})
