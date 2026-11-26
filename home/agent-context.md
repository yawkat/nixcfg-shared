Run Nix build/eval commands (`nix build`, `nix flake check`,
`nixos-rebuild`, ...) one at a time, never concurrently, including in
background tasks or parallel subagents.

Missing tools are not a reason to skip building or testing: get them with
`nix shell nixpkgs#<pkg> -c <command>` or the project's `nix develop`.
