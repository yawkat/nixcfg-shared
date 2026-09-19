{ config, lib, ... }:
{
  programs.ghostty = {
    enable = true;
    settings.theme = "Ayu";
  };

  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "com.mitchellh.ghostty.desktop" ];
  };

  qt.kde.settings.kdeglobals.General = {
    TerminalApplication = "${lib.getExe config.programs.ghostty.package} --gtk-single-instance=true";
    TerminalService = "com.mitchellh.ghostty.desktop";
  };
}
