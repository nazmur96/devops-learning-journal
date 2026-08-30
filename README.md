# DevOps Learning Journal

A **learning workspace** for Linux, systems administration, networking, storage,
and security — the ground-up skills behind DevOps and platform engineering.

Fifteen concept-focused projects, grouped by domain. It started as "Linux
administration" and outgrew the name: the material now spans automation,
observability, networking fabrics, storage, and production secrets/identity.

## Why this repo exists

The goal is **understanding, not memorization**. AI can already produce working
scripts for every project here. The point is for *me* to understand each topic
well enough to **direct and supervise AI** — recognizing when its output is wrong,
outdated, unsafe, or subtly misapplied — rather than trusting it blindly.

A script I can't explain is not a success. The unit of progress is **comprehension**.

## How to use it

1. Read [`LEARNING.md`](./LEARNING.md) — the full index, the study template, and
   the progress tracker.
2. Pick a project doc. Each one is built around the same four parts:
   - **Key points** — the concepts to genuinely understand.
   - **When to use it** — situations that call for the technique.
   - **Scenario** — a concrete story where it matters.
   - **Where AI misleads** — traps, so I can supervise AI output.
3. Try to explain the concept out loud, or attempt it, before asking AI to write code.
4. Use AI to *check understanding and fill gaps*, not to hand over finished work.

## The projects, by domain

### Foundations & Automation
| # | Project | Core concept |
|---|---------|--------------|
| 01 | [Idempotent Workspace Provisioner](./foundations/01-idempotent-workspace-provisioner.md) | Idempotency, error handling, retries |
| 11 | [Command-Line Task Manager](./foundations/11-command-line-task-manager.md) | argparse, SQLite, CRUD |

### Observability & Operations
| # | Project | Core concept |
|---|---------|--------------|
| 02 | [System Resource Alerting Tool](./observability/02-system-resource-alerting-tool.md) | Scheduling, thresholds, webhooks |
| 03 | [System Log Harvester & Process Auditor](./observability/03-system-log-harvester-process-auditor.md) | Text processing, log parsing |
| 04 | [Log Rotation & Extraction Filter](./observability/04-log-rotation-extraction-filter.md) | logrotate, retention, disk safety |

### Networking
| # | Project | Core concept |
|---|---------|--------------|
| 05 | [High-Availability Proxy Gate](./networking/05-high-availability-proxy-gate.md) | Reverse proxy, load balancing, health checks |
| 06 | [Local Nginx Web Server Setup](./networking/06-local-nginx-web-server-setup.md) | Virtual hosts, tuning, concurrency |
| 12 | [Multi-Tenant Private Network Simulator](./networking/12-multi-tenant-network-simulator.md) | netns, veth, routing isolation |
| 13 | [On-Prem Production Network Fabric](./networking/13-onprem-production-network-fabric.md) | Proxmox SDN, VRF, BGP, Cilium LB, quorum |

### Storage & Backup
| # | Project | Core concept |
|---|---------|--------------|
| 08 | [Automated Backup System](./storage-and-backup/08-automated-backup-system.md) | Compression, integrity, retention |
| 09 | [Kernel Partition & Storage Manager](./storage-and-backup/09-kernel-partition-storage-manager.md) | LVM, filesystems, capacity failover |

### Security & Secrets
| # | Project | Core concept |
|---|---------|--------------|
| 07 | [SSH Hardening Utility](./security/07-ssh-hardening-utility.md) | Key auth, firewall, fail2ban |
| 10 | [Local Git Workflow Hook Engine](./security/10-local-git-workflow-hook-engine.md) | Git hooks, secret scanning, pre-commit |
| 14 | [Secrets Management Reference](./security/14-secrets-management-reference.md) | Secret types, entropy, storage, injection, rotation |
| 15 | [Production Secrets & Identity](./security/15-production-secrets-and-identity.md) | IAM, workload identity, KMS, PKI, dynamic secrets, signing |

## Standalone references

- [DevOps / SRE Authentication](https://github.com/nazmur96/devops-sre-authentication) — a long-form reference, drill book, hands-on labs, and troubleshooting playbook for authentication and identity across DevOps platforms.

This lives in its own repository because it is a complete reference book rather
than another numbered project in this journal.

## Working with Kiro here

A project-local [`.kiro/steering/learning-philosophy.md`](./.kiro/steering/learning-philosophy.md)
tells any Kiro session (CLI or IDE) to **teach concepts first** and avoid dumping
full solutions. Open Kiro from this directory and that guidance loads automatically.

## Environment

- Fedora Linux 44 (Workstation) — `dnf`, `systemd`, `firewalld`
- Shell: zsh interactive; scripts target bash
- Recommended: `sudo dnf install ShellCheck` for linting shell scripts

Several projects were sourced from Ubuntu/Debian-oriented material and reference
`apt`/`ufw`. The docs flag the Fedora equivalents (`dnf`, `firewalld`/`nftables`) —
knowing *why* a command differs across distros is itself a learning goal.

## Layout

```
.
├── README.md              # this file
├── LEARNING.md            # index + study template + progress tracker
├── .kiro/steering/        # learning-philosophy steering (shared, versioned)
├── foundations/           # 01, 11
├── observability/         # 02, 03, 04
├── networking/            # 05, 06, 12, 13
├── storage-and-backup/    # 08, 09
└── security/              # 07, 10, 14, 15
```

Project numbers are global and preserved across folders, because the docs
cross-reference each other by number (e.g. project 14 → 07, 08, 10, 13, 15).
