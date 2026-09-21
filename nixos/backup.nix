{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.backup;
  clientCfg = config.services.backupClient;

  # Client certificate used for mTLS against the restic REST host. The backup
  # host (goliath's backup-host.nix) matches on this exact CN, so it has to
  # follow the "backup@<host>.local.yawk.at" convention.
  certCn = "backup@${config.networking.hostName}.local.yawk.at";
  certDir = "${config.services.localPki.directory}/${certCn}/latest";

  restHost = "backup.local.yawk.at";

  # The repository password is a systemd credential of this name. A bare name
  # in LoadCredential= makes systemd first look for a credential the service
  # manager itself was handed (a VM's hypervisor can inject it via SMBIOS),
  # then for a file of that name in /etc/credstore/ (or /run/credstore/,
  # /usr/lib/credstore/). Hosts pick whichever suits them; this module never
  # sees the password's location.
  credentialName = backup: "backup-password-${backup.namespace}";

  # Both remotes hold the same data; the local repository is cheap disk on
  # goliath and keeps a long history, b2 is billed per byte and keeps much
  # less.
  retention = {
    local = "--keep-last 1 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-yearly 5";
    b2 = "--keep-last 1 --keep-daily 3 --keep-weekly 2 --keep-monthly 3 --keep-yearly 1";
  };

  # Common preamble: authenticate to the REST host with the PKI client cert and
  # unlock the repository password from the systemd credential.
  #
  # restic wants the certificate and its key concatenated into a single file,
  # and the private key is only readable by root, so this is assembled at run
  # time in a private temporary file rather than being kept on disk.
  resticEnv = backup: ''
    combined=$(mktemp)
    trap 'rm -f "$combined"' EXIT
    cat ${lib.escapeShellArg certDir}/certificate.crt \
        ${lib.escapeShellArg certDir}/private.pem > "$combined"

    export XDG_CACHE_HOME=${lib.escapeShellArg clientCfg.cacheDir}
    export RESTIC_TLS_CLIENT_CERT="$combined"
    RESTIC_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY"/${lib.escapeShellArg (credentialName backup)})"
    export RESTIC_PASSWORD
  '';

  backupScript =
    backup:
    pkgs.writeShellApplication {
      name = "backup-${backup.namespace}";
      runtimeInputs = [
        pkgs.restic
        pkgs.coreutils
      ];
      text = ''
        ${resticEnv backup}

        run_remote() {
          local remote="$1"
          shift
          export RESTIC_REPOSITORY="rest:https://${restHost}/$remote/${backup.namespace}"

          # A repository that already exists makes init fail; a repository with
          # no stale lock makes unlock a no-op. Neither is a reason to stop.
          restic init || true
          restic unlock || true

          restic backup \
            ${lib.escapeShellArgs backup.directories} \
            ${lib.escapeShellArgs (map (e: "--exclude=${e}") backup.excludes)} \
            --exclude-if-present=.nobackup

          restic forget --prune "$@"
        }

        run_remote local ${retention.local}
        run_remote b2 ${retention.b2}
      '';
    };

  checkScript =
    backup:
    pkgs.writeShellApplication {
      name = "backup-check-${backup.namespace}";
      runtimeInputs = [
        pkgs.restic
        pkgs.coreutils
      ];
      text = ''
        ${resticEnv backup}

        for remote in local b2; do
          export RESTIC_REPOSITORY="rest:https://${restHost}/$remote/${backup.namespace}"
          restic check --read-data-subset=5%
        done
      '';
    };

  # Both unit kinds share everything but the script: same credential, same
  # niceness, same network dependency.
  mkUnit = backup: description: script: {
    inherit description;
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "local-pki-enroll-${builtins.replaceStrings [ "@" ] [ "_" ] certCn}.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe script;
      LoadCredential = "${credentialName backup}:${credentialName backup}";
      # A backup must never make the machine feel slow.
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
in
{
  imports = [ ./local-pki.nix ];

  options.services.backupClient = {
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/restic-backup-cache";
      description = ''
        restic cache directory. The cache makes the difference between a backup
        that reads metadata from the repository and one that re-reads
        everything, so on an impermanent root this has to be persisted.
      '';
    };
  };

  options.services.backup = lib.mkOption {
    default = [ ];
    description = "List of restic backups to run on this host.";
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          namespace = lib.mkOption {
            type = lib.types.str;
            default = config.networking.hostName;
            example = "juvenile";
            description = ''
              Repository name on the backup host. Must match an entry in
              goliath's backup-host.nix, which serves it at /local/<namespace>
              and /b2/<namespace>.

              The repository password is read from the systemd credential
              `backup-password-<namespace>`: either passed in to the system
              (e.g. by a hypervisor) or a file in /etc/credstore/. It is the
              key the repository was created with — changing it makes every
              existing snapshot unreadable.
            '';
          };

          directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            example = [ "/home" ];
            description = "Directories to back up.";
          };

          excludes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "*.log" ];
            description = "restic --exclude patterns.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg != [ ]) {
    # mTLS against the backup host. The private key stays root-only; the backup
    # units are the only consumer and they run as root.
    services.localPki = {
      enable = true;
      certs = [
        {
          cn = certCn;
          group = "root";
        }
      ];
    };

    systemd.tmpfiles.rules = [ "d ${clientCfg.cacheDir} 0700 root root -" ];

    systemd.services = lib.listToAttrs (
      lib.concatMap (backup: [
        {
          name = "backup-${backup.namespace}";
          value = mkUnit backup "Back up ${backup.namespace}" (backupScript backup);
        }
        {
          name = "backup-check-${backup.namespace}";
          value = mkUnit backup "Verify backup ${backup.namespace}" (checkScript backup);
        }
      ]) cfg
    );

    systemd.timers = lib.listToAttrs (
      lib.concatMap (backup: [
        {
          name = "backup-${backup.namespace}";
          value = {
            description = "Daily backup of ${backup.namespace}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*-*-* 00:00:00 UTC";
              # Machines that are not on 24/7 have to catch up a missed run
              # rather than skip it.
              Persistent = true;
              RandomizedDelaySec = 3600;
            };
          };
        }
        {
          name = "backup-check-${backup.namespace}";
          value = {
            description = "Weekly verification of backup ${backup.namespace}";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "Sun *-*-* 02:00:00 UTC";
              Persistent = true;
              RandomizedDelaySec = 3600;
            };
          };
        }
      ]) cfg
    );

    # For manual runs / restores: `restic` on PATH still needs the repository,
    # password and client cert set by hand.
    environment.systemPackages = [ pkgs.restic ];
  };
}
