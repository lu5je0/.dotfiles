{ ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      gtk-frdp = final.callPackage ./. {
        inherit (prev) gtk-frdp fetchFromGitLab;
      };
    })
  ];
}
