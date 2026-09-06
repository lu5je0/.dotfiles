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
      mkSystem = modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            qoderDeb = qoder-deb;
            pkgsMissionCenter = mission-center-nixpkgs.legacyPackages.x86_64-linux;
            pkgsUnstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
          };
          inherit modules;
        };
    in
    {
      nixosConfigurations = {
        desktop = mkSystem [
          ./hosts/nixos
          ./profiles/desktop.nix
        ];
        server = mkSystem [
          ./hosts/nixos
        ];
      };
    };
}
