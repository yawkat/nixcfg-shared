{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.host.backupDrives;
  enabled = cfg != { };

  driveModule = {
    options = {
      address = lib.mkOption {
        type = lib.types.str;
        description = "Target address (nvme connect --traddr).";
        example = "10.0.5.1";
      };
      subsystemNqn = lib.mkOption {
        type = lib.types.str;
        description = "Subsystem NQN to connect to (nvme connect --nqn).";
      };
      hostNqn = lib.mkOption {
        type = lib.types.str;
        description = ''
          Host NQN to present (nvme connect --hostnqn). The DH-HMAC-CHAP secret
          is read from /etc/credstore/nvme-dhchap-<hostNqn>.
        '';
      };
    };
  };

  # A shell case statement that resolves the drive named in $1 into the
  # address/subnqn/hostnqn variables. Sourced by both commands. The mount
  # point, mapper name and secret path are derived from the drive name and
  # host NQN in the commands themselves.
  resolveLib = pkgs.writeText "backup-drives-lib.sh" ''
    resolve_drive() {
      case "$1" in
      ${lib.concatStrings (
        lib.mapAttrsToList (name: d: ''
          ${lib.escapeShellArg name})
            address=${lib.escapeShellArg d.address}
            subnqn=${lib.escapeShellArg d.subsystemNqn}
            hostnqn=${lib.escapeShellArg d.hostNqn}
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

  preamble = ''
    set -euo pipefail
    export PATH=${runtimePath}:"$PATH"
    source ${resolveLib}

    name="''${1:-}"
    if [[ -z "$name" ]] || ! resolve_drive "$name"; then
      echo "usage: $(basename "$0") <drive>" >&2
      echo "available drives:" >&2
      list_drives >&2
      exit 1
    fi
    if [[ $EUID -ne 0 ]]; then
      echo "$(basename "$0") must run as root" >&2
      exit 1
    fi

    mapper="backup-$name"
    mountpoint="/mnt/backup-$name"
    secret="/etc/credstore/nvme-dhchap-$hostnqn"
  '';

  mountBackup = pkgs.writeShellScriptBin "mount-backup" ''
    ${preamble}

    echo "connecting $name ($subnqn)..."
    nvme connect \
      --transport=tcp \
      --traddr="$address" \
      --trsvcid=4420 \
      --nqn="$subnqn" \
      --hostnqn="$hostnqn" \
      --dhchap-secret="$(cat "$secret")"

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

    dev=""
    for _ in $(seq 1 50); do
      for ns in /sys/block/"$ctrl"n*; do
        [[ -e "$ns" ]] || continue
        dev="/dev/$(basename "$ns")"
        break
      done
      [[ -n "$dev" ]] && break
      sleep 0.1
    done
    if [[ -z "$dev" ]]; then
      echo "no namespace found on controller $ctrl" >&2
      exit 1
    fi

    echo "unlocking $dev (enter the disk passphrase)..."
    cryptsetup open "$dev" "$mapper"

    mkdir -p "$mountpoint"
    mount "/dev/mapper/$mapper" "$mountpoint"
    echo "mounted $name at $mountpoint"
  '';

  umountBackup = pkgs.writeShellScriptBin "umount-backup" ''
    ${preamble}

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
      Encrypted NVMe-over-TCP backup drives that can be attached on demand with
      the `mount-backup <name>` / `umount-backup <name>` commands. Each drive is
      whole-namespace LUKS mounted at /mnt/backup-<name>.
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
    systemd.tmpfiles.rules = lib.mapAttrsToList (name: _: "d /mnt/backup-${name} 0755 root root -") cfg;
  };
}
