{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.enable = true;

  # The daily account. Not in wheel: administering is yawkat-admin's
  # (admin/default.nix). It keeps what it needs day to day, such as switching
  # networks where NetworkManager runs (a laptop).
  users.users.yawkat = {
    isNormalUser = true;
    extraGroups = [
      "video"
    ]
    ++ lib.optional config.networking.networkmanager.enable "networkmanager";
    shell = pkgs.zsh;
  };
}
