# Cache for the llm-agents packages used by the optional home agent modules.
# They use their own nixpkgs-unstable; enable the cache only when a Home
# Manager user enables Claude or Codex.
{ config, lib, ... }:
let
  agentUsers = lib.filterAttrs (
    _: user: (user.host.claude.enable or false) || (user.host.codex.enable or false)
  ) (config.home-manager.users or { });
in
{
  nix.settings = lib.mkIf (agentUsers != { }) {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
}
