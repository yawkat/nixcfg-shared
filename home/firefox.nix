{ pkgs, ... }:
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

  redditEnhancementSuite = firefoxAddon {
    pname = "reddit-enhancement-suite";
    version = "5.24.10";
    addonId = "jid1-xUfzOsOFlzSOXg@jetpack";
    url = "https://addons.mozilla.org/firefox/downloads/file/4899821/reddit_enhancement_suite-5.24.10.xpi";
    hash = "sha256-RXPP2xAZNGfpnh3Vp5LyOuaXZFQMLgbQRE8SqBzcTwo=";
    license = pkgs.lib.licenses.gpl3Only;
  };
in
{
  programs.firefox = {
    enable = true;
    profiles.default = {
      name = "default";
      path = "default";
      isDefault = true;
      settings."extensions.autoDisableScopes" = 0;
      extensions.packages = [
        ublockOrigin
        tabReloader
        sponsorBlock
        redditEnhancementSuite
      ];
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
