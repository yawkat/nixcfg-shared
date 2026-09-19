{ pkgs, ... }:
{
  # Reset the root subvolume to a pristine snapshot on every boot. Everything
  # that must survive lives on the @nix, @persist and @home subvolumes instead.
  # The @root-blank snapshot is created once at install time.
  boot.initrd.systemd.services.rollback-root = {
    description = "Rollback btrfs root subvolume to a blank state";
    wantedBy = [ "initrd.target" ];
    requires = [ "systemd-cryptsetup@cryptroot.service" ];
    after = [ "systemd-cryptsetup@cryptroot.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /rollback
      mount -o subvol=/ /dev/mapper/cryptroot /rollback

      # Delete any nested subvolumes below @root before deleting @root itself,
      # otherwise the delete fails.
      btrfs subvolume list -o /rollback/@root \
        | cut -f9 -d' ' \
        | while read -r subvol; do
            btrfs subvolume delete "/rollback/$subvol"
          done
      btrfs subvolume delete /rollback/@root

      btrfs subvolume snapshot /rollback/@root-blank /rollback/@root

      umount /rollback
    '';
  };

  boot.initrd.systemd.initrdBin = [
    pkgs.btrfs-progs
    pkgs.coreutils
  ];

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/bluetooth"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
