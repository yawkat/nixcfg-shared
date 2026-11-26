---
name: security-audit-diverse
description: Full security audit using the security-audit skill at the deep profile, with every hunter assignment run in parallel by several different strong models and their results merged. Use when the user asks for a diverse, multi-model, or cross-model security audit, or invokes this skill by name. Not for quick security questions; use security-audit directly for those.
---

# Diverse security audit

Run the `security-audit` skill in **full audit mode** with the **`deep`** profile. Everything that skill says still applies: phases, write isolation, sandboxing, evidence bar, ledger, validators, report. This skill changes only how hunters are launched.

Load `security-audit` first and follow it. If it is not installed, stop and say so.

## Settings

- **Mode**: full audit. Invoking this skill is the explicit request for it, so do not ask whether a full audit was meant.
- **Profile**: `deep`. Record it in `run-metadata.json`.
- **Scope**: whatever the user named (paths, subsystem, diff between two refs). Without one, the whole target.
- **Budget**: none unless the user sets one. If they do, remember that every hunter assignment now costs one invocation per hunter model.
- **Hunter models**: the set chosen below. Record it in `run-metadata.json` as `hunter_models`.

## Choosing hunter models

Different models miss different things. The goal is two (at most three) models that are each strong at code and security reasoning but differ from each other: a different size class, a different generation, or a different training lineage. A weaker model does not add useful diversity; it adds noise.

1. If the user named models, use exactly those.
2. Otherwise pick from the models the platform's delegation tool can actually select. Prefer this order:
   - the largest, most capable model available;
   - the newest strong model that is not the same model (often a newer, mid-size release that is close to the largest one).
   Skip small or efficiency-tier models.
3. Current defaults, which may be out of date. When a newer generation exists, apply the rule above rather than these names:
   - **Claude Code**: `opus` and `fable`. Opus releases tend to be newer; Fable is the larger model.
   - **Codex / ChatGPT**: GPT-6 Astra (largest) and the newest Sol (for example GPT-6.1 Sol, which is newer and close to Astra). Do not use Luna for hunting.
   - **Other platforms**: the two strongest distinct models offered.
4. If the delegation tool cannot choose a model per agent, or only one suitable model is available, stop before any agent launches. Tell the user, and run a single-model `deep` audit only if they agree. Never report a single-model run as diverse.

Use one strong model for the parent, reconnaissance, coverage critics, and verifiers (the platform default or the largest available). Diversity is for finding candidates; verification just needs to be rigorous and independent.

## Hunting with several models

Every hunter assignment the `security-audit` workflow would launch becomes one hunter per chosen model, all with **the same coverage units and the same prompt**, launched in parallel. Do not split units between models: each model covers all of the hunted code, so a finding one model misses can still come from the other.

- Give each hunter its own canonical agent ID with the model as a suffix, for example `h-auth-01-opus` and `h-auth-01-fable`, and its own `scratch/` and `artifacts/` roots, exactly as for any other hunter.
- Hunters of the same assignment are independent. Do not show one model's result to another.
- Do not tell a hunter that other models are hunting the same unit, and do not tell it which model it is.

## Hosts with Nix

When `nix` is on `PATH` (NixOS, or any system with Nix installed, such as one managed by system-manager or Home Manager), get missing tools through Nix. On NixOS especially, most compilers, interpreters, test runners, and sandboxing tools are not on `PATH` otherwise. A missing tool is not a reason to skip a local check and fall back to source-only reasoning. Copy this section into every reconnaissance, hunter, and verifier prompt.

- **Getting tools**: get them from nixpkgs, for example `nix shell nixpkgs#python3 nixpkgs#gcc -c <command>`, or build a package once and put its `bin/` on `PATH`: `nix build nixpkgs#<pkg> --no-link --print-out-paths`. If flakes are not enabled, add `--extra-experimental-features 'nix-command flakes'`, or use `nix-shell -p <pkg> --run <command>`. These come from the binary cache, not from the target, so they count as tools already available locally under the `security-audit` rule against installing dependencies. Do not use the target's own `flake.nix`, `shell.nix`, or dev shell outside the sandbox: evaluating it and its shell hooks run target-controlled code.
- **Sandboxing**: the controls `security-audit` requires are available the same way: `nixpkgs#bubblewrap` (`bwrap --unshare-all` for no network, read-only binds for target and toolchain, a writable bind for `scratch/` only, `--clearenv`), plus `prlimit` or `systemd-run --user --scope -p MemoryMax=... -p CPUQuota=... -p TasksMax=...` for resource limits. Bind the needed `/nix/store` paths read-only into the sandbox.
- **One Nix command at a time**: the host cannot run several Nix builds or evaluations at once. The parent creates an empty lock file at `<output-dir>/nix.lock` before launching agents (or uses the one it was given, for example by `combined-review`), and every agent wraps every `nix` command in `flock <output-dir>/nix.lock nix ...`. Agents only open this file to lock it; it is not a shared run file. Prefer fetching the tools a wave obviously needs in the parent before launching it, and pass the store paths in the prompts.
- If a tool really cannot be obtained, record the exact blocker on the check, as `security-audit` requires; do not silently skip the test.

## Merging hunter results

Merge the parallel results of one assignment into one ledger update per unit before running the coverage critic. Coverage critics and later waves see only the merged ledger.

For each coverage unit:

1. **Candidates**: take the union of all hunters' candidates. Consolidate by fingerprint and then by root cause, as `security-audit` requires. When two models report the same root cause, keep one candidate with the strongest complete trace and record which models found it in a parent bookkeeping field (`found_by`), outside the schema fields. A candidate found by only one model is not weaker for it; it goes to validation like any other.
2. **Status**: the strongest status wins: `candidate` over `blocked` over `covered`. A unit is `covered` only if every model's hunter closed it as covered. Merge unresolved facts from all `blocked` results.
3. **Owner**: the unit's `agent_id` is the hunter whose result set the merged status (on a tie, the first model in `hunter_models`). Keep every hunter's checks in `local_checks` under that hunter's own agent ID; the ledger allows independently owned checks in one unit. The unit's `reviewed_paths` is the union of all checks' paths.
4. **Uncovered leads and hardening**: take the union, deduplicated.
5. **Failures**: if one model's hunter fails or returns a malformed result, keep the others' merged result but record the gap on the unit (bookkeeping field `missing_models`). If the merged result would be `covered`, leave the unit `planned` and rerun only the missing model's hunter in the next wave, so that `covered` always means every model looked.

Run `validate-coverage-ledger.cjs` after each merge, as usual.

Validation follows the `deep` profile unchanged: one fresh verifier per consolidated candidate, not one per model that found it.

## Report

In `REPORT.md`, add to the coverage statement which hunter models ran, and for each confirmed or needs-validation finding, which models found it. Mention units where a model's hunter was missing. A brief count of findings by model (found by all, found by only one) helps the user judge whether the diversity is paying off.
