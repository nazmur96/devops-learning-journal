# 02 — System Resource Alerting Tool

**Objective:** Periodically audit CPU, RAM, and disk; alert *before* failure.

**Tech:** Python or Bash, cron / systemd timers, webhooks (Slack/Discord/Mailgun).

## Key points

- **Where the numbers come from.** CPU load vs CPU utilization are different things
  (`/proc/loadavg`, `/proc/stat`, `top`, `mpstat`). Memory: `free`, `/proc/meminfo` —
  and understand why "used" memory is misleading (cache/buffers). Disk: `df` (space)
  vs `du` (usage) vs inodes (you can be "full" with free space if inodes run out).
- **cron vs systemd timers.** cron is simple and ubiquitous; systemd timers give you
  logging (`journalctl`), dependencies, `OnCalendar`, missed-run catchup
  (`Persistent=true`), and per-unit resource control. On Fedora, **systemd timers are
  the native choice**. Know the tradeoffs.
- **Thresholds & hysteresis.** A naive ">90%" alert *flaps* — fires repeatedly as usage
  bounces around 90. Understand debouncing / cooldowns / "alert once until recovered".
- **Webhooks = HTTP POST with a JSON payload.** Understand the request shape, secrets
  handling (don't hardcode the URL/token), and failure handling if the webhook is down.
- **Historical logging** so you can see trends, not just instantaneous spikes.

## When to use it

- Any always-on host (server, VM, Pi) where silent resource exhaustion causes outages.
- As a lightweight alternative to heavy monitoring stacks (Prometheus/Grafana) when
  you just need "ping me at 90%".

## Scenario

A disk slowly fills with logs over weeks. At 3am it hits 100%, the database can't write,
the app crashes. With this tool, you'd have gotten a Slack ping at 85% days earlier — a
calm Tuesday fix instead of a 3am outage.

## Where AI misleads

- **Parsing tool output instead of `/proc`.** AI often scrapes `top`/`free` text, which
  is fragile across locales and versions. The robust source is `/proc` and structured
  tools. Question brittle text parsing.
- **No flap control.** AI's first draft usually fires an alert every run once over
  threshold — spammy. You must ask for cooldown/hysteresis.
- **cron on Fedora.** AI may assume cron is running; Fedora Workstation may not have
  `crond` active by default. systemd timers are more idiomatic — verify what's enabled.
- **Secrets in the script.** AI tends to inline the webhook URL. That leaks in git.
  Know to use an env var or a config file outside the repo.
- **Disk "full" misdiagnosis.** AI checks `df` space but forgets **inodes** — a classic
  real-world gotcha it rarely raises unprompted.
