{ ... }:
{
  virtualisation.docker = {
    enable = true;
    # Images and stopped containers pile up quickly; clear out what nothing
    # references any more once a week.
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Membership in the docker group is root-equivalent, which is fine on a
  # single-user machine and saves typing sudo for every docker command.
  users.users.yawkat.extraGroups = [ "docker" ];

  # The root subvolume is reset on every boot, which would throw away all
  # images, containers and volumes.
  environment.persistence."/persist".directories = [ "/var/lib/docker" ];
}
