{ pkgs, ... }:
{
  programs.zsh.enable = true;

  users.users.yawkat = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    shell = pkgs.zsh;
  };
}
