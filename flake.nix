{
  description = "lu5je0's NixOS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, nixpkgs-unstable, ... }:
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
            inherit pkgsUnstable;
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
        ];
        nixpve-server = mkSystem [
          ./nix/profiles/base.nix
          ./nix/hosts/nixpve
        ];
      };
    };
}
