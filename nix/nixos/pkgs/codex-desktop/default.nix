{ pkgs, flake }:

# 官方 Linux 桌面包由上游适配 NixOS，启动命令为 chatgpt。
# 安装：nix profile add path:~/.dotfiles#codex-desktop
# 更新：nix flake update llm-agents，再 nix profile upgrade codex-desktop
# Git flake 只包含已跟踪的文件；新增补丁脚本须先 git add，否则 profile 升级读不到。
let
  upstream = flake.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt;
  patched = upstream.override {
    chatgpt-unwrapped = upstream.unwrapped.overrideAttrs (old: {
      # workaround: codex-preedit-first-key-caret
      # 2026-10-17：修复 preedit 首字母光标在末尾、第二字母才回到开头的问题。
      # Codex 26.1007.71326 + GNOME Wayland + WeTypeX 已实测修复；原因与升级检查见脚本。
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
