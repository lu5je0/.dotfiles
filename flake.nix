{
  description = "lu5je0's NixOS configuration";

  # inputs 只能是字面量 attrset（import / let / // 都会被判为 thunk 而报错），
  # 外部包输入只能登记在这里，但 outputs 用 @inputs 全量捕获，模块按 inputs.<name> 使用
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    mark-shot = {
      url = "github:jswysnemc/mark-shot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... }@inputs:
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
      localPackages = import ./nix/pkgs {
        inherit pkgs;
      };
      mkSystem = modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            inherit pkgsUnstable inputs;
          };
        };
    in
    {
      packages.${system} = localPackages;

      nixosConfigurations = {
        nixpve = mkSystem [
          ./nix/profiles/base.nix
          ./nix/hosts/nixpve
          ./nix/profiles/desktop.nix
          ./nix/modules/nas-mount.nix
        ];
        huskar = mkSystem [
          ./nix/profiles/base.nix
          ./nix/hosts/huskar
          ./nix/modules/gaming.nix
          ./nix/profiles/desktop.nix
          ./nix/modules/nas-mount.nix
        ];
      };
    };
}
