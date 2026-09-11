{ ... }:

{
  imports = [
    ../modules/nix-ld.nix
    ../modules/packages.nix
    ../modules/zsh.nix
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  users.users.lu5je0 = {
    isNormalUser = true;
    description = "lu5je0";
    extraGroups = [ "docker" "networkmanager" "wheel" ];
  };

  services.cron.enable = true;
  services.openssh.enable = true;
  virtualisation.docker.enable = true;

  programs.appimage.enable = true;
  programs.appimage.binfmt = true;
}
