# 03 — System Log Harvester & Process Auditor

**Objective:** Detect anomalous log patterns (e.g. failed-login spikes) without hogging server resources.

**Tech:** Bash, awk, sed, grep, syslog/journald, webhooks.

## Key points

- **Where auth logs actually live.** On Debian/Ubuntu it's `/var/log/auth.log`. On
  **Fedora it's `/var/log/secure`** *and* the systemd **journal** (`journalctl`).
  Knowing the source per distro is half the battle.
- **The right tool for the job:** `grep` (find lines), `awk` (field-oriented extraction
  & counting), `sed` (stream edits). Understand *why* `awk` is better than a pile of
  `grep | cut | sort` for counting occurrences by field (e.g. per source IP).
- **Streaming vs loading.** Reading a huge log line-by-line (streaming) keeps memory
  flat; slurping it into a variable or array does not. "Without consuming excessive
  resources" is a real constraint — understand pipelines and why they're memory-cheap.
- **Rate/threshold logic.** "Spike" means *count over a time window*, not a raw total.
  Understand windowing and how to reset counts.
- **Signal vs noise.** Real auth logs are noisy; know how to isolate the meaningful
  event (`Failed password`, `Invalid user`) and aggregate by IP/user.

## When to use it

- Lightweight intrusion detection on a single host without a SIEM.
- Ad-hoc forensics: "who's been hammering SSH this week?"
- Feeding summaries into a chat webhook so humans notice trends.

## Scenario

Someone runs a slow brute-force against your SSH. Individually the lines are buried in
thousands of log entries. Your harvester counts failed logins per IP over the last hour,
sees 400 from one address, and posts a summary to Slack. You block the IP before they
get in.

## Where AI misleads

- **Wrong log path for the distro.** AI reflexively uses `/var/log/auth.log` — wrong on
  Fedora. It should use `/var/log/secure` or `journalctl -u sshd`. Catch this.
- **`cat file | grep` and other useless-use-of-cat / anti-patterns.** AI often writes
  inefficient pipelines. Fine functionally, but understand the cleaner form.
- **Regex that's too greedy or too narrow.** AI's log-matching regex frequently misses
  variants (IPv6, differing message formats) or over-matches. Verify against real lines.
- **Non-streaming memory hogs.** AI may read the whole file into memory (e.g. Bash
  arrays) — the opposite of the stated "don't consume excessive resources" goal.
- **No time window.** AI counts totals, not rates, so it can't actually detect a
  "spike". You must specify the windowing.
