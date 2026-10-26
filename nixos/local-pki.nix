{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.localPki;

  cert-request = cfg.package;

  mkSafeName = cert: builtins.replaceStrings [ "@" ] [ "_" ] cert.cn;

  publicCerts = lib.filter (cert: cert.public) cfg.certs;
in
{
  options.services.localPki = {
    enable = lib.mkEnableOption "local PKI client";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The cert-request client. The flake's `localPki` and `backup` modules
        default it to the one from the device-ca flake input.
      '';
    };

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
            public = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Also keep a publicly trusted (Let's Encrypt) certificate for the host name cn in
                `''${directory}/''${cn}-public`, for devices without the local CA. device-ca gets it on behalf of this
                host, authenticated by the local certificate, which needs the name's `_acme-challenge` record to be
                delegated to device-ca (see its README). Until the first one, `latest` there points at the local
                certificate, so that its users can start.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = map (cert: {
      assertion = cert.public -> !lib.hasInfix "@" cert.cn;
      message = "services.localPki: only host names can have a public certificate, not ${cert.cn}";
    }) cfg.certs;

    environment.etc."ssl/certs/ca-certificates.crt".enable = false;

    # Runtime directory structure (mirrors "Directory structure" task)
    systemd.tmpfiles.rules = [
      "d ${cfg.directory}    0755 root root -"
      "d ${cfg.directory}/ca 0755 root root -"
      # Pre-populate with system bundle; update-ca service will append local CA
      "C /etc/ssl/certs/ca-certificates.crt 0644 root root - ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ]
    ++ lib.concatMap (cert: [
      "d ${cfg.directory}/${cert.cn}-public 0755 root root -"
      # the local certificate stands in until the first public one, which replaces the link
      "L ${cfg.directory}/${cert.cn}-public/latest - - - - ${cfg.directory}/${cert.cn}/latest"
    ]) publicCerts;

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
    )
    // lib.listToAttrs (
      map (
        cert:
        let
          safeName = mkSafeName cert;
        in
        {
          name = "local-pki-renew-public-${safeName}";
          value = {
            description = "Renew public certificate for ${cert.cn}";
            after = [
              "network-online.target"
              "local-pki-enroll-${safeName}.service"
              # when both timers fire at once (at boot), don't race the renewal of the certificate it authenticates with
              "local-pki-renew-${safeName}.service"
            ];
            wants = [ "network-online.target" ];
            requires = [ "local-pki-enroll-${safeName}.service" ];
            serviceConfig = {
              Type = "oneshot";
              # the server answers within minutes, if at all
              TimeoutStartSec = "15min";
              ExecStart = [
                "${cert-request}/bin/cert-request --ca-work-directory ${cfg.directory}/ca renew-public --cert-directory ${cfg.directory}/${cert.cn}-public --auth-cert-directory ${cfg.directory}/${cert.cn} --cn ${lib.escapeShellArg cert.cn} --group ${lib.escapeShellArg cert.group}"
              ]
              ++ cert.reload;
            };
          };
        }
      ) publicCerts
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
    )
    // lib.listToAttrs (
      map (cert: {
        name = "local-pki-renew-public-${mkSafeName cert}";
        value = {
          description = "Hourly public certificate renewal timer for ${cert.cn}";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # It only asks the CA when a third of the lifetime is left. At :30, so that it doesn't race the hourly
            # renewal of the local certificate it authenticates with
            OnCalendar = "*:30";
            Persistent = true;
          };
        };
      }) publicCerts
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
