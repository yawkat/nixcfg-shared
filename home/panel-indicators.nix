{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.host.panels;
  themeId = "breeze-dark-machine";
  theme = pkgs.runCommand "plasma-machine-panel-theme" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python ${../pkgs/panel-theme.py} \
      ${pkgs.kdePackages.libplasma}/share/plasma/desktoptheme \
      $out ${lib.escapeShellArg cfg.color} ${themeId}
  '';
  indicator = pkgs.callPackage ../pkgs/input-indicator.nix { };
  deviceConfig = pkgs.writeText "input-indicator-devices.json" (
    builtins.toJSON cfg.inputIndicator.devices
  );
in
{
  options.host.panels = {
    color = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "#[0-9a-fA-F]{6}");
      default = if config.host.work then "#29495e" else "#583f31";
      description = ''
        Fixed panel background color: muted blue for work and muted brown for
        personal machines. Override per host to distinguish more computers.
        Set null to retain the unmodified Breeze Dark panel.
      '';
    };
    inputIndicator = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show USB keyboard/mouse connection state in every panel's tray.";
      };
      devices = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption { type = lib.types.str; };
              vendorId = lib.mkOption { type = lib.types.strMatching "[0-9a-fA-F]{4}"; };
              productId = lib.mkOption { type = lib.types.strMatching "[0-9a-fA-F]{4}"; };
            };
          }
        );
        default = [
          {
            name = "Razer DeathAdder V2";
            vendorId = "1532";
            productId = "0084";
          }
          {
            name = "Das Keyboard";
            vendorId = "24f0";
            productId = "0140";
          }
        ];
        description = ''
          USB devices on the keyboard/mouse switch. The indicator is connected
          when all listed devices are present, and disconnected otherwise.
          Identification uses USB vendor/product IDs, never event node numbers.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.color != null) {
      xdg.dataFile."plasma/desktoptheme/${themeId}".source = theme;
      qt.kde.settings.plasmarc.Theme.name = themeId;
    })
    (lib.mkIf cfg.inputIndicator.enable {
      assertions = [
        {
          assertion = cfg.inputIndicator.devices != [ ];
          message = "host.panels.inputIndicator.devices must contain at least one USB device.";
        }
      ];
      home.packages = [ indicator ];
      xdg.configFile."input-indicator/devices.json".source = deviceConfig;
      systemd.user.services.input-indicator = {
        Unit = {
          Description = "Keyboard and mouse switch connection indicator";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe indicator} --config ${deviceConfig}";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ];
}
