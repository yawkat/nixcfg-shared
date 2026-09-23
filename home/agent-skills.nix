# Skills shared by the coding agents. Claude Code and Codex read the same
# SKILL.md format, so one list feeds both: home/claude.nix hands it to
# programs.claude-code.skills, and a machine running Codex can do the same
# with programs.codex.skills.
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

  config.host.agentSkills = {
    security-audit = "${security-audit-skill}/skills/security-audit";
  };
}
