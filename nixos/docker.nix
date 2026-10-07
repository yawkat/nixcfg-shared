{ config, ... }:
let
  docker = config.virtualisation.docker.rootless.package;
in
{
  # Rootless rather than the system daemon: membership in the docker group is
  # root-equivalent, whereas this daemon runs as the user and can do no more
  # than they can. Its data lives in ~/.local/share/docker, so it survives the
  # blank-root reset without a persistence entry.
  virtualisation.docker.rootless = {
    enable = true;
    # Exports DOCKER_HOST for login sessions, so the CLI and Testcontainers
    # find the per-user socket without further setup.
    setSocketVariable = true;
  };

  # virtualisation.docker.autoPrune only covers the system daemon. Images and
  # stopped containers pile up quickly; clear out what nothing references any
  # more once a week.
  systemd.user.services.docker-prune = {
    description = "Prune unused rootless Docker data";
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    environment.DOCKER_HOST = "unix://%t/docker.sock";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${docker}/bin/docker system prune --force";
    };
  };
  systemd.user.timers.docker-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
