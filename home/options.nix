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
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 300;
        description = ''
          Seconds of inactivity after which the screen dims. `null` never dims.
        '';
      };

      screenOffAfter = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 600;
        description = ''
          Seconds of inactivity after which the screen turns off. `null` leaves
          the screen on indefinitely.
        '';
      };

      lockAfter = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
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
  };
}
