{
  config,
  lib,
  pkgs,
  ...
}:
let
  firefoxAddon =
    {
      pname,
      version,
      addonId,
      url,
      hash,
      license,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl { inherit url hash; };
      dontUnpack = true;

      installPhase = ''
        runHook preInstall

        install -Dm644 "$src" \
          "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${addonId}.xpi"

        runHook postInstall
      '';

      passthru = { inherit addonId; };
      meta = { inherit license; };
    };

  ublockOrigin = firefoxAddon {
    pname = "ublock-origin";
    version = "1.74.0";
    addonId = "uBlock0@raymondhill.net";
    url = "https://addons.mozilla.org/firefox/downloads/file/4981431/ublock_origin-1.74.0.xpi";
    hash = "sha256-F1dW10RoybpFhj9/wzPTvmcPgtWwZjFOkVgU3VR9FlI=";
    license = pkgs.lib.licenses.gpl3Only;
  };

  tabReloader = firefoxAddon {
    pname = "tab-reloader";
    version = "0.6.8";
    addonId = "jid0-bnmfwWw2w2w4e4edvcdDbnMhdVg@jetpack";
    url = "https://addons.mozilla.org/firefox/downloads/file/4805316/tab_reloader-0.6.8.xpi";
    hash = "sha256-0DP1xSfQUNFCTeoogi0RsiPBuQO5x8ECCftevb9qWCk=";
    license = pkgs.lib.licenses.mpl20;
  };

  sponsorBlock = firefoxAddon {
    pname = "sponsorblock";
    version = "6.1.7";
    addonId = "sponsorBlocker@ajay.app";
    url = "https://addons.mozilla.org/firefox/downloads/file/4897574/sponsorblock-6.1.7.xpi";
    hash = "sha256-DVDhYyxvFe4VpUPmcOHFcpdGBaXAJiKRbgjgJoA9+D8=";
    license = pkgs.lib.licenses.lgpl3Only;
  };

  redditEnhancer = firefoxAddon {
    pname = "reddit-enhancer";
    version = "3.5.1";
    addonId = "{46abbc04-ce38-475f-9ef8-e0a4a59d0c9f}";
    url = "https://addons.mozilla.org/firefox/downloads/file/4957758/reddit_enhancer-3.5.1.xpi";
    hash = "sha256-YcmSYqBSwoDG6I82B+4x8mlqrPXDgZzfT9ipJNVP2EE=";
    # AMO lists a custom license with no text, and the upstream repository
    # ships none, so no rights are granted. Treat it as unfree.
    license = {
      fullName = "Reddit Enhancer custom license";
      url = "https://addons.mozilla.org/en-US/firefox/addon/reddit-enhancer/license/";
      free = false;
    };
  };

  plasmaIntegration = firefoxAddon {
    pname = "plasma-integration";
    version = "2.1";
    addonId = "plasma-browser-integration@kde.org";
    url = "https://addons.mozilla.org/firefox/downloads/file/4614817/plasma_integration-2.1.xpi";
    hash = "sha256-Nb+jdm4JcWDnT1Jb3lTZe7upDXJdqkJbneb+9uxenUQ=";
    license = pkgs.lib.licenses.gpl3Only;
  };

  # Only wanted on personal machines; work profiles stay minimal.
  personalAddons = [
    sponsorBlock
    redditEnhancer
    plasmaIntegration
  ];
in
{
  programs.firefox = {
    enable = true;
    # The plasma-browser-integration extension talks to this native
    # messaging host to forward downloads/media controls/KDE Connect
    # sharing to the Plasma desktop.
    nativeMessagingHosts = lib.optionals (!config.host.work) [
      pkgs.kdePackages.plasma-browser-integration
    ];
    profiles.default = {
      name = "default";
      path = "default";
      isDefault = true;
      settings."extensions.autoDisableScopes" = 0;
      extensions.packages = [
        ublockOrigin
        tabReloader
      ]
      ++ lib.optionals (!config.host.work) personalAddons;
    };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
    };
  };
}
