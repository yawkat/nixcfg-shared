{ config, ... }:
let
  # Everything else in the tray beyond the always-visible clock/kickoff/tasks
  # row, carried over unchanged from the panel Plasma had set up by hand
  # before this module existed, so switching to declarative panels doesn't
  # rearrange anything that was already there.
  systemTrayExtraItems = [
    "org.kde.plasma.cameraindicator"
    "org.kde.plasma.clipboard"
    "org.kde.plasma.devicenotifier"
    "org.kde.plasma.manage-inputmethod"
    "org.kde.plasma.mediacontroller"
    "org.kde.plasma.notifications"
    "org.kde.kscreen"
    "org.kde.plasma.battery"
    "org.kde.plasma.brightness"
    "org.kde.plasma.keyboardindicator"
    "org.kde.plasma.keyboardlayout"
    "org.kde.plasma.volume"
    "org.kde.plasma.weather"
    "org.kde.kdeconnect"
  ];

  mkPanel = screen: {
    inherit screen;
    location = "bottom";
    widgets = [
      "org.kde.plasma.kickoff"
      "org.kde.plasma.pager"
      {
        iconTasks = {
          launchers = [
            "applications:com.mitchellh.ghostty.desktop"
            "applications:firefox.desktop"
          ];

          # Plasma 6 defaults to grouping every window of an application
          # under one icon, so telling two windows of the same app apart
          # takes an extra click. One icon per window instead.
          behavior.grouping.method = "none";
        };
      }
      "org.kde.plasma.marginsseparator"
      { systemTray.items.extra = systemTrayExtraItems; }
      "org.kde.plasma.digitalclock"
      "org.kde.plasma.showdesktop"
    ];
  };
in
{
  # plasma-manager applies this by deleting and regenerating
  # plasma-org.kde.plasma.desktop-appletsrc wholesale on the next Plasma
  # login, so from here on the panel layout lives in Nix, not in whatever
  # the systemsettings GUI last wrote.
  programs.plasma.panels = map mkPanel config.host.panels.screens;
}
