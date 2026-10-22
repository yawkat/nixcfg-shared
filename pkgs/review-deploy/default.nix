{
  pkgs,
  lib ? pkgs.lib,
  # The admin's checkout, which deploys run from
  checkout,
  # The repository the untrusted side pushes its proposals to, and the commands
  # that serve it to git as its owner, so that git never reads that
  # repository's config as the admin: config and hooks can run commands. What
  # is deployed is pushed back to it as the branch deployed, for the proposals
  # to build on.
  source,
  uploadPack,
  receivePack,
  branch ? "main",
  # name -> command run in the checkout after the merge; the first argument
  # picks one
  deploy,
  defaultTarget,
  # Command that takes a title and a message, run before deploying
  notify ? null,
}:
# The one way a change from the untrusted side (a daily account and the agents
# it runs) gets deployed: the admin reads it and confirms its exact commit. It
# must be a fast-forward of what is checked out. Shown are the commits and their
# full diff; then the commit is merged by its hash, the one that was shown, and
# deployed. Nothing of the proposal is evaluated or run before that.
#
# The review has to show what is really there: no colors and no raw control
# characters in the pager (less shows them as ^X), a warning for invisible or
# bidi Unicode, which can make code read differently than it runs, and every
# file as text, whatever .gitattributes (which a proposal can change) says.
#
# A flake.lock change is listed by input (lock-sources.py): new revisions, and a
# warning for a new input or one whose source changed, as a swap for a fork
# would. What a new revision brings in is not reviewed here.
#
# The proposals' repository belongs to the untrusted side, which must not be
# able to stop a deploy: when it can't be read or written, that is a warning,
# and what is checked out is what gets deployed.
let
  deployNames = lib.attrNames deploy;
  lockSources = pkgs.writers.writePython3 "lock-sources" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./lock-sources.py);
in
pkgs.writeShellApplication {
  name = "review-deploy";
  runtimeInputs = [
    pkgs.git
    pkgs.less
    pkgs.gnugrep
    pkgs.coreutils
  ];
  text = ''
    target=''${1:-${defaultTarget}}
    case $target in
      ${lib.concatMapStringsSep "|" lib.escapeShellArg deployNames}) ;;
      *) echo "usage: review-deploy [${lib.concatStringsSep "|" deployNames}]" >&2; exit 2 ;;
    esac

    cd ${lib.escapeShellArg checkout}
    if [ -n "$(git status --porcelain)" ]; then
      echo "${checkout} has uncommitted changes; commit or remove them first" >&2
      exit 1
    fi

    # All branches, so that an empty repository (the first run, which pushes deployed) is no error
    old=$(git rev-parse HEAD)
    if git -c transfer.fsckObjects=true fetch --quiet --no-tags --prune \
      --upload-pack=${lib.escapeShellArg uploadPack} ${lib.escapeShellArg source} \
      "+refs/heads/*:refs/proposed/*"; then
      new=$(git rev-parse --quiet --verify "refs/proposed/${branch}^{commit}" || echo "$old")
    else
      echo "!!! Could not read the proposals from ${source}; going on with what is checked out" >&2
      new=$old
    fi

    lockAt() {
      git show "$1:flake.lock" 2>/dev/null || echo '{"root": "root", "nodes": {"root": {}}}'
    }

    # Nothing new also when the proposal is behind (the admin committed here since)
    if ! git merge-base --is-ancestor "$new" "$old"; then
      if ! git merge-base --is-ancestor "$old" "$new"; then
        echo "The proposal is not based on what is deployed ($old); rebase it onto that" >&2
        exit 1
      fi

      export LESS=FX LESSSECURE=1
      {
        git log --no-color --reverse --stat --format='commit %H%nAuthor: %an <%ae>%n%n%w(0,4,4)%B' "$old..$new"
        git diff --no-color --no-ext-diff --no-textconv --text "$old" "$new"
      } | less

      warn=0
      # zero-width characters, bidi controls, BOM, and C0 controls other than tab and newline
      # (printed through cat -v, which makes them visible instead of letting them act on the terminal)
      if git diff --no-color --no-ext-diff --no-textconv --text "$old" "$new" \
        | LC_ALL=C.UTF-8 grep -nP '[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{FEFF}]|[\x00-\x08\x0B-\x1F\x7F]' \
        | cat -v | grep .; then
        echo "!!! The diff has invisible or control characters (above)"
        warn=1
      fi

      if ! git diff --quiet "$old" "$new" -- flake.lock; then
        echo
        echo "flake.lock:"
        # The names and URLs are the proposal's, hence cat -v too
        if ! ${lockSources} <(lockAt "$old") <(lockAt "$new") | cat -v; then
          warn=1
        fi
      fi

      echo
      git diff --stat "$old" "$new" | tail -n1
      echo "Deploy $new to $target?"
      if [ "$warn" = 1 ]; then
        echo "There were warnings: answer 'deploy anyway' to go on."
        expected="deploy anyway"
      else
        expected=yes
      fi
      read -r -p "> " answer
      if [ "$answer" != "$expected" ]; then
        echo "Not deployed"
        exit 1
      fi
      git merge --quiet --ff-only "$new"
    else
      echo "Nothing new; deploying $old again"
    fi

    if ! git push --quiet --force --receive-pack=${lib.escapeShellArg receivePack} ${lib.escapeShellArg source} \
      HEAD:refs/heads/deployed; then
      echo "!!! Could not push the deployed commit to ${source}" >&2
    fi
    ${lib.optionalString (
      notify != null
    ) ''${notify} "deploy" "$(git log -1 --format='%h %s') to $target" || true''}
    case $target in
      ${lib.concatStrings (
        lib.mapAttrsToList (name: command: ''
          ${lib.escapeShellArg name}) ${command} ;;
        '') deploy
      )}
    esac
  '';
}
