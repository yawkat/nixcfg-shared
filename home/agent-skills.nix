# Skills and global instructions shared by the coding agents. Claude Code and
# Codex read the same SKILL.md format, so one list feeds both: home/claude.nix
# hands it to programs.claude-code.skills, and home/codex.nix hands it to
# programs.codex.skills. The context text goes to each agent's always-loaded
# instructions (Claude's CLAUDE.md, Codex's AGENTS.md) the same way.
{ security-audit-skill }:
{ lib, ... }:
{
  options.host.agentSkills = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = ''
      Skill directories (each containing a SKILL.md) to install for the coding
      agents, keyed by skill name. Entries defined elsewhere are added to the
      shared ones below.
    '';
  };

  options.host.agentContext = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = ''
      Global instructions for the coding agents, loaded in every session.
      Definitions elsewhere are appended to the shared text below.
    '';
  };

  config.host.agentSkills = {
    security-audit = "${security-audit-skill}/skills/security-audit";
    # Local skills layered on security-audit and the agents' own code review.
    security-audit-diverse = ./skills/security-audit-diverse;
    combined-review = ./skills/combined-review;
  };

  # Every machine that gets this file has Nix, because Home Manager installed
  # it, including hosts that only use system-manager. Concurrent builds each
  # evaluate in their own client and share one daemon, which is how a machine
  # has run out of memory before.
  config.host.agentContext = ''
    Never run multiple `nix build`, `nix flake check`, `nixos-rebuild` or
    similar Nix build/eval commands concurrently, including as parallel
    background tasks or in parallel subagents. Run them one at a time.

    Nix is available on this machine. A missing compiler, interpreter, test
    runner or other tool is not a reason to skip building or testing: get it
    from nixpkgs, for example `nix shell nixpkgs#python3 nixpkgs#gcc -c
    <command>`, or use the project's own dev shell (`nix develop -c <command>`)
    when it has one. If flakes are not enabled, add
    `--extra-experimental-features 'nix-command flakes'` or use
    `nix-shell -p <pkg> --run <command>`. Only if a tool really cannot be
    obtained, say exactly what was not tested and why.
  '';
}
