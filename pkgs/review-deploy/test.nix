{ pkgs }:
# review-deploy against repositories in the build directory: the admin's
# checkout (admin), the proposals (proposals.git) and a clone of them (work).
# Everything runs as the build user, so uploadPack and receivePack are plain
# git; what they are for is that the hosts run them as the proposals' owner.
let
  reviewDeploy = import ./. {
    inherit pkgs;
    checkout = ".";
    source = "../proposals.git";
    uploadPack = "git-upload-pack";
    receivePack = "git-receive-pack";
    deploy = {
      none = "true";
      marker = "touch ../deployed";
    };
    defaultTarget = "none";
  };

  lock =
    owner: rev:
    pkgs.writeText "flake.lock" (
      builtins.toJSON {
        version = 7;
        root = "root";
        nodes = {
          root.inputs.nixpkgs = "nixpkgs";
          nixpkgs.locked = {
            type = "github";
            inherit owner rev;
            repo = "nixpkgs";
            narHash = "sha256-${rev}";
          };
        };
      }
    );
in
pkgs.runCommand "review-deploy-test"
  {
    nativeBuildInputs = [
      reviewDeploy
      pkgs.git
    ];
  }
  ''
    set -euo pipefail
    export HOME=$PWD
    git config --global user.name test
    git config --global user.email test@example.com
    git config --global init.defaultBranch main

    # deploy ANSWER [TARGET]: review-deploy's output in $out_text, its status in $status
    deploy() {
      status=0
      out_text=$(cd admin && echo "$1" | review-deploy ''${2:-} 2>&1) || status=$?
    }
    expect() {
      if [ "$status" != "$1" ] || ! grep -qF -- "$2" <<<"$out_text"; then
        echo "expected status $1 and '$2', got $status:"
        echo "$out_text"
        exit 1
      fi
    }
    propose() {
      (cd work && eval "$1" && git add -A && git commit -qm "$2" && git push -qf origin HEAD:main)
    }
    rev() {
      git -C "$1" rev-parse "''${2:-HEAD}"
    }

    git init -q --bare proposals.git
    mkdir admin
    (cd admin && git init -q && echo a > a && git add a && git commit -qm first)

    echo "the first run, with nothing proposed, pushes what is deployed"
    deploy ""
    expect 0 "Nothing new"
    [ "$(rev proposals.git deployed)" = "$(rev admin)" ]
    git clone -q -b deployed proposals.git work

    echo "a reviewed fast-forward is merged and deployed"
    propose "echo b > b" second
    deploy no marker
    expect 1 "Not deployed"
    [ ! -e deployed ]
    deploy yes marker
    expect 0 "+b"
    [ -e deployed ]
    [ "$(rev admin)" = "$(rev work)" ]
    [ "$(rev proposals.git deployed)" = "$(rev work)" ]

    echo "control characters need a second look and are shown, not run"
    propose "printf 'x = 1;\033[2K\n' > c" third
    deploy yes
    expect 1 "invisible or control characters"
    expect 1 "^[[2K"
    deploy "deploy anyway"
    expect 0 ""
    [ "$(rev admin)" = "$(rev work)" ]

    echo ".gitattributes can't hide a change"
    propose "printf '* -diff\n' > .gitattributes" attributes
    deploy yes
    expect 0 ""
    propose "echo hidden-change > b" change
    deploy no
    expect 1 "+hidden-change"
    if grep -q "Binary files" <<<"$out_text"; then echo "$out_text"; exit 1; fi
    deploy yes
    expect 0 ""

    echo "flake.lock: new inputs and changed sources are warnings, new revisions are not"
    propose "cat ${lock "NixOS" "aaaa"} > flake.lock" lock
    deploy yes
    expect 1 "new input nixpkgs: github:NixOS/nixpkgs"
    deploy "deploy anyway"
    expect 0 ""
    propose "cat ${lock "evil" "bbbb"} > flake.lock" fork
    deploy yes
    expect 1 "source changed nixpkgs: github:NixOS/nixpkgs -> github:evil/nixpkgs"
    (cd work && git reset -q --hard HEAD~1 && git push -qf origin HEAD:main)
    propose "cat ${lock "NixOS" "cccc"} > flake.lock" update
    deploy yes
    expect 0 "updated  nixpkgs (github:NixOS/nixpkgs) aaaa -> cccc"

    echo "a proposal that is not a fast-forward is refused"
    (cd work && git reset -q --hard HEAD~1)
    propose "echo d > d" fork
    deploy yes
    expect 1 "not based on what is deployed"

    echo "uncommitted changes in the checkout stop it"
    (cd work && git fetch -q && git reset -q --hard origin/deployed && git push -qf origin HEAD:main)
    echo dirty > admin/a
    deploy yes
    expect 1 "uncommitted changes"
    git -C admin checkout -q a

    echo "a broken proposals repository doesn't stop a deploy"
    propose "echo e > e" fifth
    printf '#!/bin/sh\nexit 1\n' > proposals.git/hooks/pre-receive
    chmod +x proposals.git/hooks/pre-receive
    deploy yes
    expect 0 "Could not push"
    mv proposals.git proposals-gone.git
    deploy ""
    expect 0 "Could not read the proposals"

    touch $out
  ''
