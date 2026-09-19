{ ... }:
{
  gtk = {
    enable = true;
    colorScheme = "dark";
  };

  qt.kde.settings = {
    "plasma-localerc".Formats.LC_TIME = "en_DK.UTF-8";

    kdeglobals = {
      KDE.LookAndFeelPackage = "org.kde.breezedark.desktop";
      General.ColorScheme = "BreezeDark";
      Icons.Theme = "breeze-dark";
    };

    plasmarc.Theme.name = "breeze-dark";
    powerdevilrc.AC.Display.TurnOffDisplayWhenIdle = false;
  };
}
