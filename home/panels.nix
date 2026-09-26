{ config, pkgs, ... }:
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

  # KDE's colour grid face prints each cell's value on top of its shade, with
  # no option to turn that off. This copy under its own id drops the labels
  # and nothing else; cell size still comes from the grid layout, not the text.
  quietColorGridId = "local.ksysguard.colorgrid-quiet";
  quietColorGrid = pkgs.runCommand quietColorGridId { nativeBuildInputs = [ pkgs.jq ]; } ''
    cp -r ${pkgs.kdePackages.libksysguard}/share/ksysguard/sensorfaces/org.kde.ksysguard.colorgrid $out
    chmod -R u+w $out
    substituteInPlace $out/contents/ui/FaceGrid.qml \
      --replace-fail "text: sensor.formattedValue" ""
    jq '.KPlugin.Id = "${quietColorGridId}" | .KPlugin.Name = "Color Grid (no labels)"' \
      $out/metadata.json > metadata.json
    mv metadata.json $out/metadata.json
  '';

  # The generic org.kde.plasma.systemmonitor applet, which the cpu/memory
  # presets are just defaults for. Sensor ids go into the config verbatim
  # rather than through plasma-manager's `sensors` option, which demands a
  # colour per id and can't express that `cpu/cpu.*/usage` is a wildcard
  # expanded to one sensor per core at runtime.
  mkSystemMonitor =
    {
      title,
      face,
      sensors,
      total,
      details,
      faceConfig,
      # Minimum milliseconds between redraws; 0 follows the sensor daemon.
      updateRateLimit ? 0,
    }:
    let
      # Plasma stores sensor lists as a JSON array inside a single string.
      idList = builtins.toJSON;
    in
    {
      systemMonitor = {
        inherit title;
        displayStyle = face;
        settings = {
          Appearance = { inherit updateRateLimit; };
          Sensors = {
            highPrioritySensorIds = idList sensors;
            totalSensors = idList [ total ];
            lowPrioritySensorIds = idList details;
          };
          "${face}/General" = faceConfig;
        };
      };
    };

  mkPanel = screen: {
    inherit screen;
    location = "bottom";
    opacity = if config.host.work then "opaque" else "adaptive";
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
      # KDE-maintained resource monitors, bundled with plasma-workspace.
      # One cell per core, shaded by that core's usage.
      (mkSystemMonitor {
        title = "CPU";
        face = quietColorGridId;
        # Per-core shades flicker at the daemon's default rate; a slower
        # refresh reads as load rather than noise.
        updateRateLimit = 2000;
        sensors = [ "cpu/cpu.*/usage" ];
        total = "cpu/all/usage";
        details = [
          "cpu/all/cpuCount"
          "cpu/all/coreCount"
        ];
        faceConfig = {
          # Theme highlight colour for every core, instead of a different
          # palette colour per core, so only the shade carries meaning.
          useSensorColor = false;
        };
      })
      # A single vertical bar filling up as physical memory is used.
      (mkSystemMonitor {
        title = "Memory";
        face = "org.kde.ksysguard.barchart";
        sensors = [ "memory/physical/usedPercent" ];
        total = "memory/physical/usedPercent";
        details = [
          "memory/physical/used"
          "memory/physical/total"
        ];
        faceConfig = {
          horizontalBars = false;
          showLegend = false;
          showGridLines = false;
          showYAxisLabels = false;
          rangeAuto = false;
          rangeFrom = 0;
          rangeTo = 100;
        };
      })
      "org.kde.plasma.marginsseparator"
      {
        systemTray.items = {
          extra = systemTrayExtraItems;
          shown = [ "shared-input-indicator" ];
        };
      }
      "org.kde.plasma.digitalclock"
      "org.kde.plasma.showdesktop"
    ];
  };
in
{
  home.packages = with pkgs.kdePackages; [
    ksystemstats
    plasma-systemmonitor
  ];
  xdg.dataFile."ksysguard/sensorfaces/${quietColorGridId}".source = quietColorGrid;
  # Register the upstream sensor service even outside a NixOS Plasma session.
  systemd.user.packages = [ pkgs.kdePackages.ksystemstats ];
  # The session bus may predate the Nix environment on non-NixOS hosts.
  # Its standard per-user service directory is always searched for activation.
  xdg.dataFile."dbus-1/services/org.kde.ksystemstats1.service".source =
    "${pkgs.kdePackages.ksystemstats}/share/dbus-1/services/org.kde.ksystemstats1.service";

  # plasma-manager applies this by deleting and regenerating
  # plasma-org.kde.plasma.desktop-appletsrc wholesale on the next Plasma
  # login, so from here on the panel layout lives in Nix, not in whatever
  # the systemsettings GUI last wrote.
  programs.plasma.panels = map mkPanel config.host.panels.screens;
}
