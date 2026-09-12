{
  description = "Patched mark-shot（单色托盘图标 + GTK3 schema 修复），供 nix profile install 使用";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    mark-shot = {
      url = "github:jswysnemc/mark-shot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, mark-shot, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = import ./default.nix {
        inherit pkgs;
        flake = mark-shot;
      };
    };
}
