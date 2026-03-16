{
  description = "MetaTrader 5 NixOS module (Wine-based)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules.metatrader5 = import ./modules/metatrader5.nix;
    nixosModules.default     = self.nixosModules.metatrader5;
  };
}
