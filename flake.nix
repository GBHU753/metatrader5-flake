{
  description = "MetaTrader 5 home-manager module (Wine-based)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    homeManagerModules.metatrader5 = import ./modules/metatrader5.nix;
    homeManagerModules.default     = self.homeManagerModules.metatrader5;
  };
}
