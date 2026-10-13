{ lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  # Every generation with a new kernel or initrd adds ~40M to the 512M ESP,
  # and nix.gc doesn't remove generations that still have boot entries, so
  # without a limit /boot fills up and a rebuild fails halfway through.
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # So `sudo nixos-rebuild switch` finds the flake without `--flake`:
  # nixos-rebuild looks for /etc/nixos/flake.nix by default. Only touches the
  # link when nothing unexpected already lives at /etc/nixos.
  system.activationScripts.etcNixosFlakeLink = lib.stringAfter [ "etc" ] ''
    target=/home/yawkat/nixcfg
    link=/etc/nixos
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "warning: $link exists and is not a symlink; leaving it alone (wanted to point it at $target)" >&2
    else
      ln -sfn "$target" "$link"
    fi
  '';

  # Every machine with the default module is a physical PC. Warnings go out
  # through failure-notify.nix.
  services.smartd.enable = true;

  # systemd in initrd gives a clean LUKS passphrase prompt and lets the
  # blank-root rollback run as an ordered service before the root mount.
  boot.initrd.systemd.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    # Garbage-collect during a build when free space drops below 5G, up to
    # 20G free, instead of failing the build with ENOSPC.
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 20 * 1024 * 1024 * 1024;
  };
  # Keep a runaway build from taking the desktop down with it. Without a cap,
  # builds fill RAM and then the zram swap, the machine thrashes for minutes,
  # and the global OOM killer finally picks a victim by oom_score -- which
  # favours Electron apps (adj 200-300), so it killed the tiny `nix` client
  # inside Claude's cgroup rather than the build eating the memory. With
  # MemoryMax the kernel OOMs inside nix-daemon.service instead and kills a
  # builder straight away; that build fails, nothing else is touched.
  # MemoryHigh is deliberately unset: it would throttle normal big builds.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "80%";
    # zram is the only swap, and the desktop needs it more than builds do.
    MemorySwapMax = "4G";
    # Builders inherit this, so a global OOM still prefers them over apps.
    OOMScoreAdjust = 500;
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
  boot.kernel.sysctl = {
    # The kernel defaults assume swap on a disk, where swapping is expensive
    # and reading neighbouring pages ahead pays off. Neither holds for zram;
    # these are the values Fedora and Pop!_OS ship for it.
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    # Allow all magic SysRq functions (NixOS allows only sync), so a frozen
    # desktop can still be rescued with Alt+SysRq+F (OOM kill) or REISUB.
    "kernel.sysrq" = 1;
  };

  # btrfs already discards asynchronously, but a weekly trim catches what
  # that skips. The LUKS layer passes discards through (allowDiscards in
  # disk.nix).
  services.fstrim.enable = true;

  # Faster and more robust under load than the reference dbus-daemon; the
  # default on Fedora and Arch.
  services.dbus.implementation = "broker";

  environment.systemPackages = with pkgs; [
    git
    vim
  ];
}
