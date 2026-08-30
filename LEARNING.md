# LEARNING.md — DevOps Learning Journal

The master index. Fifteen projects across five domains, studied for
**understanding**, not memorization.

## The study template

Every project doc uses the same four-part structure. The order is deliberate —
concepts first, code last (or never, until you've tried).

1. **Key points** — the concepts you must genuinely understand. If you can't
   explain these in your own words, you're not done, even if a script "works".
2. **When to use it** — the real situations that call for this technique (and when
   *not* to reach for it).
3. **Scenario** — a concrete story that makes the need obvious and memorable.
4. **Where AI misleads** — the specific traps where AI-generated answers (including
   Kiro's) tend to be wrong, outdated, unsafe, or subtly misapplied. This is the
   supervision checklist that lets you direct AI instead of trusting it blindly.

## How to work a project

1. Read the doc. Try to explain each **Key point** aloud before touching a keyboard.
2. Attempt the concept yourself, even partially.
3. Use AI to check your understanding and fill gaps — not to hand you the finished
   artifact. When AI gives you code, run it through the **Where AI misleads** list.
4. Mark your comprehension status below.

## Projects by domain

### Foundations & Automation — `foundations/`
| # | Project | Core concept | Doc |
|---|---------|--------------|-----|
| 01 | Idempotent Workspace Provisioner | Idempotency, error handling, retries | [doc](./foundations/01-idempotent-workspace-provisioner.md) |
| 11 | Command-Line Task Manager | argparse, SQLite, CRUD | [doc](./foundations/11-command-line-task-manager.md) |

### Observability & Operations — `observability/`
| # | Project | Core concept | Doc |
|---|---------|--------------|-----|
| 02 | System Resource Alerting Tool | Scheduling, thresholds, webhooks | [doc](./observability/02-system-resource-alerting-tool.md) |
| 03 | System Log Harvester & Process Auditor | Text processing, log parsing | [doc](./observability/03-system-log-harvester-process-auditor.md) |
| 04 | Log Rotation & Extraction Filter | logrotate, retention, disk safety | [doc](./observability/04-log-rotation-extraction-filter.md) |

### Networking — `networking/`
| # | Project | Core concept | Doc |
|---|---------|--------------|-----|
| 05 | High-Availability Proxy Gate | Reverse proxy, load balancing, health checks | [doc](./networking/05-high-availability-proxy-gate.md) |
| 06 | Local Nginx Web Server Setup | Virtual hosts, tuning, concurrency | [doc](./networking/06-local-nginx-web-server-setup.md) |
| 12 | Multi-Tenant Private Network Simulator | netns, veth, routing isolation | [doc](./networking/12-multi-tenant-network-simulator.md) |
| 13 | On-Prem Production Network Fabric | Proxmox SDN, VRF, BGP, Cilium LB, quorum | [doc](./networking/13-onprem-production-network-fabric.md) |

### Storage & Backup — `storage-and-backup/`
| # | Project | Core concept | Doc |
|---|---------|--------------|-----|
| 08 | Automated Backup System | Compression, integrity, retention | [doc](./storage-and-backup/08-automated-backup-system.md) |
| 09 | Kernel Partition & Storage Manager | LVM, filesystems, capacity failover | [doc](./storage-and-backup/09-kernel-partition-storage-manager.md) |

### Security & Secrets — `security/`
| # | Project | Core concept | Doc |
|---|---------|--------------|-----|
| 07 | SSH Hardening Utility | Key auth, firewall, fail2ban | [doc](./security/07-ssh-hardening-utility.md) |
| 10 | Local Git Workflow Hook Engine | Git hooks, secret scanning, pre-commit | [doc](./security/10-local-git-workflow-hook-engine.md) |
| 14 | Secrets Management Reference | Secret types, entropy, storage, injection, rotation | [doc](./security/14-secrets-management-reference.md) |
| 15 | Production Secrets & Identity | IAM, workload identity, KMS, PKI, dynamic secrets, signing | [doc](./security/15-production-secrets-and-identity.md) |

## Progress tracker

Status: ⬜ not started · 🟨 studying · 🟩 can explain it · ✅ can supervise AI on it

| # | Project | Status | Notes |
|---|---------|--------|-------|
| 01 | Idempotent Workspace Provisioner | ⬜ | |
| 02 | System Resource Alerting Tool | ⬜ | |
| 03 | System Log Harvester & Process Auditor | ⬜ | |
| 04 | Log Rotation & Extraction Filter | ⬜ | |
| 05 | High-Availability Proxy Gate | ⬜ | |
| 06 | Local Nginx Web Server Setup | ⬜ | |
| 07 | SSH Hardening Utility | ⬜ | |
| 08 | Automated Backup System | ⬜ | |
| 09 | Kernel Partition & Storage Manager | ⬜ | |
| 10 | Local Git Workflow Hook Engine | ⬜ | |
| 11 | Command-Line Task Manager | ⬜ | |
| 12 | Multi-Tenant Private Network Simulator | ⬜ | Precursor to 13 — same primitives, no hardware |
| 13 | On-Prem Production Network Fabric | ⬜ | Planned, gradual: 1 server → 2 → 3+. Not started |
| 14 | Secrets Management Reference | ⬜ | Cross-cutting — read alongside 07, 08, 10, 13 |
| 15 | Production Secrets & Identity | ⬜ | Roadmap. Explore each section against a real homelab decision |

## Note on this environment

You're on **Fedora 44**. Several projects in the source list assume Ubuntu/Debian
(`apt`, `ufw`). The docs flag Fedora equivalents (`dnf`, `firewalld`/`nftables`) —
knowing *why* a command differs across distros is itself a key learning goal.
