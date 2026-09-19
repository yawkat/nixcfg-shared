{
  description = "yawkat's shared Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Used only to evaluate the nixosModules in CI. Consumers supply their own
    # disko and impermanence inputs.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      disko,
      impermanence,
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

      nixosModules = {
        default = ./nixos;
        diskLuksBtrfs = ./nixos/disk.nix;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          mkTestHome =
            extra:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.homeManagerModules.default
                {
                  home.username = "test-user";
                  home.homeDirectory = "/home/test-user";
                  home.stateVersion = "26.05";
                }
                extra
              ];
            };
          testHome = mkTestHome { };
          # Both sides of host.work must keep evaluating.
          testHomeWork = mkTestHome { host.work = true; };
          # Evaluate the system modules end to end so CI catches option
          # breakage. Dummy device/hostname only — no real host identity.
          testSystem =
            (nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                disko.nixosModules.disko
                impermanence.nixosModules.impermanence
                self.nixosModules.default
                self.nixosModules.diskLuksBtrfs
                {
                  host.disk.device = "/dev/vda";
                  host.backupDrives.sample = {
                    address = "10.0.0.1";
                    subsystemNqn = "nqn.2026-09.example:sample";
                    hostNqn = "nqn.2026-09.example:ci";
                  };
                  networking.hostName = "ci";
                  boot.loader.grub.enable = false;
                  system.stateVersion = "26.05";
                }
              ];
            }).config.system.build.toplevel;
        in
        {
          home-activation = testHome.activationPackage;
          home-activation-work = testHomeWork.activationPackage;

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
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          nixos-eval = testSystem;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
