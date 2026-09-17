{ ... }:

{
  imports = [
    ../modules/nh.nix
    ../modules/nix-ld.nix
    ../modules/packages.nix
    ../modules/zsh.nix
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # nix-community 二进制缓存（第三方，只读公开）。用于 nightly 类包（如
    # neovim-nightly-overlay）避免本地编译。放在系统级而不是信任 flake 的 nixConfig：
    # 替换按路径哈希全局进行，缓存已在全局列表就不依赖 flake 提权。
    # 只列额外缓存：cache.nixos.org 由 nixpkgs 的 nix.settings 默认定义（substituters
    # 用 mkAfter 追加，trusted-public-keys 直给），且 list 是合并语义，重复列会得两份。
    substituters = [
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    persistent = true;
  };

  # 定期执行 nix store optimise，用硬链接合并 store 中内容相同的文件
  nix.optimise.automatic = true;

  services.envfs.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.sessionVariables = {
    NPM_CONFIG_PREFIX = "/home/lu5je0/.local";
    # /etc/ssl/certs has no hashed symlinks, so CApath alone verifies nothing
    SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_DIR = "/etc/ssl/certs";
  };

  environment.localBinInPath = true;

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  users.groups.lu5je0.gid = 1000;
  users.users.lu5je0 = {
    isNormalUser = true;
    uid = 1000;
    group = "lu5je0";
    description = "lu5je0";
    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
    ];
  };

  services.cron.enable = true;
  services.openssh.enable = true;
  virtualisation.docker.enable = true;

  programs.appimage.enable = true;
}
