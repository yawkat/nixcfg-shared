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
  password-gui = pkgs.callPackage ../pkgs/password-gui.nix { };
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
    # password-gui bundles an x86_64-only QtJambi native library.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [ password-gui ]
  );
}
