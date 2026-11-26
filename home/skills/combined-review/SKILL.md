---
name: combined-review
description: Runs two reviews of the same code in parallel subagents, the platform's own code review at its most thorough local setting and the security-audit-diverse audit, then hands back one combined summary. Use when the user asks for a combined, full, or complete review, or invokes this skill by name.
---

# Combined review

Run two independent reviews of the same target in parallel, each in its own subagent, and report both together:

1. **Code review**: the platform's built-in code review at its most thorough local setting.
2. **Security audit**: the `security-audit-diverse` skill.

Both are expensive and both start agents of their own. Invoking this skill is the user's explicit request for that cost.

## Target

Settle the target once and give both reviews the same one:

- whatever the user named: a branch, a PR, a commit range, or paths;
- otherwise the current branch's changes against its base branch, including uncommitted changes.

Note the exact refs (base, head, and whether the worktree is dirty) so both reviews look at the same code. Pass the security audit the same scope as a scoped run (the diff between the two refs, or the named paths), unless the user asked for an audit of the whole codebase.

## Launching

Start both subagents at once and let them run in parallel. Each needs to delegate further. If the platform does not let a subagent start agents, run the two reviews in this agent instead, one after the other. Never downgrade either one to a single-agent pass.

Tell each subagent that it is one of two parallel reviews, that it must not edit target source, commit, push, or post comments, and that it should return its findings in full rather than a summary.

### Hosts with Nix

When `nix` is on `PATH` (NixOS, or any system with Nix installed, such as one managed by system-manager or Home Manager), get missing tools through Nix. On NixOS especially, most build tools, interpreters, and test runners are not on `PATH` otherwise. Tell both subagents, and have them tell every agent they start:

- A missing tool is not a reason to skip running or testing something. Get it from nixpkgs, for example `nix shell nixpkgs#python3 nixpkgs#gcc -c <command>`, or the project's own dev shell (`nix develop -c <command>`) when the project has one and running its code is acceptable for that review. The security audit has stricter rules for this; `security-audit-diverse` covers them.
- The host cannot run several Nix builds or evaluations at once, and these reviews run many agents in parallel. Create an empty lock file in a scratch directory outside the target before launching, pass its path to both subagents, and have every agent wrap every `nix` command in `flock <lock file> nix ...`. The security audit uses this lock file instead of creating its own.
- If a tool really cannot be obtained, say exactly what was not tested and why.

### Code review subagent

Use the platform's own review at its maximum local effort, not a cloud or remote review:

- **Claude Code**: the `code-review` skill with the `max` level and the target, for example `max main...HEAD` or `max <PR number>`. Not `ultra`, which runs in the cloud.
- **Codex / ChatGPT**: the built-in review (`/review` interactively). From a subagent, run it non-interactively with the strongest available model and the highest reasoning effort it supports, for example `codex exec review --base <base> -c review_model="<model>" -c model_reasoning_effort="xhigh"`, or `--uncommitted` / `--commit <sha>` to match the target. If that command cannot run (missing, sandboxed, no network), have the subagent review the same diff itself on the strongest model, looking for correctness bugs, and say that the built-in review was not available.
- **Other platforms**: their built-in review command or skill at its most thorough local setting. If there is none, the subagent reviews the diff itself for correctness bugs and says so.

### Security audit subagent

Invoke `security-audit-diverse` with the target scope. It writes its report files to its own output directory outside the target; have the subagent return that path along with the findings.

If the security audit stops to ask the user something (for example, no second model is available), pass the question to the user rather than answering it yourself.

## Combined report

When both are done, report to the user:

1. **Target**: refs and scope reviewed.
2. **Security findings**: confirmed findings by severity, then needs-validation items, each with location and one-line summary. Link the audit's report directory.
3. **Code review findings**: in the order the review ranked them.
4. **Overlap**: point out where both reviews flagged the same code or root cause, and merge those entries rather than listing them twice.
5. **Gaps**: anything either review could not do (a missing model, an unavailable built-in review, an incomplete audit run).

Keep the findings as each review reported them. Do not drop, re-rank, or re-verify them yourself. Do not apply fixes unless the user asks.
