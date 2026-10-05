# Claude Code and Claude Desktop, opt-in via host.claude.enable (work machines
# leave it off). Both packages come from llm-agents rather than nixpkgs, see
# the input in flake.nix. Neither self-updates on Linux, so
# `nix flake update llm-agents` is the one bump for each.
{ llm-agents }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  agentPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.host.claude.enable = lib.mkEnableOption "Claude Code and Claude Desktop";

  config = lib.mkIf config.host.claude.enable {
    programs.claude-code = {
      enable = true;
      package = agentPkgs.claude-code;
      skills = config.host.agentSkills;
      # Concurrent builds each evaluate in their own client and share one
      # daemon, which is how this machine has run out of memory before.
      context = ''
        Never run multiple `nix build`, `nix flake check`, `nixos-rebuild` or
        similar Nix build/eval commands concurrently, including as parallel
        background tasks or in parallel subagents. Run them one at a time.
      '';
    };

    home.packages = [ agentPkgs.claude-desktop ];
  };
}
