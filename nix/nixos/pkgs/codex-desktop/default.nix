{ pkgs, flake }:

# 官方 Linux 桌面包由上游适配 NixOS，启动命令为 chatgpt。
# 安装：nix profile add path:~/.dotfiles#codex-desktop
# 更新：在仓库根目录执行 nix flake update llm-agents，再 nix profile upgrade codex-desktop
# Git flake 只包含已跟踪的文件；新增补丁脚本须先 git add，否则 profile 升级读不到。
let
  upstream = flake.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt;
  patched = upstream.override {
    chatgpt-unwrapped = upstream.unwrapped.overrideAttrs (old: {
      # workaround: codex-ime-first-key
      # 修复预测打断组字与发送后聚焦失败；约束见补丁脚本。
      postInstall = (old.postInstall or "") + ''
        ${pkgs.python3}/bin/python3 ${./patch-preedit-caret.py} \
          --helpers ${./ime-workarounds.js} \
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
