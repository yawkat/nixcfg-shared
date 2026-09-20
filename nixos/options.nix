{ lib, ... }:
{
  options.host = {
    disk.device = lib.mkOption {
      type = lib.types.str;
      description = "Whole-disk device the disko layout wipes and partitions.";
      example = "/dev/nvme0n1";
    };
  };
}
