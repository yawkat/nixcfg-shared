{ config, lib, ... }:
{
  programs.plasma.session.sessionRestore.restoreOpenApplicationsOnLogin = "startWithEmptySession";

  # Unbind the global F-key shortcuts. They're global, so they swallow the
  # same keys in every app (IntelliJ uses Ctrl+F1-F4, F7, F9, F10 and F12).
  # With a single virtual desktop the "Switch to Desktop" ones do nothing
  # anyway. Alt+F4 (close window) stays. The Meta key still opens the
  # launcher; only its Alt+F1 alternative is dropped. kglobalaccel rewrites
  # kglobalshortcutsrc at runtime, so this goes through plasma-manager
  # rather than qt.kde.settings; an empty list is written as "none".
  programs.plasma.shortcuts = {
    kwin = {
      "Expose" = [ ];
      "ExposeAll" = [ ];
      "ExposeClass" = [ ];
      "Switch to Desktop 1" = [ ];
      "Switch to Desktop 2" = [ ];
      "Switch to Desktop 3" = [ ];
      "Switch to Desktop 4" = [ ];
      "Window Operations Menu" = [ ];
    };
    plasmashell = {
      "activate application launcher" = "Meta";
      "show dashboard" = [ ];
    };
  };

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

      # SDDM autologin (nixos/desktop.nix) skips the greeter on the DM
      # service's first start, but a killed/crashed display-manager service
      # takes the active session down with it (they share a systemd cgroup)
      # and then re-autologins unconditionally on restart. "Switch User" on
      # the lock screen is the one path to an unauthenticated SDDM greeter
      # process while a session is locked, so it's the one crash-to-restart
      # surface reachable without already being logged in. Disabling it here
      # removes that surface rather than just hiding the button.
      "KDE Action Restrictions" = {
        "action/switch_user" = false;
        "action/start_new_session" = false;
      };
    };

    plasmarc.Theme.name = lib.mkDefault "breeze-dark";

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

    # Turn the Overview effect off. Plasma 6 ships it enabled and bound to the
    # top-left hot corner, so it takes over the screen whenever the pointer
    # merely passes through that corner on its way somewhere else. Disabling
    # the plugin removes the effect itself (and with it Meta+W); the screen
    # edge is pinned to KWin's ElectricNone (9) as well, so the corner stays
    # inert even if something re-enables the plugin behind our back.
    #
    # The Zoom effect goes too: it binds Meta+Plus / Meta+= / Meta+Minus to
    # magnify the whole screen, which is too easy to hit by accident. With
    # the plugin unloaded KWin never registers those global shortcuts.
    #
    # Likewise the tiling editor (Meta+T). Only the editor UI goes; the
    # Meta+arrow quick-tile shortcuts are part of KWin core and keep working.
    kwinrc = {
      Plugins.overviewEnabled = false;
      "Effect-overview".BorderActivate = 9;
      Plugins.zoomEnabled = false;
      Plugins.tileseditorEnabled = false;
    };

    # Silence the "device plugged in"/"device unplugged" notifications
    # entirely. Both events live in plasma_workspace.notifyrc with
    # Action=Popup|Sound by default; clearing Action drops the popup and the
    # sound.
    "plasma_workspace.notifyrc" = {
      "Event/deviceAdded".Action = "";
      "Event/deviceRemoved".Action = "";
    };
  };
}
