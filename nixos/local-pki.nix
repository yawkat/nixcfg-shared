{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.localPki;

  cert-request = pkgs.callPackage ../pkgs/device-ca-client.nix { };

  mkSafeName = cert: builtins.replaceStrings [ "@" ] [ "_" ] cert.cn;
in
{
  options.services.localPki = {
    enable = lib.mkEnableOption "local PKI client";

    directory = lib.mkOption {
      type = lib.types.str;
      default = "/data/local-pki";
      description = "Directory used to store local PKI files.";
    };

    certs = lib.mkOption {
      default = [ ];
      description = "List of certificates to enroll and keep renewed.";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            cn = lib.mkOption {
              type = lib.types.str;
              description = "Common Name for the certificate.";
            };
            group = lib.mkOption {
              type = lib.types.str;
              description = "Unix group that gets read access to the private key.";
            };
            reload = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra commands to run after renewal (e.g. service reloads).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."ssl/certs/ca-certificates.crt".enable = false;

    # Runtime directory structure (mirrors "Directory structure" task)
    systemd.tmpfiles.rules = [
      "d ${cfg.directory}    0755 root root -"
      "d ${cfg.directory}/ca 0755 root root -"
      # Pre-populate with system bundle; update-ca service will append local CA
      "C /etc/ssl/certs/ca-certificates.crt 0644 root root - ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];

    # CA update service (mirrors local-pki-update-ca.service + the symlink tasks)
    systemd.services = {
      local-pki-update-ca = {
        description = "Update local CA root certificates";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${cert-request}/bin/cert-request --ca-work-directory ${cfg.directory}/ca update-ca";
          ExecStartPost = pkgs.writeShellScript "local-pki-install-ca" ''
            set -euo pipefail
            cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
                "${cfg.directory}/ca/latest/ca_yawk_at_combined.crt" \
                > /etc/ssl/certs/ca-certificates.crt
          '';
        };
      };
    }
    // lib.listToAttrs (
      lib.concatMap (
        cert:
        let
          safeName = mkSafeName cert;
        in
        [
          {
            name = "local-pki-enroll-${safeName}";
            value = {
              description = "Enroll local PKI certificate for ${cert.cn}";
              after = [
                "network-online.target"
                "local-pki-update-ca.service"
              ];
              wants = [ "network-online.target" ];
              requires = [ "local-pki-update-ca.service" ];
              wantedBy = [ "multi-user.target" ];
              unitConfig.ConditionPathExists = "!${cfg.directory}/${cert.cn}/latest/certificate.crt";
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${cert-request}/bin/cert-request --ca-work-directory ${cfg.directory}/ca enroll --cert-directory ${cfg.directory}/${cert.cn} --cn ${lib.escapeShellArg cert.cn} --group ${lib.escapeShellArg cert.group}";
              };
            };
          }
          {
            name = "local-pki-renew-${safeName}";
            value = {
              description = "Renew local CA certificate for ${cert.cn}";
              after = [
                "network-online.target"
                "local-pki-update-ca.service"
                "local-pki-enroll-${safeName}.service"
              ];
              wants = [ "network-online.target" ];
              requires = [
                "local-pki-update-ca.service"
                "local-pki-enroll-${safeName}.service"
              ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = [
                  "${cert-request}/bin/cert-request --ca-work-directory ${cfg.directory}/ca renew --cert-directory ${cfg.directory}/${cert.cn} --cn ${lib.escapeShellArg cert.cn} --group ${lib.escapeShellArg cert.group}"
                ]
                ++ cert.reload;
              };
            };
          }
        ]
      ) cfg.certs
    );

    # Daily timer (mirrors local-pki-update-ca.timer)
    systemd.timers = {
      local-pki-update-ca = {
        description = "Daily CA bundle update";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    }
    // lib.listToAttrs (
      lib.map (cert: {
        name = "local-pki-renew-${mkSafeName cert}";
        value = {
          description = "Hourly renewal timer for ${cert.cn}";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
          };
        };
      }) cfg.certs
    );

    users.groups = lib.listToAttrs (
      map (cert: {
        name = cert.group;
        value = { };
      }) cfg.certs
    );

    environment.etc."ssl/certs/ca_yawk_at_combined.crt" = {
      source = "${cfg.directory}/ca/latest/ca_yawk_at_combined.crt";
    };

    environment.variables.NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    environment.variables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    environment.variables.REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";

    systemd.globalEnvironment = {
      NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    };
  };
}
