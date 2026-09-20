{ lib, config, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # So `sudo nixos-rebuild switch` finds the flake without `--flake`:
  # nixos-rebuild looks for /etc/nixos/flake.nix by default. Only touches the
  # link when nothing unexpected already lives at /etc/nixos.
  system.activationScripts.etcNixosFlakeLink = lib.stringAfter [ "etc" ] ''
    target=${lib.escapeShellArg config.host.flakeDir}
    link=/etc/nixos
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "warning: $link exists and is not a symlink; leaving it alone (host.flakeDir wants it to point at $target)" >&2
    else
      ln -sfn "$target" "$link"
    fi
  '';

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
