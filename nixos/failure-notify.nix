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

  # `failure-notify TITLE [MESSAGE]`, the message read from stdin if not
  # given. Callers outside a unit with LoadCredential= (smartd, ZED) find the
  # credential where systemd would: among the system credentials or in a
  # credstore directory. Both are root-only.
  notifyCommand = pkgs.writeShellApplication {
    name = "failure-notify";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
      # iconv
      (lib.getBin pkgs.glibc)
    ];
    text = ''
      title="$1"
      if [ $# -ge 2 ]; then
        message="$2"
      else
        message="$(cat)"
      fi

      url_file=
      for dir in "''${CREDENTIALS_DIRECTORY:-}" /run/credentials/@system /etc/credstore /run/credstore; do
        if [ -n "$dir" ] && [ -r "$dir"/${credentialName} ]; then
          url_file="$dir"/${credentialName}
          break
        fi
      done
      if [ -z "$url_file" ]; then
        echo "failure-notify: credential ${credentialName} not found" >&2
        exit 1
      fi

      # ntfy turns longer messages, and ones that are not valid UTF-8, into
      # attachments. iconv -c drops a character that head cut in half, and any
      # other invalid bytes.
      body="$(printf '%s' "$message" | head -c 4000 | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true)"

      curl \
        --fail --silent --show-error \
        --max-time 30 --retry 10 --retry-delay 30 --retry-all-errors \
        -H "Title: ${config.networking.hostName}: $title" \
        -H "Priority: high" \
        -H "Tags: warning" \
        --data-binary "$body" \
        "$(cat "$url_file")"
    '';
  };

  unitScript = pkgs.writeShellScript "failure-notify-unit" ''
    unit="$1"
    # systemd sets MONITOR_* in units started through OnFailure=. The message
    # deliberately carries no log output: anyone with the topic name can read
    # it.
    message="$unit failed: ''${MONITOR_SERVICE_RESULT:-unknown}"
    if [ -n "''${MONITOR_EXIT_STATUS:-}" ]; then
      message="$message (''${MONITOR_EXIT_CODE:-exit} $MONITOR_EXIT_STATUS)"
    fi
    exec ${lib.getExe cfg.command} "$unit failed" "$message. See journalctl -u $unit."
  '';

  # Called by the NixOS smartd module's notification script as a sendmail
  # replacement. The mail on stdin also carries the full `smartctl -a`; the
  # SMARTD_* variables it inherits are all that is needed.
  smartdMailer = pkgs.writeShellScript "failure-notify-smartd" ''
    cat > /dev/null
    exec ${lib.getExe cfg.command} \
      "SMART $SMARTD_FAILTYPE on $SMARTD_DEVICESTRING" \
      "$SMARTD_FULLMESSAGE"
  '';
in
{
  options.services.failureNotify = {
    command = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = notifyCommand;
      defaultText = lib.literalMD "the failure-notify script";
      description = ''
        `failure-notify TITLE [MESSAGE]` (message from stdin if not given), for
        other configuration to send notifications with, e.g. as
        `lib.getExe config.services.failureNotify.command`. Prefixes the title
        with the host name. It needs root, or the credential
        `${credentialName}` loaded into the calling unit, to find the topic.
      '';
    };

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

  config = lib.mkMerge [
    {
      systemd.services = {
        "failure-notify@" = {
          description = "Notify about the failure of %i";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            # %i, not %I: unescaping would turn the dashes of the unit name
            # into slashes.
            ExecStart = "${unitScript} %i";
            LoadCredential = "${credentialName}:${credentialName}";
            DynamicUser = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            NoNewPrivileges = true;
          };
        };
      }
      // lib.genAttrs cfg.units (_: {
        onFailure = [ "failure-notify@%n.service" ];
      });
    }

    {
      # Only takes effect where smartd is enabled. Replaces its e-mail
      # notifications, which have nowhere to go.
      services.smartd.notifications.mail = {
        enable = true;
        mailer = smartdMailer;
      };
    }
  ];
}
