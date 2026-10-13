{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # Host entries are machine-specific and stay out of this repository.
    includes = [ "config.local" ];
    # Detect dead connections (NAT timeouts, suspend, Wi-Fi changes) so the
    # session drops instead of hanging forever.
    settings."*".ServerAliveInterval = 60;
  };
}
