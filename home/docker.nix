{ lib, pkgs, ... }:
let
  docker = pkgs.docker;
in
{
  # Rootless Docker: the daemon runs as the user, so there is no
  # root-equivalent docker group, and its data lives in ~/.local/share/docker,
  # which survives the NixOS blank-root reset. Home Manager has no module for
  # it, so this mirrors NixOS's virtualisation.docker.rootless, which also
  # lets it run on non-NixOS work machines.
  #
  # The host must still provide what an unprivileged user cannot: setuid
  # newuidmap/newgidmap and /etc/subuid and /etc/subgid ranges for the user.
  # NixOS does both by default for normal users.
  home.packages = [ docker ];

  systemd.user.services.docker = {
    Unit = {
      Description = "Docker Application Container Engine (Rootless)";
      # Taken from NixOS's docker-rootless module.
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "notify";
      ExecStart = "${docker}/bin/dockerd-rootless";
      ExecReload = "${pkgs.procps}/bin/kill -s HUP $MAINPID";
      # newuidmap/newgidmap are setuid and so cannot come from the store:
      # /run/wrappers on NixOS, /usr/bin elsewhere. dockerd-rootless.sh also
      # needs basic tools (id, grep) that NixOS system services get by
      # default, but user services don't; without grep it fails to detect
      # slirp4netns and falls back to a network driver rootlesskit lacks.
      Environment = [
        "PATH=/run/wrappers/bin:${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
          ]
        }:/usr/bin:/bin"
      ];
      TimeoutSec = 0;
      RestartSec = 2;
      Restart = "always";
      LimitNOFILE = "infinity";
      LimitNPROC = "infinity";
      LimitCORE = "infinity";
      Delegate = true;
      NotifyAccess = "all";
      KillMode = "mixed";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Shells read sessionVariables, while GUI apps such as IntelliJ get their
  # environment from systemd's environment.d. Both are needed so the CLI and
  # Testcontainers find the per-user socket wherever they run.
  home.sessionVariables.DOCKER_HOST = "unix://\${XDG_RUNTIME_DIR}/docker.sock";
  systemd.user.sessionVariables.DOCKER_HOST = "unix://\${XDG_RUNTIME_DIR}/docker.sock";

  # Images and stopped containers pile up quickly; clear out everything that
  # nothing references any more once a week.
  systemd.user.services.docker-prune = {
    Unit = {
      Description = "Prune unused rootless Docker data";
      Requires = [ "docker.service" ];
      After = [ "docker.service" ];
    };
    Service = {
      Type = "oneshot";
      Environment = [ "DOCKER_HOST=unix://%t/docker.sock" ];
      ExecStart = "${docker}/bin/docker system prune --all --force";
    };
  };
  systemd.user.timers.docker-prune = {
    Unit.Description = "Weekly prune of unused rootless Docker data";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
