{ pkgs, ... }:
{
  home.packages = [ pkgs.jetbrains.idea ];

  home.file = {
    ".jdks/graalvm-25".source = pkgs.graalvmPackages.graalvm-ce.home;
    ".jdks/openjdk-25".source = pkgs.jdk25.home;
    ".jdks/openjdk-8".source = pkgs.jdk8.home;
  };

  # Marketplace plugins require separately pinned artifacts on nixpkgs 26.05,
  # so plugins remain managed by IntelliJ IDEA rather than Home Manager.
}
