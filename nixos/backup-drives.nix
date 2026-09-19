{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.host.backupDrives;
  enabled = cfg != { };

  driveModule =
    { name, config, ... }:
    {
      options = {
        transport = lib.mkOption {
          type = lib.types.str;
          default = "tcp";
          description = "NVMe-over-Fabrics transport (nvme connect --transport).";
        };
        address = lib.mkOption {
          type = lib.types.str;
          description = "Target address (nvme connect --traddr).";
          example = "10.0.5.1";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 4420;
          description = "Target service id (nvme connect --trsvcid).";
        };
        subsystemNqn = lib.mkOption {
          type = lib.types.str;
          description = "Subsystem NQN to connect to (nvme connect --nqn).";
        };
        hostNqn = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Host NQN to present (nvme connect --hostnqn). When null the system
            default from /etc/nvme/hostnqn is used.
          '';
        };
        dhchapSecretFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = if config.hostNqn == null then null else "/etc/credstore/nvme-dhchap-${config.hostNqn}";
          defaultText = lib.literalExpression ''"/etc/credstore/nvme-dhchap-''${hostNqn}"'';
          description = ''
            Path to a file holding the DH-HMAC-CHAP secret. Its contents are
            passed as nvme connect --dhchap-secret. Keep it under /etc/credstore
            so it survives on the persistent subvolume. Null disables auth.
          '';
        };
        partition = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "Partition on the namespace to unlock and mount.";
        };
        mapperName = lib.mkOption {
          type = lib.types.str;
          default = "backup-${name}";
          defaultText = lib.literalExpression ''"backup-''${name}"'';
          description = "device-mapper name for the opened LUKS volume.";
        };
        mountPoint = lib.mkOption {
          type = lib.types.str;
          default = "/mnt/backup-${name}";
          defaultText = lib.literalExpression ''"/mnt/backup-''${name}"'';
          description = "Where the decrypted filesystem is mounted.";
        };
      };
    };

  # A shell case statement that resolves the drive named in $1 into the
  # variables the mount/umount commands use. Sourced by both commands.
  resolveLib = pkgs.writeText "backup-drives-lib.sh" ''
    resolve_drive() {
      case "$1" in
      ${lib.concatStrings (
        lib.mapAttrsToList (name: d: ''
          ${lib.escapeShellArg name})
            transport=${lib.escapeShellArg d.transport}
            address=${lib.escapeShellArg d.address}
            port=${lib.escapeShellArg (toString d.port)}
            subnqn=${lib.escapeShellArg d.subsystemNqn}
            hostnqn=${lib.escapeShellArg (if d.hostNqn == null then "" else d.hostNqn)}
            secretfile=${lib.escapeShellArg (if d.dhchapSecretFile == null then "" else d.dhchapSecretFile)}
            partition=${lib.escapeShellArg (toString d.partition)}
            mapper=${lib.escapeShellArg d.mapperName}
            mountpoint=${lib.escapeShellArg d.mountPoint}
            ;;
        '') cfg
      )}
      *) return 1 ;;
      esac
    }
    list_drives() {
    ${lib.concatStringsSep "\n" (map (n: "  echo ${lib.escapeShellArg n}") (lib.attrNames cfg))}
    }
  '';

  runtimePath = lib.makeBinPath [
    pkgs.nvme-cli
    pkgs.cryptsetup
    pkgs.util-linux
    pkgs.coreutils
  ];

  mountBackup = pkgs.writeShellScriptBin "mount-backup" ''
    set -euo pipefail
    export PATH=${runtimePath}:"$PATH"
    source ${resolveLib}

    name="''${1:-}"
    if [[ -z "$name" ]] || ! resolve_drive "$name"; then
      echo "usage: mount-backup <drive>" >&2
      echo "available drives:" >&2
      list_drives >&2
      exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
      echo "mount-backup must run as root" >&2
      exit 1
    fi

    connect_args=(--transport="$transport" --traddr="$address" --trsvcid="$port" --nqn="$subnqn")
    if [[ -n "$hostnqn" ]]; then
      connect_args+=(--hostnqn="$hostnqn")
    fi
    if [[ -n "$secretfile" ]]; then
      connect_args+=(--dhchap-secret="$(cat "$secretfile")")
    fi

    echo "connecting $name ($subnqn)..."
    nvme connect "''${connect_args[@]}"

    # Find the controller that now serves this subsystem, then its namespace.
    ctrl=""
    for _ in $(seq 1 50); do
      for c in /sys/class/nvme/*/; do
        [[ -r "$c/subsysnqn" ]] || continue
        if [[ "$(cat "$c/subsysnqn")" == "$subnqn" ]]; then
          ctrl="$(basename "$c")"
          break
        fi
      done
      [[ -n "$ctrl" ]] && break
      sleep 0.1
    done
    if [[ -z "$ctrl" ]]; then
      echo "could not find nvme controller for $subnqn" >&2
      exit 1
    fi

    nsdev=""
    for _ in $(seq 1 50); do
      for ns in /sys/block/"$ctrl"n*; do
        [[ -e "$ns" ]] || continue
        nsdev="/dev/$(basename "$ns")"
        break
      done
      [[ -n "$nsdev" ]] && break
      sleep 0.1
    done
    if [[ -z "$nsdev" ]]; then
      echo "no namespace found on controller $ctrl" >&2
      exit 1
    fi

    partdev="''${nsdev}p''${partition}"
    for _ in $(seq 1 50); do
      [[ -b "$partdev" ]] && break
      sleep 0.1
    done
    if [[ ! -b "$partdev" ]]; then
      echo "partition $partdev did not appear" >&2
      exit 1
    fi

    echo "unlocking $partdev (enter the disk passphrase)..."
    cryptsetup open "$partdev" "$mapper"

    mkdir -p "$mountpoint"
    mount "/dev/mapper/$mapper" "$mountpoint"
    echo "mounted $name at $mountpoint"
  '';

  umountBackup = pkgs.writeShellScriptBin "umount-backup" ''
    set -euo pipefail
    export PATH=${runtimePath}:"$PATH"
    source ${resolveLib}

    name="''${1:-}"
    if [[ -z "$name" ]] || ! resolve_drive "$name"; then
      echo "usage: umount-backup <drive>" >&2
      echo "available drives:" >&2
      list_drives >&2
      exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
      echo "umount-backup must run as root" >&2
      exit 1
    fi

    umount "$mountpoint" || true
    cryptsetup close "$mapper" || true
    nvme disconnect --nqn="$subnqn" || true
    echo "disconnected $name"
  '';
in
{
  options.host.backupDrives = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule driveModule);
    default = { };
    description = ''
      Encrypted NVMe-over-Fabrics backup drives that can be attached on demand
      with the `mount-backup <name>` / `umount-backup <name>` commands.
    '';
  };

  config = lib.mkIf enabled {
    boot.kernelModules = [ "nvme_tcp" ];

    environment.systemPackages = [
      mountBackup
      umountBackup
      pkgs.nvme-cli
    ];

    # The DH-HMAC-CHAP secrets must survive the blank-root rollback.
    environment.persistence."/persist".directories = [ "/etc/credstore" ];

    # Ensure every mount point exists (recreated each boot on the ephemeral root).
    systemd.tmpfiles.rules = lib.mapAttrsToList (_: d: "d ${d.mountPoint} 0755 root root -") cfg;
  };
}
