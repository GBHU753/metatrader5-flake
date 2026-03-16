{ config, lib, pkgs, ... }:

let
  cfg = config.programs.metatrader5;

  # Load hashes from the pinned hashes.json sitting next to this file.
  # When hashes are empty strings (initial state before first update.sh run)
  # we fall back to a placeholder and emit a warning so the module still evaluates.
  hashData = builtins.fromJSON (builtins.readFile ../hashes.json);

  hasMt5Hash     = hashData.mt5.hash     != "";
  hasWebviewHash = hashData.webview2.hash != "";

  # Placeholder used before update.sh has been run for the first time.
  # fetchurl will fail with a hash-mismatch error, which tells the user to
  # run ./update.sh.  The warn call surfaces a human-readable message too.
  placeholderHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  mt5Hash = if hasMt5Hash then hashData.mt5.hash else
    lib.warn
      "metatrader5: hashes.json contains no mt5 hash — run ./update.sh first"
      placeholderHash;

  webviewHash = if hasWebviewHash then hashData.webview2.hash else
    lib.warn
      "metatrader5: hashes.json contains no webview2 hash — run ./update.sh first"
      placeholderHash;

  # Fetch the installers at build time (fixed-output derivations).
  # Re-fetched automatically whenever hashes.json is updated by the nightly job.
  mt5Installer = pkgs.fetchurl {
    url  = hashData.mt5.url;
    hash = mt5Hash;
  };

  webview2Installer = pkgs.fetchurl {
    url  = hashData.webview2.url;
    hash = webviewHash;
  };

  # Wine binary paths — wineWow64Packages ships wine and wine64 side by side
  wine    = "${cfg.winePackage}/bin/wine";
  wine64  = "${cfg.winePackage}/bin/wine64";
  winecfg = "${cfg.winePackage}/bin/winecfg";

  # Set the Windows version in the registry without spawning a GUI winecfg.
  setWin11Reg = pkgs.writeShellScript "mt5-set-win11" ''
    export WINEPREFIX="$1"
    # Initialise the prefix first (wineboot -u = update without showing splash)
    ${wine64} wineboot --init
    # Set Windows version to Windows 11 via the command-line flag
    ${winecfg} /v win11
  '';

  # One-shot installer script executed at first login (or manually via mt5-install)
  installerScript = pkgs.writeShellScript "mt5-install" ''
    set -euo pipefail

    export WINEPREFIX="${cfg.winePrefix}"
    STAMP="$WINEPREFIX/.mt5-installed"

    if [ -f "$STAMP" ]; then
      echo "MetaTrader 5 already installed in $WINEPREFIX — skipping."
      exit 0
    fi

    echo "==> Initialising Wine prefix and setting Windows 11 compatibility..."
    ${setWin11Reg} "$WINEPREFIX"

    echo "==> Installing WebView2 Runtime (silent)..."
    ${wine} ${webview2Installer} /silent /install

    # Wait for any background wine processes spawned by the installer to settle
    ${wine64} wineserver --wait

    echo "==> Running MetaTrader 5 installer..."
    echo "    Follow the on-screen wizard.  Close it when done."
    ${wine} ${mt5Installer}

    ${wine64} wineserver --wait

    touch "$STAMP"
    echo "==> MetaTrader 5 installation complete."
  '';

  # Launcher: runs terminal64.exe from the configured prefix
  mt5Launcher = pkgs.writeShellScriptBin "mt5" ''
    export WINEPREFIX="${cfg.winePrefix}"
    MT5_EXE="$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"

    if [ ! -f "$MT5_EXE" ]; then
      echo "MetaTrader 5 is not installed yet.  Run 'mt5-install' first."
      exit 1
    fi

    exec ${wine} "$MT5_EXE" "$@"
  '';

  # Expose the installer as a runnable command
  mt5InstallBin = pkgs.writeShellScriptBin "mt5-install" ''
    exec ${installerScript}
  '';

in
{
  ###########################################################################
  # Options
  ###########################################################################
  options.programs.metatrader5 = {
    enable = lib.mkEnableOption "MetaTrader 5 (via Wine)";

    winePackage = lib.mkOption {
      type        = lib.types.package;
      default     = pkgs.wineWow64Packages.staging;
      defaultText = lib.literalExpression "pkgs.wineWow64Packages.staging";
      description = ''
        Wine package to use.  Must provide both 32- and 64-bit Wine
        binaries (required by MT5).  Defaults to
        `pkgs.wineWow64Packages.staging`.
      '';
    };

    winePrefix = lib.mkOption {
      type        = lib.types.str;
      default     = "${config.home.homeDirectory}/.mt5";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.mt5"'';
      description = ''
        Path to the Wine prefix used for MetaTrader 5.
      '';
    };

    autoInstall = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        When true a systemd user service runs `mt5-install` automatically
        after the graphical session starts (one-shot; skipped if already
        installed).  Requires a graphical session.

        When false, run `mt5-install` manually after logging in.
      '';
    };
  };

  ###########################################################################
  # Implementation
  ###########################################################################
  config = lib.mkIf cfg.enable {

    home.packages = [
      cfg.winePackage
      pkgs.winetricks
      mt5Launcher
      mt5InstallBin
    ];

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

    # Optional systemd user service for automatic first-run installation.
    # home-manager manages the wantedBy symlink natively.
    systemd.user.services.mt5-install = lib.mkIf cfg.autoInstall {
      Unit = {
        Description = "MetaTrader 5 first-run installer";
        After       = [ "graphical-session.target" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type            = "oneshot";
        ExecStart       = "${installerScript}";
        RemainAfterExit = true;
        Restart         = "no";
      };
    };
  };
}
