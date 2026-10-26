# The Home Manager module for yawkat-admin: the flake's own, passed in by
# flake.nix.
{ homeModule }:
{
  config,
  lib,
  pkgs,
  ...
}:
# Two accounts. yawkat, the daily one with autologin, runs AI agents and
# other people's code, so it must not be able to administer anything: not this
# machine (no sudo, no polkit admin) and nothing else whose admin keys live
# with yawkat-admin.
#
# yawkat-admin is used in its own session: Ctrl+Alt+F1/F2 between the two, or
# "Switch User". Never through su or sudo in a yawkat terminal, and never by
# typing its password into a prompt in yawkat's session (polkit dialogs
# included): yawkat's terminal, compositor and every program it starts can
# read what is typed there.
#
# Its password is in /persist/passwords/yawkat-admin (`mkpasswd -m sha-512`),
# which has to exist before the first rebuild with this: otherwise
# yawkat-admin can't log in, and with yawkat out of wheel nobody but root
# could administer the machine.
let
  admin = config.users.users.yawkat-admin;
  source = "${config.users.users.yawkat.home}/nixcfg";
  checkout = "${admin.home}/nixcfg";
  git = "${pkgs.git}/bin";

  # How changes to the host config reach the system: yawkat (and the agents it
  # runs) edits ~yawkat/nixcfg and commits to main; yawkat-admin runs
  # `review-deploy [switch|boot|none]` in its own session, which shows the new
  # commits in full, merges the exact commit it showed into ~yawkat-admin/nixcfg
  # (the system flake, /etc/nixos) and switches to it (pkgs/review-deploy). git
  # reads and writes yawkat's repository only as yawkat, through the sudo rules
  # below: its config and hooks are yawkat's to write, and they can run
  # commands. What is deployed is pushed back to yawkat's repository as the
  # branch deployed, for new work to start from.
  reviewDeploy = import ../../pkgs/review-deploy {
    inherit pkgs checkout source;
    uploadPack = "sudo -u yawkat ${git}/git-upload-pack";
    receivePack = "sudo -u yawkat ${git}/git-receive-pack";
    deploy = {
      switch = "nixos-rebuild switch --flake . --sudo";
      boot = "nixos-rebuild boot --flake . --sudo";
      none = "true";
    };
    defaultTarget = "switch";
  };

  # Groups that are as good as root
  privilegedGroups = [
    "wheel"
    "libvirtd"
    "docker"
    "podman"
    "lxd"
    "incus-admin"
    "disk"
  ];
  yawkatPrivileged = lib.filter (
    group:
    lib.elem group config.users.users.yawkat.extraGroups
    || lib.elem "yawkat" (config.users.groups.${group}.members or [ ])
  ) privilegedGroups;
in
{
  imports = [ ./auth.nix ];

  assertions = [
    {
      assertion = yawkatPrivileged == [ ];
      message = "yawkat runs untrusted code and must not be in ${lib.concatStringsSep ", " yawkatPrivileged}: that is yawkat-admin's";
    }
  ];

  users.users.yawkat-admin = {
    isNormalUser = true;
    description = "yawkat (admin)";
    extraGroups = [ "wheel" ];
    hashedPasswordFile = "/persist/passwords/yawkat-admin";
    shell = pkgs.zsh;
  };

  # yawkat-admin is the only one in wheel (users.nix), and its session runs
  # nothing of yawkat's, so a password at sudo guards nothing that logging in
  # as yawkat-admin didn't already. Keep it that way: anyone or anything added
  # to wheel, or able to run code as yawkat-admin, is root.
  security.sudo.wheelNeedsPassword = false;

  security.sudo.extraRules = [
    {
      users = [ "yawkat-admin" ];
      runAs = "yawkat";
      commands =
        map
          (command: {
            command = "${git}/${command} ${source}";
            options = [ "NOPASSWD" ];
          })
          [
            "git-upload-pack"
            "git-receive-pack"
          ];
    }
  ];

  # So `sudo nixos-rebuild switch` finds the flake without `--flake`:
  # nixos-rebuild looks for /etc/nixos/flake.nix by default. The admin's
  # checkout, not the one yawkat (and its agents) edit: those changes come over
  # through review-deploy. Only touches the link when nothing unexpected
  # already lives at /etc/nixos.
  system.activationScripts.etcNixosFlakeLink = lib.stringAfter [ "etc" ] ''
    target=${checkout}
    link=/etc/nixos
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "warning: $link exists and is not a symlink; leaving it alone (wanted to point it at $target)" >&2
    else
      ln -sfn "$target" "$link"
    fi
  '';

  home-manager.users.yawkat-admin = {
    imports = [ homeModule ];
    home.packages = [ reviewDeploy ];
    # Unlike yawkat's, this session locks: it is the one that holds the keys.
    host.idle.dimAfter = 300;
    host.idle.lockAfter = 300;
    home.stateVersion = "26.05";
  };
}
