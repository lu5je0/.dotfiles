{
  description = "lu5je0's NixOS and macOS configuration";

  inputs = {
    # nixos
    nixpkgs.url = "github:NixOS/nixpkgs/release-26.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # darwin
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-darwin-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # 跟随上游更新，保留上游 nixpkgs 以复用桌面包依赖与缓存。
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

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
      nix-darwin,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgsUnstableFor =
        system:
        import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      pkgsUnstable = pkgsUnstableFor system;
      mkSystem =
        system: modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            inherit inputs;
            pkgsUnstable = pkgsUnstableFor system;
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
        oneplus6 = mkSystem "aarch64-linux" [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/oneplus6
          ./nix/nixos/profiles/phone.nix
          ./nix/nixos/modules/nas-mount.nix
        ];
        raider = mkSystem system [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/raider
          ./nix/nixos/modules/nas-mount.nix
        ];
        huskar = mkSystem system [
          ./nix/nixos/profiles/base.nix
          ./nix/nixos/hosts/huskar
          ./nix/nixos/modules/gaming
          ./nix/nixos/profiles/desktop.nix
          ./nix/nixos/modules/nas-mount.nix
        ];
        jerry = mkSystem system [
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
