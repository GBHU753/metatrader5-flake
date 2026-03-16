{ config, lib, pkgs, ... }:

let
  cfg = config.programs.metatrader5;
in
{
  ###########################################################################
  # Options
  ###########################################################################
  options.programs.metatrader5 = {
    enable = lib.mkEnableOption "MetaTrader 5 (via Wine / mkWindowsApp)";

    package = lib.mkOption {
      type        = lib.types.package;
      description = ''
        The metatrader5 package to install.  Must be built with
        `mkWindowsApp` from erosanix.  Consumers should pass
        `inputs.metatrader5.packages.''${pkgs.system}.metatrader5` here,
        or override via `pkgs.callPackage`.
      '';
    };
  };

  ###########################################################################
  # Implementation
  ###########################################################################
  config = lib.mkIf cfg.enable {

    home.packages = [ cfg.package ];

    # Remind the user that graphics drivers must be enabled at the system level.
    # home-manager cannot set hardware.graphics options itself.
    warnings = [
      ''
        programs.metatrader5: Wine requires OpenGL and 32-bit driver support.
        Ensure your NixOS system configuration includes:
          hardware.graphics.enable      = true;
          hardware.graphics.enable32Bit = true;
      ''
    ];
  };
}
