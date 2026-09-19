{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    nixd
    nixfmt
    rsync
    tmux
    htop
    ncdu
    maven
    jdk25
    visualvm
    sublime-merge
    wiremix
    iproute2
    wireshark
    tcpdump
    noto-fonts
    (openssh.override { etcDir = "${builtins.placeholder "out"}/etc/ssh"; })
    github-cli
    xdg-utils
    mtr
    python3
    zip
    unzip
    magic-wormhole
    wget
    vim
    psmisc
    kdePackages.spectacle
  ];
}
