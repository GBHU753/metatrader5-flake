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
    # Set Windows version to 11 (required by MT5)
    wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' \
      /v CurrentVersion /d "10.0" /f
    winecfg -v win11

    # Install WebView2 silently
    wine ${webview2Installer} /silent /install
    wineserver -w

    # Run the MT5 installer — interactive GUI wizard
    wine ${mt5Installer}
    wineserver -w
  '';

  # winAppRun executes on every launch.
  winAppRun = ''
    wine "${mt5Exe}" "$ARGS"
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
