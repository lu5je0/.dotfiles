{
  description = "lu5je0's NixOS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.qoder-deb = {
    url = "https://download.qoder.com/qoder-app/releases/latest/Qoder-linux-amd64.deb";
    flake = false;
  };

  outputs = { nixpkgs, qoder-deb, ... }:
    let
      mkSystem = modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs.qoderDeb = qoder-deb;
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
