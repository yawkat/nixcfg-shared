{ lib, ... }:
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "Jonas Konrad";
      email = lib.mkDefault "me@yawk.at";
    };
  };
}
