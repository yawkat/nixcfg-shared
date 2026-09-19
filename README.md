# Shared Nix configuration

This repository exports an opinionated Home Manager module containing my
portable shell and desktop preferences. Host identity, operating-system setup,
and machine-specific packages belong in the consuming configuration.

No license is granted for this repository.

## Flake output

- `homeManagerModules.default`: shared packages plus Git, VS Code, Zsh,
  Starship, Firefox, Ghostty, GTK, and KDE preferences.

The package set includes unfree software, so consumers must enable
`nixpkgs.config.allowUnfree`.

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
configuration. Future system-wide settings can be published independently as
`nixosModules` without changing the Home Manager interface.
