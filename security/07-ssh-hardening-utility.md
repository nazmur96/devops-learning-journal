# 07 — Automated Host Security & SSH Hardening Utility

**Objective:** Audit and lock down remote access automatically.

**Tech:** Bash, OpenSSH, firewall (source says iptables/ufw — Fedora uses **firewalld/nftables**), fail2ban.

## Key points

- **Key-based auth beats passwords.** Understand the asymmetric-key model: private key
  stays with you, public key goes in `~/.ssh/authorized_keys` on the server. Then
  disabling `PasswordAuthentication` closes brute-force entirely.
- **`sshd_config` essentials.** `PasswordAuthentication no`, `PermitRootLogin no`,
  `PubkeyAuthentication yes`, `Port`, `AllowUsers`. Know what each does and the blast
  radius of getting it wrong.
- **The lock-yourself-out risk is the #1 concept here.** Always keep an active session
  open and test a *new* connection before closing it. Always back up `sshd_config` and
  `sshd -t` to validate before reload.
- **Firewall on Fedora.** Not `ufw`. It's **firewalld** (`firewall-cmd`) over
  **nftables**. Adding/removing a port and reloading is distro-specific knowledge.
- **Changing the SSH port** reduces log noise but is *security through obscurity* — and
  on Fedora, **SELinux** must be told about the new port (`semanage port -a`).
- **fail2ban** watches auth logs and bans offending IPs via the firewall. Understand
  jails, `maxretry`, `bantime`, and that it reads `/var/log/secure` on Fedora.

## When to use it

- Any internet-facing host with SSH open.
- Standardizing security posture across a fleet.

## Scenario

A new VM has password SSH on port 22. Within hours, bots are brute-forcing it. You run
the hardening steps: keys only, root login off, fail2ban jailing repeat offenders. Log
noise drops to near zero and the attack surface collapses.

## Where AI misleads

- **`ufw`/`iptables` on Fedora.** AI defaults to Ubuntu's `ufw` or raw `iptables`; Fedora
  is **firewalld/nftables**. Blindly following AI leaves your rules ineffective.
- **Locking you out.** AI cheerfully sets `PasswordAuthentication no` without telling you
  to verify key login first. This is how people brick access. Non-negotiable safety step.
- **Forgetting SELinux on port change.** Change the SSH port, `sshd` won't start —
  because SELinux blocks the new port and AI didn't mention `semanage port`.
- **`PermitRootLogin` nuance.** `prohibit-password` vs `no` differ; AI is often sloppy.
- **fail2ban log path.** AI may point it at `/var/log/auth.log` (wrong on Fedora).
- **No config backup / no `sshd -t`.** AI edits live config without a validated rollback.
