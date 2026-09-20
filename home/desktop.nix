{ config, lib, ... }:
{
  gtk = {
    enable = true;
    colorScheme = "dark";

    # Don't manage ~/.gtkrc-2.0. Plasma's kde-gtk-config daemon rewrites that
    # file whenever appearance settings are applied, which turns the Home
    # Manager symlink back into a regular file and makes the *next* activation
    # abort with "would be clobbered" — taking every other user unit and file
    # in the generation down with it. Nothing is lost by backing off: GTK 2 has
    # no color-scheme setting, so the file Home Manager generates here is
    # empty. colorScheme still reaches GTK 3/4 via their settings.ini.
    gtk2.enable = false;
  };

  qt.kde.settings = {
    "plasma-localerc".Formats.LC_TIME = "en_DK.UTF-8";

    kdeglobals = {
      KDE.LookAndFeelPackage = "org.kde.breezedark.desktop";
      General.ColorScheme = "BreezeDark";
      Icons.Theme = "breeze-dark";
    };

    plasmarc.Theme.name = "breeze-dark";

    baloofilerc.General = {
      # Index file names only, never file contents. Content indexing runs
      # baloo_file_extractor, which on a dev machine walks build trees and
      # archives: here it grew to ~10G resident+swap, filled the 16G zram
      # (the only swap we have), and pushed plasmashell and kwin out to
      # swap. Faulting them back in is what stalls the cursor. KRunner and
      # Dolphin still find files by name, which is what we actually use.
      "only basic indexing" = true;

      # Baloo writes this key as "exclude folders[$e]" so it can expand
      # $HOME, but qt.kde.settings goes through kwriteconfig6, which escapes
      # the brackets to \x5b/\x5d and leaves baloo ignoring the entry
      # entirely. A plain key does get read, so the paths have to be
      # absolute here -- "$HOME/..." would be taken literally.
      "exclude folders" = lib.concatStringsSep "," [
        "${config.home.homeDirectory}/dev/"
        "${config.home.homeDirectory}/Downloads/"
      ];
    };
  };
}
