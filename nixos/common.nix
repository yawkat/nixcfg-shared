{ lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # systemd in initrd gives a clean LUKS passphrase prompt and lets the
  # blank-root rollback run as an ordered service before the root mount.
  boot.initrd.systemd.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nixpkgs.config.allowUnfree = true;

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings.LC_TIME = "en_DK.UTF-8";
  time.timeZone = lib.mkDefault "UTC";

  console.keyMap = "de-latin1-nodeadkeys";

  zramSwap.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
  ];
}
