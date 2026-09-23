# Substituter for the llm-agents flake behind the home host.claude.enable
# option (see home/claude.nix). It builds against its own nixpkgs-unstable, so
# without this every rebuild that bumps the input recompiles the Claude
# packages' dependency closure locally. Only added when some Home Manager user
# enables Claude, so machines without it (work) don't trust the extra cache.
{ config, lib, ... }:
let
  claudeUsers = lib.filterAttrs (_: user: user.host.claude.enable) (config.home-manager.users or { });
in
{
  nix.settings = lib.mkIf (claudeUsers != { }) {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
}
