{
  description = "MetaTrader 5 home-manager module (Wine-based)";

  inputs = {
    nixpkgs.url    = "github:NixOS/nixpkgs/nixos-unstable";
    erosanix.url   = "github:emmanuelrosa/erosanix";
    erosanix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, erosanix }:
  let
    systems = [ "x86_64-linux" ];
    forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f system);
  in
  {
    packages = forEachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        mkWindowsApp = erosanix.packages.${system}.mkwindowsapp;
      in {
        default    = self.packages.${system}.metatrader5;
        metatrader5 = pkgs.callPackage ./pkgs/metatrader5.nix {
          inherit mkWindowsApp;
          wine = pkgs.wineWow64Packages.staging;
        };
      });

    homeManagerModules.metatrader5 = import ./modules/metatrader5.nix;
    homeManagerModules.default     = self.homeManagerModules.metatrader5;
  };
}
