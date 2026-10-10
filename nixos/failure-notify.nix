{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.failureNotify;

  # The ntfy topic URL (e.g. https://ntfy.sh/<topic>) is a systemd credential
  # of this name, found the same way as the backup password: handed to the
  # system (e.g. by a hypervisor) or a file in /etc/credstore/. On the free
  # ntfy.sh tier the unguessable topic name is the only thing keeping others
  # from reading or posting, so it must not end up in this public repository
  # or the nix store. It is low value, so a command line is fine.
  credentialName = "failure-notify-url";

  notifyScript = pkgs.writeShellApplication {
    name = "failure-notify";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      unit="$1"
      host=${lib.escapeShellArg config.networking.hostName}

      # systemd sets MONITOR_* in units started through OnFailure=. The
      # message deliberately carries no log output: anyone with the topic
      # name can read it.
      message="$unit failed: ''${MONITOR_SERVICE_RESULT:-unknown}"
      if [ -n "''${MONITOR_EXIT_STATUS:-}" ]; then
        message="$message (''${MONITOR_EXIT_CODE:-exit} $MONITOR_EXIT_STATUS)"
      fi
      message="$message. See journalctl -u $unit on $host."

      curl \
        --fail --silent --show-error \
        --max-time 30 --retry 10 --retry-delay 30 --retry-all-errors \
        -H "Title: $host: $unit failed" \
        -H "Priority: high" \
        -H "Tags: warning" \
        --data-binary "$message" \
        "$(cat "$CREDENTIALS_DIRECTORY"/${credentialName})"
    '';
  };
in
{
  options.services.failureNotify = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "postgresql-dump" ];
      description = ''
        Services (names under `systemd.services`) that send a push notification
        through ntfy whenever they fail. The topic URL is loaded as the systemd
        credential `${credentialName}`.
      '';
    };
  };

  config = lib.mkIf (cfg.units != [ ]) {
    systemd.services =
      lib.genAttrs cfg.units (_: {
        onFailure = [ "failure-notify@%n.service" ];
      })
      // {
        "failure-notify@" = {
          description = "Notify about the failure of %i";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            # %i, not %I: unescaping would turn the dashes of the unit name
            # into slashes.
            ExecStart = "${lib.getExe notifyScript} %i";
            LoadCredential = "${credentialName}:${credentialName}";
            DynamicUser = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            NoNewPrivileges = true;
          };
        };
      };
  };
}
