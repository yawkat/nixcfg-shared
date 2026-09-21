{
  config,
  lib,
  pkgs,
  ...
}:
let
  themeId = "breeze-dark-work";
  theme = pkgs.runCommand "plasma-work-panel-theme" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python ${../pkgs/panel-theme.py} \
      ${pkgs.kdePackages.libplasma}/share/plasma/desktoptheme \
      $out '#3b2b4b' ${themeId}
  '';
  indicator = pkgs.callPackage ../pkgs/input-indicator.nix { };
in
{
  xdg.dataFile = lib.mkIf config.host.work {
    "plasma/desktoptheme/${themeId}".source = theme;
  };
  qt.kde.settings = lib.mkIf config.host.work {
    plasmarc.Theme.name = themeId;
  };

  home.packages = [ indicator ];
  systemd.user.services.input-indicator = {
    Unit = {
      Description = "Keyboard and mouse switch connection indicator";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe indicator;
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
