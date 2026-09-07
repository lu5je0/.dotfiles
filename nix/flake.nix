{
  description = "lu5je0's NixOS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.mission-center-nixpkgs.url = "github:NixOS/nixpkgs/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0";
  inputs.qoder-deb = {
    url = "https://download.qoder.com/qoder-app/releases/latest/Qoder-linux-amd64.deb";
    flake = false;
  };

  outputs = { nixpkgs, nixpkgs-unstable, mission-center-nixpkgs, qoder-deb, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      qoder = pkgs.callPackage ./pkgs/qoder.nix { src = qoder-deb; };
      mkSystem = modules:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            pkgsMissionCenter = mission-center-nixpkgs.legacyPackages.${system};
            pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
          };
        };
    in
    {
      packages.${system}.qoder = qoder;

      nixosConfigurations = {
        nixpve = mkSystem [
          ./profiles/base.nix
          ./hosts/nixpve
          ./profiles/desktop.nix
        ];
        nixpve-server = mkSystem [
          ./profiles/base.nix
          ./hosts/nixpve
        ];
      };
    };
}
