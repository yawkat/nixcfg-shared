{ lib, ... }:
{
  programs.git = {
    enable = true;
    settings.init.defaultBranch = "main";
    # Keep origin/HEAD in sync with the remote default branch on fetch, so
    # tools that derive the default branch from it do not use a stale one.
    settings.remote.origin.followRemoteHEAD = "always";
    # Drop origin/* refs of branches deleted on the remote.
    settings.fetch.prune = true;
    # Record worktree links as relative paths, so worktrees keep working when
    # the repository is moved or mounted somewhere else.
    settings.worktree.useRelativePaths = true;
    # Check fetched and pushed objects, so corruption shows up right away
    # rather than months later.
    settings.transfer.fsckObjects = true;
    settings.user = {
      name = "Jonas Konrad";
      email = lib.mkDefault "me@yawk.at";
    };
  };
}
