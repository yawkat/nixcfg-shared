{ config, ... }:
let
  commonMountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  disko.devices.disk.main = {
    device = config.host.disk.device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = commonMountOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = commonMountOptions;
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = commonMountOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = commonMountOptions;
                };
              };
            };
          };
        };
      };
    };
  };

  # /persist and /nix hold the real state; make sure they are mounted before
  # anything that writes to them during activation.
  fileSystems."/persist".neededForBoot = true;
}
