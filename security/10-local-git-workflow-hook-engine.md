# 10 — Local Git Workflow Hook Engine

**Objective:** Enforce formatting and security rules *before* code leaves the workstation.

**Tech:** Git hooks, the pre-commit framework, shell tools.

## Key points

- **What Git hooks are.** Scripts Git runs at lifecycle events. `pre-commit` (before a
  commit is recorded), `commit-msg` (validate message), `pre-push`. They live in
  `.git/hooks/` — which is **not committed**, so raw hooks don't travel with the repo.
- **Why the `pre-commit` framework exists.** It solves the "hooks aren't shared" problem:
  a committed `.pre-commit-config.yaml` defines hooks, and `pre-commit install` wires
  them up for every clone. Understand this gap and how the tool closes it.
- **Client-side vs server-side enforcement.** Client hooks can be **bypassed**
  (`git commit --no-verify`). They're a helpful guardrail, *not* a security boundary.
  True enforcement needs server-side (CI, protected branches). Understanding this
  distinction is critical — don't rely on local hooks for real secret prevention.
- **Secret scanning.** Detecting plaintext credentials means regexes/entropy checks
  (`detect-secrets`, `gitleaks`). Understand false positives/negatives.
- **Fast & deterministic.** A slow hook gets disabled by frustrated devs.

## When to use it

- Preventing secrets, debug prints, or unformatted code from ever being committed.
- Standardizing lint/format across a team automatically.

## Scenario

You're about to commit a config with an AWS key pasted in for "just a quick test". The
pre-commit secret scanner blocks the commit and points at the line. Crisis averted —
because that key never entered git history (where deleting it is painful).

## Where AI misleads

- **Treating client hooks as a security control.** AI implies local hooks *prevent*
  secret leaks. They don't — `--no-verify` bypasses them. The real defense is
  server-side + rotating any leaked secret. AI rarely stresses this.
- **Hooks-don't-travel gap.** AI writes a raw `.git/hooks/pre-commit` and forgets it
  won't be shared on clone; the pre-commit framework is the fix.
- **Removing a secret from the working file ≠ from history.** Once committed, it's in
  git history forever unless you rewrite it. AI often "fixes" only the current file.
- **Over-broad secret regexes.** AI's patterns either miss real keys or flag everything,
  training devs to `--no-verify` habitually.
- **Non-portable hook scripts.** AI writes bashisms that fail on other shells/OSes.
