{ lib
, stdenv
, mkWindowsApp
, wine
, fetchurl
, makeDesktopItem
, copyDesktopItems
, imagemagick
}:

let
  # Hashes are pinned in hashes.json and kept fresh by the nightly CI job.
  hashData = builtins.fromJSON (builtins.readFile ../hashes.json);

  mt5Installer = fetchurl {
    url  = hashData.mt5.url;
    hash = hashData.mt5.hash;
  };

  webview2Installer = fetchurl {
    url  = hashData.webview2.url;
    hash = hashData.webview2.hash;
  };

  # MT5 installs to a path that includes the version number, so we glob for it.
  mt5Exe = "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe";

  icon = stdenv.mkDerivation {
    name = "metatrader5-icon";
    src  = fetchurl {
      url  = "https://c.mql5.com/favicon.ico";
      hash = "sha256-6AymGlwlum4SKRgwL8ASNx9xgvzc6sZLGDM3Zbzm90I=";
    };
    dontUnpack = true;
    nativeBuildInputs = [ imagemagick ];
    installPhase = ''
      for n in 16 24 32 48 64 96 128 256; do
        size="''${n}x''${n}"
        mkdir -p $out/hicolor/$size/apps
        magick $src -resize $size $out/hicolor/$size/apps/metatrader5.png
      done
    '';
  };

in mkWindowsApp rec {
  inherit wine;

  pname   = "metatrader5";
  version = "latest";    # upstream doesn't version the installer URL

  # MT5 is a 64-bit application
  wineArch = "win64";

  src = mt5Installer;
  dontUnpack = true;

  nativeBuildInputs = [ copyDesktopItems ];

  # winAppInstall runs inside the unionfs bottle on FIRST LAUNCH.
  # The Wine prefix is already initialised at this point.
  winAppInstall = ''
    # Set Windows version to 10/11 via registry (non-interactive).
    # winecfg -v requires a display and opens a GUI; use reg directly instead.
    $WINE reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' \
      /v CurrentVersion /t REG_SZ /d "10.0" /f
    $WINE reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' \
      /v CurrentBuildNumber /t REG_SZ /d "22621" /f
    $WINE reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' \
      /v CSDVersion /t REG_SZ /d "" /f
    $WINE reg add 'HKLM\System\CurrentControlSet\Control\Windows' \
      /v CSDVersion /t REG_DWORD /d 0 /f

    # Install WebView2 silently.
    # WebView2's bootstrapper spawns persistent background update processes
    # (edgeupdate) that never exit on their own under Wine, so we must NOT
    # use "wineserver -w" here — it would block forever.
    # Instead, run the installer and then forcibly kill all Wine processes
    # before proceeding to the MT5 installer.
    $WINE ${webview2Installer} /silent /install || true
    wineserver -k
    sleep 2

    # Run the MT5 installer — interactive GUI wizard.
    # The user must click through the setup wizard on the desktop.
    # MT5 auto-launches after install completes (the installer's default behaviour).
    # We use wineserver -k rather than wineserver -w so that the auto-launched MT5
    # and any background processes (updater, agent) are force-killed, allowing
    # mk_app_layer to finalise the layer cleanly without blocking.
    # The user launches MT5 normally via the metatrader5 command after this.
    $WINE ${mt5Installer}
    wineserver -k
    sleep 2
  '';

  # winAppRun executes on every launch.
  # DO NOT use wineserver -w here — mkWindowsApp manages the process lifecycle.
  # We background the Wine process and wait only for terminal64.exe to exit,
  # then force-kill any remaining Wine processes (MT5 updater, agent, etc.)
  # so that mkWindowsApp's subsequent wineserver -w returns immediately rather
  # than blocking indefinitely on lingering background processes.
  winAppRun = ''
    $WINE "${mt5Exe}" "$ARGS" &
    wait $!
    wineserver -k
  '';

  installPhase = ''
    runHook preInstall

    ln -s $out/bin/.launcher $out/bin/metatrader5
    mkdir -p $out/share/icons
    ln -s ${icon}/hicolor $out/share/icons

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name        = pname;
      exec        = pname;
      icon        = pname;
      desktopName = "MetaTrader 5";
      genericName = "Trading Platform";
      categories  = [ "Office" "Finance" ];
      comment     = "MetaTrader 5 trading platform (via Wine)";
    })
  ];

  meta = with lib; {
    description = "MetaTrader 5 multi-asset trading platform";
    homepage    = "https://www.metatrader5.com/";
    license     = licenses.unfree;
    platforms   = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
