# Shared Nix configuration

This repository exports an opinionated Home Manager module containing my
portable shell and desktop preferences. Host identity, operating-system setup,
and machine-specific packages belong in the consuming configuration.

No license is granted for this repository.

## Flake output

- `homeManagerModules.default`: shared packages plus Git, VS Code, IntelliJ
  IDEA, JDKs, Zsh, Starship, Firefox, Ghostty, GTK, KDE preferences, and the
  personal GUI tools below.

The package set includes unfree software, so consumers must enable
`nixpkgs.config.allowUnfree`.

Also exposed for building directly: `packages.<system>.{paste-cli,password-gui}`
and `overlays.default`.

### Packaged GUI tools

Built from source and installed by `homeManagerModules.default` on personal
machines (gated on `host.work`, see below):

- `paste-cli`: the [paste](https://github.com/yawkat/paste) CLI (`paste-cli`),
  with `wl-clipboard`, `libnotify`, and `xdg-utils` on its path. It ships a
  Spectacle *Export → Open With* entry (`image/png;image/jpeg`) and a Dolphin
  *Share via paste* service menu, so screenshots and files upload straight from
  Plasma. Named `paste-cli` so it does not shadow coreutils' `paste`.
- `password-gui`: the QtJambi [password](https://github.com/yawkat/password-java)
  manager GUI (x86_64 only — QtJambi's native library is x86_64). The QtJambi
  version is pinned to whatever Qt 6 nixpkgs ships (via `-Dqtjambi.version`), and
  the wrapper points it at the system Qt and defaults to the Wayland platform.

`kdePackages.spectacle` is in the shared packages unconditionally, so it is on
every machine.

### Options

- `host.work` — mark the machine as a work computer (default `false`).
  Configuration that is only wanted on personal machines is left out when this
  is set: the personal-only Firefox addons (SponsorBlock and Reddit Enhancement
  Suite) and the packaged GUI tools above. Set it in the consuming Home Manager
  configuration:

  ```nix
  host.work = true;
  ```

- `host.idle` — the per-machine idle timeouts, all in seconds and all `null`
  by default, which means "never". Standby itself is not configurable: it is
  off everywhere, and the power button always shuts down.

  | Option | Default | Effect |
  | --- | --- | --- |
  | `host.idle.dimAfter` | `null` | Seconds before the screen dims (20–600000). |
  | `host.idle.screenOffAfter` | `null` | Seconds before the screen turns off (30–600000). |
  | `host.idle.lockAfter` | `null` | Seconds before the session locks (60–600000). |

  Leaving `lockAfter` at `null` sets `Autolock=false`, so a machine that should
  never lock needs no configuration at all. kscreenlocker stores its timeout as
  whole minutes, so `lockAfter` has to be a multiple of 60.

  ```nix
  host.idle = {
    dimAfter = 300;
    screenOffAfter = null;
    lockAfter = 900;
  };
  ```

## Standalone Home Manager

Add this repository as an input, make its Nixpkgs and Home Manager inputs
follow the consumer, and import the module:

```nix
inputs.shared-config = {
  url = "github:yawkat/nixcfg-shared";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};

home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    inputs.shared-config.homeManagerModules.default
    ./home.nix
  ];
}
```

The consuming `home.nix` must set `home.username`, `home.homeDirectory`, and
`home.stateVersion`.

## NixOS with Home Manager

Use Home Manager as a NixOS module and import the shared module for the user:

```nix
modules = [
  home-manager.nixosModules.home-manager
  {
    home-manager.useGlobalPkgs = true;
    home-manager.users.my-user.imports = [
      shared-config.homeManagerModules.default
    ];
  }
];
```

System services, desktop sessions, and portals remain part of the NixOS host
configuration.

## NixOS system modules

This repository also exports reusable, host-agnostic `nixosModules` for full
NixOS machines. Host identity (hostname, disk device, networking, passwords,
`stateVersion`) is **not** part of these modules; a consuming per-host flake
supplies it.

- `nixosModules.default`: bootloader (systemd-boot), Nix flake settings and GC,
  locale, German (nodeadkeys) keyboard, zram swap, KDE Plasma 6 on Wayland
  (SDDM), PipeWire, the `yawkat` user with a Zsh login shell, and a btrfs
  blank-root impermanence setup that resets `/` on every boot while persisting
  `/nix`, `/home`, and `/persist`.
- `nixosModules.diskLuksBtrfs`: a [disko](https://github.com/nix-community/disko)
  layout — GPT with an ESP plus a LUKS partition (interactive passphrase)
  holding a btrfs filesystem with `@root`, `@nix`, `@persist`, and `@home`
  subvolumes.

Networking is intentionally left to the host: a wired machine wants static
`systemd-networkd`, a laptop wants NetworkManager, so each host configures its
own (and persists any NetworkManager connections under `/persist` itself).

### Options

Set these in the consuming host module:

- `host.disk.device` — whole-disk device the disko layout wipes and partitions
  (e.g. `/dev/nvme0n1`).

### Consuming flake

The consumer imports the shared modules alongside its own `disko`,
`impermanence`, and `home-manager` inputs (the shared flake does not force
these on consumers):

```nix
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    disko.nixosModules.disko
    impermanence.nixosModules.impermanence
    home-manager.nixosModules.home-manager
    shared-config.nixosModules.default
    shared-config.nixosModules.diskLuksBtrfs
    ./hosts/<host>.nix
  ];
}
```

The per-host module sets `networking.hostName`, `host.disk.device`, networking,
`time.timeZone`, `system.stateVersion`, the user password, and wires the shared
Home Manager module for `yawkat`.

The blank-root impermanence setup expects a read-only `@root-blank` btrfs
snapshot to exist as a sibling of `@root`; create it once at install time, after
disko has formatted the disk, from the btrfs top-level subvolume:

```sh
mount -o subvol=/ /dev/mapper/cryptroot /mnt/btrfs-top
btrfs subvolume snapshot -r /mnt/btrfs-top/@root /mnt/btrfs-top/@root-blank
umount /mnt/btrfs-top
```

Future system-wide settings can be published as additional `nixosModules`
without changing the Home Manager interface.
