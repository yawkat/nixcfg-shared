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
    sshfs
    python3
    nodejs
    # Sandboxing for commands run against untrusted code (e.g. by coding
    # agents): bwrap for namespaces, prlimit (util-linux) for rlimits.
    bubblewrap
    util-linux
    zip
    unzip
    magic-wormhole
    wget
    vim
    psmisc
    kdePackages.spectacle
    kdePackages.kcalc
    okteta
    meld
  ];
}
