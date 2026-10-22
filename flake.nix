{
  description = "lu5je0's NixOS and macOS configuration";

  # inputs 只能是字面量 attrset（import / let / // 都会被判为 thunk 而报错）
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
    nixpkgs-unstable.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

    nixpkgs-darwin.url = "https://channels.nixos.org/nixpkgs-26.05-darwin/nixexprs.tar.zst";
    nixpkgs-darwin-unstable.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # 保留上游 nixpkgs，复用其桌面包依赖与缓存；用 flake.lock 固定版本。
    llm-agents.url = "github:numtide/llm-agents.nix";

    fcitx5-wetypex = {
      url = "github:lu5je0/fcitx5-wetypex";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 上游只有 flake 打包；补丁后不装进系统配置，`nix profile add path:~/.dotfiles#mark-shot`
    mark-shot = {
      url = "github:jswysnemc/mark-shot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      nix-darwin,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      localPackages = import ./nix/nixos/pkgs {
        inherit pkgs inputs;
      };
      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            inherit pkgsUnstable;
          };
        };
    in
    {
      packages.${system} = localPackages // {
        oneplus6-uboot = pkgs.callPackage ./nix/nixos/hosts/oneplus6/pkgs/uboot { };
      };

      packages.aarch64-darwin.darwin-rebuild = nix-darwin.packages.aarch64-darwin.darwin-rebuild;

      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        modules = [ ./nix/darwin ];
        specialArgs.pkgsUnstable = import inputs.nixpkgs-darwin-unstable {
          system = "aarch64-darwin";
          config.allowUnfree = true;
        };
      };

      nixosConfigurations = {
        oneplus6 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          # Keep the system on stable; shared modules can select ARM unstable packages.
          specialArgs.pkgsUnstable = import nixpkgs-unstable {
            system = "aarch64-linux";
            config.allowUnfree = true;
          };
          modules = [
            ./nix/nixos/profiles/base.nix
            ./nix/nixos/profiles/phone.nix
            ./nix/nixos/hosts/oneplus6
          ];
        };
        nixpve = mkSystem [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/nixpve
          ./nix/nixos/modules/nas-mount.nix
        ];
        huskar = mkSystem [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/huskar
          ./nix/nixos/modules/gaming.nix
          ./nix/nixos/profiles/desktop.nix
          ./nix/nixos/modules/nas-mount.nix
        ];
        jerry = mkSystem [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/jerry
          ./nix/nixos/modules/gaming.nix
          ./nix/nixos/profiles/desktop.nix
          ./nix/nixos/modules/nas-mount.nix
        ];
      };
    };
}
