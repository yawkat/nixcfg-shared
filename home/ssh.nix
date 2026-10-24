{ config, lib, ... }:
let
  generated = config.home.file.".ssh/config".source;
in
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

  # ssh refuses a config that isn't owned by the user or root. Home Manager's
  # usual symlink into the Nix store is root-owned, which is fine on the host,
  # but inside a user namespace that maps only the user's uid (sandboxed tools,
  # Claude sessions) root shows up as nobody and every ssh fails with "Bad
  # owner or permissions". So write the generated config as a real file the
  # user owns instead of linking it, read-only so it isn't edited by accident:
  # changes belong in Nix or config.local. A differing regular file already
  # there (hand-written, or edited since) is kept as config.hm-backup.
  home.file.".ssh/config".enable = false;
  home.activation.sshConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    sshConfig="$HOME/.ssh/config"
    if [[ -f $sshConfig && ! -L $sshConfig ]] && ! cmp -s ${generated} "$sshConfig"; then
      run mv "$sshConfig" "$sshConfig.hm-backup"
    fi
    run rm -f "$sshConfig"
    run install -D -m 400 ${generated} "$sshConfig"
  '';
}
