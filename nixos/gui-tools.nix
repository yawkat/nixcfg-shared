{ pkgs, ... }:
{
  # Packaged GUI tools, installed system-wide on full NixOS hosts only (the
  # system-manager machine consumes homeManagerModules.default, not this).
  # paste-cli ships a Spectacle "Open With" entry and a Dolphin service menu;
  # password-gui ships its desktop entry.
  nixpkgs.overlays = [
    (final: _prev: {
      paste-cli = final.callPackage ./pkgs/paste-cli.nix { };
      password-gui = final.callPackage ./pkgs/password-gui.nix { };
    })
  ];

  environment.systemPackages = [
    pkgs.paste-cli
    pkgs.password-gui
  ];
}
