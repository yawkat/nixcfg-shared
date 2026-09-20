{ lib, ... }:
{
  options.host = {
    disk.device = lib.mkOption {
      type = lib.types.str;
      description = "Whole-disk device the disko layout wipes and partitions.";
      example = "/dev/nvme0n1";
    };

    flakeDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        Absolute path to this host's flake checkout. Symlinked to
        `/etc/nixos` so plain `nixos-rebuild switch` (without `--flake`)
        finds it.
      '';
      example = "/home/user/nixcfg";
    };
  };
}
