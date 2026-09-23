# Codex CLI and the ChatGPT desktop app, opt-in via host.codex.enable.
# Keep the CLI from nixpkgs; the desktop app comes from llm-agents.
{ llm-agents }:
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.host.codex.enable = lib.mkEnableOption "Codex CLI and the ChatGPT desktop app";

  config = lib.mkIf config.host.codex.enable {
    programs.codex = {
      enable = true;
      skills = config.host.agentSkills;
    };

    home.packages = [ llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt ];
  };
}
