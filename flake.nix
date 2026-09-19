{
  description = "yawkat's shared Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      homeManagerModules.default = ./home;

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          testHome = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home.username = "test-user";
                home.homeDirectory = "/home/test-user";
                home.stateVersion = "26.05";
              }
            ];
          };
        in
        {
          home-activation = testHome.activationPackage;

          privacy =
            pkgs.runCommand "shared-config-privacy-check"
              {
                src = self;
                nativeBuildInputs = [ pkgs.ripgrep ];
              }
              ''
                cp -R "$src" source
                chmod -R u+w source

                # Base64 keeps the forbidden values themselves out of this public
                # source tree, so this check cannot accidentally match its own list.
                printf '%s' \
                  'b3JhY2xlCmhlY2F0ZQpjaXNjbwp2YmFuCmpvbmFzLmtvbnJhZEBvcmFjbGUuY29tCi9ob21lL3lhd2thdAovb3B0L2Npc2NvCg==' \
                  | base64 --decode > forbidden-markers

                while IFS= read -r marker; do
                  if rg --hidden --ignore-case --fixed-strings -- "$marker" source; then
                    echo "Public source contains a private marker" >&2
                    exit 1
                  fi
                done < forbidden-markers

                touch "$out"
              '';
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
