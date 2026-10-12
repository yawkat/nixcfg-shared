{ lib, ... }:
{
  programs.git = {
    enable = true;
    settings.init.defaultBranch = "main";
    # Keep origin/HEAD in sync with the remote default branch on fetch, so
    # tools that derive the default branch from it do not use a stale one.
    settings.remote.origin.followRemoteHEAD = "always";
    settings.user = {
      name = "Jonas Konrad";
      email = lib.mkDefault "me@yawk.at";
    };
  };
}
