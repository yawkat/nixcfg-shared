{ lib, ... }:
{
  programs.git = {
    enable = true;
    settings.init.defaultBranch = "main";
    settings.user = {
      name = "Jonas Konrad";
      email = lib.mkDefault "me@yawk.at";
    };
  };
}
