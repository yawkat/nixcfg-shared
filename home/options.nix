{ lib, ... }:
{
  options.host = {
    work = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this machine is a work computer. Configuration that is only
        wanted on personal machines is left out when this is set.
      '';
    };

    idle = {
      dimAfter = lib.mkOption {
        # Upper and lower bound come from plasma-manager's dimDisplay option;
        # repeating them here turns a downstream type error into a clear one.
        type = lib.types.nullOr (lib.types.ints.between 20 600000);
        default = null;
        example = 300;
        description = ''
          Seconds of inactivity after which the screen dims. `null` never dims.
        '';
      };

      screenOffAfter = lib.mkOption {
        # Likewise from plasma-manager's turnOffDisplay option.
        type = lib.types.nullOr (lib.types.ints.between 30 600000);
        default = null;
        example = 600;
        description = ''
          Seconds of inactivity after which the screen turns off. `null` leaves
          the screen on indefinitely.
        '';
      };

      lockAfter = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 60 600000);
        default = null;
        example = 900;
        description = ''
          Seconds of inactivity after which the session locks. `null` never
          locks, which is what most of the desktops want.

          kscreenlocker stores this as whole minutes, so the value has to be a
          multiple of 60.
        '';
      };
    };

    panels = {
      screens = lib.mkOption {
        type = lib.types.listOf lib.types.ints.unsigned;
        default = [ 0 ];
        example = [ 0 1 ];
        description = ''
          Which screens get a bottom taskbar panel, identified by the same
          0-indexed screen number KDE itself uses. A single-monitor laptop
          just wants the default `[ 0 ]`; a desktop with independent monitors
          that each need their own taskbar lists every screen index here.
        '';
      };
    };
  };
}
