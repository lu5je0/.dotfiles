{
  description = "lu5je0's NixOS and macOS configuration";

  inputs = {
    nixpkgs.url = "https://releases.nixos.org/nixos/unstable/nixos-26.11pre1124497.0bb8272318b4/nixexprs.tar.zst";
    nixpkgs-unstable.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";

    # 一加 6 的硬件配置需要 7.2 内核。
    nixpkgs-oneplus6.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";

    nixpkgs-darwin.url = "https://channels.nixos.org/nixpkgs-26.05-darwin/nixexprs.tar.zst";
    nixpkgs-darwin-unstable.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # 跟随上游更新，保留上游 nixpkgs 以复用桌面包依赖与缓存。
    llm-agents.url = "github:numtide/llm-agents.nix";

    arcglyph = {
      url = "github:lu5je0/arcglyph";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fcitx5-wetypex = {
      url = "github:lu5je0/fcitx5-wetypex";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wayland-scroll-factor = {
      url = "github:daniel-g-carrasco/wayland-scroll-factor";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-oneplus6,
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
      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            inherit inputs pkgsUnstable;
          };
        };
    in
    {
      packages.${system} = import ./nix/nixos/pkgs { inherit pkgs pkgsUnstable inputs; };
      packages.aarch64-darwin.darwin-rebuild = nix-darwin.packages.aarch64-darwin.darwin-rebuild;

      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        modules = [ ./nix/darwin ];
        specialArgs.pkgsUnstable = import inputs.nixpkgs-darwin-unstable {
          system = "aarch64-darwin";
          config.allowUnfree = true;
        };
      };

      nixosConfigurations = {
        oneplus6 = nixpkgs-oneplus6.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs.pkgsUnstable = import nixpkgs-unstable {
            system = "aarch64-linux";
            config.allowUnfree = true;
          };
          modules = [
            ./nix/nixos/profiles/base.nix
            ./nix/nixos/hosts/oneplus6
            ./nix/nixos/profiles/phone.nix
            ./nix/nixos/modules/nas-mount.nix
          ];
        };
        raider = mkSystem [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/raider
          ./nix/nixos/modules/nas-mount.nix
        ];
        huskar = mkSystem [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/huskar
          ./nix/nixos/modules/gaming
          ./nix/nixos/profiles/desktop.nix
          ./nix/nixos/modules/nas-mount.nix
        ];
        jerry = mkSystem [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/jerry
          inputs.wayland-scroll-factor.nixosModules.default
          ./nix/nixos/modules/gaming
          ./nix/nixos/profiles/desktop.nix
          ./nix/nixos/modules/nas-mount.nix
        ];
      };
    };
}
