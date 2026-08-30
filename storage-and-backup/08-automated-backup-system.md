# 08 — Automated Backup System

**Objective:** Compress a directory and move it to external storage, safely.

**Tech:** Bash, tar, cron (or systemd timer on Fedora).

## Key points

- **tar fundamentals.** `tar` = *tape archive* (bundling), compression is separate:
  `-z` gzip, `-j` bzip2, `-J` xz. Understand the difference between archiving and
  compressing, and the common flags (`-c` create, `-x` extract, `-t` list, `-f` file).
- **Integrity checks.** A backup you can't restore is not a backup. Verify with a
  checksum (`sha256sum`) and/or a test extraction (`tar -tzf`). Understand *why*
  "it created a file" ≠ "the backup is good".
- **Retention / rotation.** Keep N backups, delete older. Understand `find -mtime +N
  -delete` and its danger (one wrong path = mass deletion).
- **Atomicity & partial failures.** If the script dies mid-copy, you must not leave a
  corrupt file that looks valid. Write to a temp name, then rename on success.
- **The 3-2-1 principle.** "External storage" matters: a backup on the same disk dies
  with the disk. Understand why offsite/separate media is the point.
- **Logging execution + timing** so a silently-failing nightly backup gets noticed.

## When to use it

- Protecting configs, databases, project dirs on any host.
- Before risky operations (a manual snapshot).

## Scenario

Ransomware or a `rm -rf` typo wipes a project directory Friday. Your nightly backup ran,
was checksum-verified, and lives on a separate volume. You restore in minutes. The team
that skipped integrity checks discovers their "backups" were all zero-byte files.

## Where AI misleads

- **No verification.** AI's backup script usually stops at "created archive" — no
  checksum, no test restore. The most dangerous omission.
- **`find -delete` footguns.** AI writes retention cleanup with paths/globs that can
  delete far more than intended if a variable is empty. Always review the delete path.
- **Same-disk "backup".** AI happily backs up to another folder on the same disk,
  missing the entire point of "external storage".
- **Unquoted variables / spaces in filenames.** Classic Bash bug AI reproduces, breaking
  on real-world paths.
- **cron assumptions on Fedora.** AI assumes `crond` is active; a systemd timer is more
  idiomatic. Verify the scheduler actually runs.
- **Ignoring exit codes of `tar`/`cp`.** AI logs "done" even when the copy failed.
