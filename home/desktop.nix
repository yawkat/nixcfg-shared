{ ... }:
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
  };
}
