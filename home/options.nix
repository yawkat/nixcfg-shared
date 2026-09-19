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
  };
}
