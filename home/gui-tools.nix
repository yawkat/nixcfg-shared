{ password-java }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Personal GUI tools, so they follow the shared config onto personal machines
  # but stay off work machines (which set host.work). paste-cli ships a
  # Spectacle "Open With" entry and a Dolphin service menu; password-gui ships
  # its desktop entry.
  paste-cli = pkgs.callPackage ../pkgs/paste-cli.nix { };
  # password-gui comes from the upstream flake, see the input in flake.nix;
  # `nix flake update password-java` bumps it.
  password-gui = password-java.packages.${pkgs.stdenv.hostPlatform.system}.app;
in
{
  home.packages = lib.optionals (!config.host.work) (
    [
      paste-cli
      pkgs.vlc
      pkgs.mpv
      pkgs.gimp
      pkgs.ffmpeg
      pkgs.thunderbird
    ]
    # password-gui bundles x86_64-only Skiko native libraries, and upstream
    # only exposes the app package there.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ password-gui ]
  );

  # paste-cli reads this on every run; without it the client falls back to its
  # compiled-in default of http://127.0.0.1:8080 and every upload fails with
  # "Connection refused". Only the endpoint goes here: the RSA keypair that
  # authenticates against it stays at ~/.config/paste/key, which is a secret
  # and is covered by the restic backup of ~/.config instead.
  home.file.".config/paste/config.json" = lib.mkIf (!config.host.work) {
    text = builtins.toJSON { remote = "https://s.yawk.at/"; };
  };
}
