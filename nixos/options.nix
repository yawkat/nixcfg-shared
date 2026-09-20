{ lib, ... }:
{
  options.host = {
    disk.device = lib.mkOption {
      type = lib.types.str;
      description = "Whole-disk device the disko layout wipes and partitions.";
      example = "/dev/nvme0n1";
    };

    work = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this machine is a work computer. Configuration that is only
        wanted on personal machines is left out when this is set. Mirrors the
        home-manager-level option of the same name.
      '';
    };
  };
}
