{
  config,
  lib,
  pkgs,
  ...
}:
let
  # OpenSCAD language support (completion, hover, preview), not packaged in
  # nixpkgs. The bundled openscad-lsp is a static binary, so it runs on NixOS
  # as is, and it finds BOSL2 in ~/.local/share/OpenSCAD/libraries
  # (home/gui-tools.nix) on its own.
  openscad-language-support = pkgs.vscode-utils.extensionFromVscodeMarketplace {
    name = "openscad-language-support";
    publisher = "Leathong";
    version = "2.0.1";
    hash = "sha256-GTvn97POOVmie7mOD/Q3ivEHXmqb+hvgiic9pTWYS0s=";
  };
in
{
  programs.vscode = {
    enable = true;

    profiles.default = {
      extensions =
        with pkgs.vscode-extensions;
        [
          jnoortheen.nix-ide
        ]
        # OpenSCAD itself is only installed on personal machines.
        ++ lib.optionals (!config.host.work) [ openscad-language-support ];

      userSettings = {
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.formatterPath" = "nixfmt";
        "nix.serverSettings" = {
          "nixd" = {
            "formatting" = {
              "command" = [ "nixfmt" ];
            };
          };
        };
      };
    };
  };
}
