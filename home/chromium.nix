# Chromium is managed through home-manager so extensions can be declared; each
# is dropped into "External Extensions" and fetched from the Web Store.
{ config, lib, ... }:
{
  programs.chromium = {
    enable = true;
    # Firefox is the default browser; don't nag about it on every start.
    commandLineArgs = [ "--no-default-browser-check" ];
    extensions = lib.optionals config.host.claude.enable [
      # Claude in Chrome (https://claude.com/claude-in-chrome)
      { id = "fcoeoabgfenejglbffodgkkbkcdhcgfn"; }
    ];
  };
}
