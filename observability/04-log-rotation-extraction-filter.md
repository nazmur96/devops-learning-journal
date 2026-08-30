# 04 — Log Rotation & Extraction Filter

**Objective:** Keep large app logs from filling the disk; extract only fatal events.

**Tech:** syslog/journald, logrotate, awk/sed.

## Key points

- **Why rotation exists.** A single ever-growing log file eventually fills the disk and
  takes down the host. Rotation = periodically start a fresh file, compress old ones,
  and delete the oldest. Understand the lifecycle: active → rotated → compressed → purged.
- **How logrotate works.** It's config-driven (`/etc/logrotate.conf`,
  `/etc/logrotate.d/*`), run on a schedule (a cron job or systemd timer). Key
  directives: `daily`/`weekly`, `rotate N` (how many to keep), `compress`,
  `delaycompress`, `missingok`, `notifempty`, `copytruncate` vs `create`.
- **`copytruncate` vs `create` — the subtle, critical one.** If an app holds the log
  file open, plain rotation (rename + new file) can leave the app writing to the old
  inode. `copytruncate` copies then truncates in place (tiny race window, possible lost
  lines). Knowing *why* you'd choose each is a real signal of understanding.
- **Retention = exactly N.** "Retain 7 iterations" maps to `rotate 7`. Understand off-by-one.
- **Extraction filter.** Producing a clean file of only `FATAL`/`ERROR` lines is an
  `awk`/`grep` job layered on top — separate concern from rotation itself.

## When to use it

- Any service that logs to files (nginx, custom apps) on a box with finite disk.
- When you must satisfy a retention policy (keep N days, then delete).

## Scenario

An app logs verbosely. Without rotation the file hits 40GB and the disk fills; the
service dies. With logrotate: daily rotation, gzip old logs, keep 7, delete the 8th.
Disk stays bounded, and a nightly filter writes `fatal-YYYY-MM-DD.log` with only the
lines that matter for the on-call engineer.

## Where AI misleads

- **`copytruncate` blindness.** AI rarely explains the open-file-handle problem, so its
  config can silently lose or duplicate log lines. This is the #1 real-world logrotate
  gotcha — make AI justify its choice.
- **Testing rotation.** AI forgets `logrotate -d` (debug/dry-run) and `-f` (force). You
  should never wait a day to find out your config is wrong.
- **journald vs files.** On Fedora, much logging goes to the **systemd journal**, which
  rotates via `journald.conf` (`SystemMaxUse=`), *not* logrotate. AI may configure
  logrotate for logs that don't exist as flat files.
- **Permissions after rotation.** Wrong `create` mode/owner can make the app unable to
  write the new file. AI often omits this.
- **Compression timing.** `delaycompress` matters when a process still writes briefly to
  the just-rotated file; AI usually ignores it.
