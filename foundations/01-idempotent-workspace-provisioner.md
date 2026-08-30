# 01 — Idempotent Workspace Provisioner

**Objective:** Turn a fresh Linux instance into a secured developer workspace, automatically and repeatably.

**Tech:** Bash, package managers, Git, Docker, Python.

## Key points

- **Idempotency is the whole game.** Running the script once or ten times must leave
  the system in the *same* correct state. This means: check-before-act ("is this
  package already installed?"), not blind "install it again". Understand the
  difference between an **imperative** step (`install X`) and a **desired-state**
  assertion (`ensure X is present`).
- **Exit codes and `set -euo pipefail`.** `-e` exits on any command failure, `-u`
  errors on unset variables, `-o pipefail` makes a pipeline fail if *any* stage
  fails (not just the last). Know *why* each matters and when `-e` bites you (e.g.
  a command you *expect* to sometimes fail needs `|| true`).
- **Retries with backoff** for network operations. Mirrors fail. A robust provisioner
  retries with increasing delays rather than dying on the first transient error.
- **Least privilege & user/group setup.** Understand `useradd`, groups, `sudoers`,
  and why you don't run everything as root.
- **Clean, actionable error output.** A failure should say *what* failed and *what
  to do*, not dump a stack trace.

## When to use it

- Onboarding a new machine/VM/container to a known-good baseline.
- Any time "works on my machine" drift is a problem — reproducibility.
- As the conceptual precursor to real config management (Ansible, cloud-init). You're
  learning by hand what those tools automate.

## Scenario

You get a new laptop (or spin up a cloud VM) Monday morning. Instead of a day of
manual setup you half-remember, you run one script. A mirror is down — the script
retries, then falls back, and finishes. You run it *again* by accident: nothing breaks,
nothing double-installs. That "safe to re-run" property is idempotency.

## Where AI misleads

- **AI writes imperative, not idempotent, scripts by default.** It'll happily emit
  `dnf install -y foo` without checking state or handling "already configured". Ask
  explicitly for idempotency and re-run safety, then verify.
- **Distro assumptions.** You're on **Fedora 44 → `dnf`**, but AI frequently defaults
  to `apt-get` (Debian/Ubuntu). Watch for this constantly.
- **Silent `set -e` traps.** AI often adds `set -e` then writes a line that legitimately
  returns non-zero, causing a confusing early exit. Understand this or you'll be lost.
- **Fake retry logic.** AI may write a loop that "retries" but doesn't actually detect
  failure (ignores exit codes). Check that the retry condition is real.
- **Over-broad `sudo`/curl|bash.** AI may suggest piping a remote script straight into
  a shell as root. Recognize the supply-chain risk.
