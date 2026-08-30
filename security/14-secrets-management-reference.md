# 14 — Secrets Management Reference

**Objective:** Stop treating `openssl rand -hex 32`, `ssh-keygen -t ed25519 -a 100`,
and `kubectl create secret` as unrelated incantations. They are the *generate* step
of three different secret types, each with the same lifecycle after that.

**Tech:** OpenSSL, ssh-keygen, systemd-creds, age/SOPS, argon2, cert-manager /
Let's Encrypt, Kubernetes Secrets, OpenBao (Vault), restic.

**Why this doc exists:** those commands felt isolated because only the first step
was ever learned. This is the missing frame around them.

---

## Key points

### 1. Three secret types. Everything else follows from which one you have.

This is the idea that makes the scattered commands click.

| Type | What it is | Examples | How you make it |
|---|---|---|---|
| **Symmetric** | random bytes both sides hold | API keys, tokens, restic repo password, HMAC keys | CSPRNG: `openssl rand` |
| **Asymmetric** | keypair; private half never leaves the host | SSH keys, TLS certs, age/GPG, signing keys | `ssh-keygen`, `openssl genpkey`, `age-keygen` |
| **Derived** | stretched from human input by a KDF | login passwords, disk passphrases | `argon2`, `openssl passwd`, `mkpasswd` |

Consequences worth memorising:

- **Symmetric:** possession *is* access. Anyone holding it is you. Rotation means
  generate a new one and distribute it everywhere at once — which is why dual
  acceptance windows matter (see rotation below).
- **Asymmetric:** you prove possession without transmitting the secret. Only the
  public half travels. Rotation is cheaper: new keypair, re-register the public
  half, old private key becomes worthless.
- **Derived:** deliberately *slow* to compute. You **hash** passwords, you never
  encrypt them — encryption is reversible, which is the opposite of the goal.

Getting the type wrong is the root of most secret-handling bugs. "Encrypt the user
passwords" is a type error, not a coding error.

### 2. All randomness comes from one place

`openssl rand`, `ssh-keygen`, `age-keygen`, Python's `secrets`, `uuidgen` — all of
them ultimately read the kernel CSPRNG via `getrandom(2)`. So "is this random
enough?" reduces to one question: **how many bits of entropy?**

- **128 bits** — floor for anything that matters
- **256 bits** — long-lived secrets, anything you cannot easily rotate

```bash
openssl rand -hex 32      # 32 BYTES = 256 bits -> 64 hex characters
```

That answers the original question directly: `-hex 32` is 32 *bytes*, not 32
characters. Encoding changes the length, never the entropy:

| Command | Bytes | Entropy | Output length |
|---|---|---|---|
| `openssl rand -hex 16` | 16 | 128 bits | 32 chars |
| `openssl rand -hex 32` | 32 | 256 bits | 64 chars |
| `openssl rand -base64 32` | 32 | 256 bits | 44 chars |

Prefer `-hex` for anything that lands in a URL, a shell command, or a config file.
Base64 emits `+`, `/`, and `=`, which need quoting and corrupt URLs.

### 3. The lifecycle is identical for every type

```
generate → store → inject → use → rotate → revoke → detect leaks
```

Isolated commands only ever cover `generate`. Every real incident happens in the
other six.

### 4. Storage, worst to best

| Tier | Method | Verdict |
|---|---|---|
| ✗ | git, chat, Dockerfile, container image layer | never. images and history are forever |
| ✗ | shell history (`export SECRET=...`) | leaks to `~/.zsh_history` |
| ~ | file, mode `0600`, root-owned | acceptable floor for single-host bootstrap |
| ✓ | `systemd-creds` (TPM-sealed) | best single-host option on Fedora |
| ✓ | `age` / SOPS encrypted file in git | good for GitOps — encrypted at rest, diffable |
| ✓✓ | OpenBao / Vault with short-lived dynamic credentials | the real answer for a platform |

Your machine already has `age` and `sops` installed, and a TPM at `/dev/tpmrm0`,
so the two good options are available now.

`systemd-creds` is the modern Linux answer almost no AI mentions:

```bash
# Seal a secret to THIS machine's TPM. Needs root: TPM access is gated by
# polkit, so without sudo you get an authentication prompt and a failure.
printf '%s' "$SECRET" | sudo systemd-creds encrypt \
    --with-key=tpm2 --name=api-key - /etc/creds/api-key.cred

# In the unit:
#   LoadCredentialEncrypted=api-key:/etc/creds/api-key.cred
# The service reads it at $CREDENTIALS_DIRECTORY/api-key — a per-service
# tmpfs, root-only, never on disk, invisible to other services.
```

Note the `printf` rather than `echo`: `echo` appends a newline, which becomes part
of the secret and produces authentication failures that look like a wrong password.
That single trailing byte has cost people hours.

TPM sealing means the ciphertext is useless on any other machine. That is a real
security property, and also a real footgun: reinstall the TPM state and the secret
is unrecoverable. Keep an offline copy of anything you cannot regenerate.

### 5. Injection: how the secret reaches the process

Ranked by how easily it leaks:

| Method | Leak surface |
|---|---|
| CLI argument | **worst** — world-readable in `ps`, saved in shell history |
| Environment variable | `/proc/PID/environ`, crash dumps, `docker inspect`, inherited by children |
| File + tight perms | good — `--password-file` style flags exist for this reason |
| stdin / file descriptor | good — never touches disk |
| `systemd` credentials | best on a single host — per-service tmpfs |
| K8s projected volume | better than env — updates propagate, absent from `describe` |

Environment variables are the default everywhere and are *mediocre*. Worth knowing
precisely why rather than cargo-culting either direction:

```bash
docker inspect <container> | grep -i -A5 '"Env"'   # your "hidden" secret, printed
```

### 6. Kubernetes Secrets are not encrypted

The single most common misconception, and it matters for the homelab build.

```bash
echo -n 'hunter2' | base64      # aHVudGVyMg==   <- encoding, NOT encryption
```

A Kubernetes `Secret` is base64-encoded plaintext. It is stored **unencrypted in
etcd** unless you explicitly configure `EncryptionConfiguration` at rest. Anyone
with `get secret` in the namespace, or read access to etcd, or root on a node, has
the value.

So the production patterns are:

- **External Secrets Operator + OpenBao/Vault** — the secret lives in the vault;
  ESO syncs it in. This is what the homelab architecture already specifies.
- **SOPS + age**, or sealed-secrets — encrypted in git, decrypted in-cluster.
  Works with GitOps because ciphertext is safe to commit.
- **Short-lived dynamic credentials** — the vault mints a 1-hour database
  credential on demand. Nothing static to steal, rotation becomes automatic.
- **Workload identity** (SPIFFE/SVID, projected service account tokens) — the pod
  proves *what it is* instead of holding a shared secret. The direction of travel.

Mount as a **volume**, not `env`, when you can: volume contents update when the
Secret changes, and they do not appear in `kubectl describe pod` or crash dumps.

### 7. TLS is asymmetric keys plus an attestation

A certificate is just a public key plus identity claims, signed by a CA. Three
files, three roles:

- **private key** — never leaves the host, mode `0600`
- **CSR** — the request; contains the public key and the names you want
- **certificate** — the CA's signature over that

For Let's Encrypt, the choice that actually matters is the challenge type:

- **HTTP-01** — proves control by serving a file on port 80. Cannot do wildcards.
  Requires public inbound reachability.
- **DNS-01** — proves control via a TXT record. Handles wildcards **and private
  hosts with no public ingress**, which is why the homelab plan uses it.

Rotation for TLS is *renewal*, and the classic failure is not the renewal — it is
forgetting to reload the service afterwards. A cert renewed on disk that nginx
never re-read is still expired to every client.

### 8. Rotation is the part everyone skips

Three ideas do most of the work:

**Dual acceptance.** For symmetric secrets you cannot swap atomically across
several consumers. Accept old *and* new simultaneously, migrate, then retire the
old. Systems that support two active API keys exist precisely for this.

**Blast radius.** Before creating a secret, ask what breaks when it rotates. A key
shared by six services has six times the coordination cost, which is exactly why
it never gets rotated.

**Some secrets cannot be rotated at all.** A restic repository password is not a
credential — it is the key material the backup is encrypted with. Lose it and the
data is gone; change it and you must re-key the repository. That is why it gets
saved somewhere independent of the machine it protects, *before* the first backup.

On compromise, order matters: **revoke at the issuer first**, then clean up.
Deleting the commit does not un-leak the key — it is in every clone, every fork,
and probably a scraper's database already.

**Detection closes the loop.** Rotation you never trigger is theatre. Pre-commit
secret scanning (project 10, `ggshield`) and honeytokens — a decoy credential that
alerts when used — are how you find out.

---

## Quick reference

The "all in one place" table. Every entry is a *generate* step; the lifecycle above
applies to all of them.

| Need | Command | Notes |
|---|---|---|
| API key / token | `openssl rand -hex 32` | 256 bits. `-hex` avoids URL-unsafe chars |
| Shorter token | `openssl rand -hex 16` | 128-bit floor |
| Restic / backup password | `openssl rand -hex 32` | **store off-machine — unrecoverable** |
| SSH key | `ssh-keygen -t ed25519 -a 100 -C "you@host"` | see the `-a` note below |
| SSH cert-style rotation | new keypair + re-register public half | private key never moves |
| age keypair (file encryption) | `age-keygen -o key.txt` | pairs with SOPS |
| TLS private key | `openssl genpkey -algorithm ED25519 -out key.pem` | or let cert-manager handle it |
| Self-signed cert (lab) | `openssl req -x509 -newkey ed25519 -keyout k.pem -out c.pem -days 30 -nodes` | `-nodes` = no passphrase on the key |
| Password *hash* (system) | `openssl passwd -6` | SHA512-crypt; fine for `/etc/shadow` |
| Password *hash* (app) | `argon2` (`sudo dnf install argon2`) | argon2id. Never a bare SHA for app passwords |
| Seal a secret to this host | `systemd-creds encrypt --with-key=tpm2 --name=n - out.cred` | TPM-bound |
| Encrypt a file for git | `sops -e -i secrets.yaml` | with age recipients |
| K8s secret from file | `kubectl create secret generic n --from-file=k=./f` | base64, **not** encrypted |
| UUID (not a secret) | `uuidgen` | identifier, not a credential |

### The `ssh-keygen -a 100` nuance

`-a 100` sets **KDF rounds for the passphrase** protecting the private key on disk.
It makes brute-forcing a stolen key file slower.

It does nothing if the key has no passphrase. Ed25519 keys always use the modern
OpenSSH private key format, so `-a` is accepted either way — but it only buys you
something when you actually set a passphrase. AI answers routinely present `-a 100`
as a property of the key strength itself. It is not; it is disk-at-rest protection
for the private key.

---

## When to use it

- Any time you are about to type a command that produces a secret — check the type
  first, then the storage and injection question.
- Designing a service that stores user passwords (derived, argon2id, never
  reversible) versus one that issues API keys (symmetric, 256-bit, revocable).
- Before exposing anything to a network: what authenticates it, where does that
  credential live, and how do you rotate it?
- Reviewing AI-generated code that touches credentials — the traps below are common
  enough to be a checklist.

---

## Scenario

You set up encrypted off-site backups. Three secrets appear within five minutes,
and they are three different types:

1. A **key ID** and an **application key** from the storage provider — symmetric,
   issued by them, revocable from their console. Mixing up which is which produces
   an authentication error that reads like a network fault.
2. A **repository password** you generate with `openssl rand -hex 32` — symmetric,
   but *not* a credential: it is the encryption key. No console can reset it. Lose
   it and every backup is permanently unreadable. It must be stored somewhere that
   survives the machine dying.
3. An **SSH key** to reach the server — asymmetric. The private half never leaves
   your laptop; only the public half goes into `authorized_keys`.

Later, a fourth: an API key placed in a URL path "because it was simpler". It shows
up in the web server's access log, because logging the request path is what web
servers do. Now it must be rotated — and rotation is only possible because it was
the revocable kind. Had that been the repository password in a URL, the answer
would have been to re-key every backup.

Same five minutes, three types, four different correct answers.

---

## Where AI misleads

- **Password hashing with fast hashes.** AI suggests `sha256`/`md5` for storing
  passwords. Those are built to be *fast*, which is exactly wrong. Use argon2id
  (or bcrypt/scrypt). If the answer does not mention a work factor, it is wrong.
- **"Encrypt the password."** Type error. Passwords are hashed, one-way. Encryption
  implies you can decrypt, which means an attacker with your key can too.
- **Base64 described as securing Kubernetes Secrets.** Encoding is not encryption.
  AI frequently implies otherwise, and rarely mentions that etcd stores them in the
  clear by default.
- **Secrets via CLI args or `echo`.** `ps` is world-readable and shells log history.
  AI produces `--password=hunter2` constantly.
- **Env vars presented as secure.** They leak via `/proc`, crash dumps,
  `docker inspect`, and every child process. Not forbidden — just not "secure".
- **`openssl rand -base64` where the output must be URL- or shell-safe.** `+/=`
  will break things intermittently, which is the worst way to break.
- **Entropy arithmetic.** `-hex 32` is 32 bytes → 64 characters → 256 bits. AI (and
  humans) routinely conflate byte count with character count.
- **`-a 100` sold as key strength.** It is passphrase KDF rounds for the private key
  file. Irrelevant without a passphrase.
- **RSA 2048 by reflex** for SSH, when ed25519 is shorter, faster, and safer.
- **`systemd-creds` never mentioned**, despite being present on this machine and
  the best single-host option available.
- **Distro traps.** `mkpasswd` is a *different program* depending on the distro —
  here it is the standalone `mkpasswd` 5.6.6 wrapping `crypt(3)`. AI often assumes
  the Debian `whois` variant with different flags. `openssl passwd -6` is portable.
  And expect `apt`/`ufw` answers when you are on `dnf`/`firewalld`.
- **"Just chmod 777 it."** Fixes the error, creates the vulnerability.
- **Rotation ignored entirely.** AI will generate a secret and never mention dual
  acceptance windows, revocation, or the fact that some secrets cannot be rotated.
- **"Delete the commit and you're fine."** You are not. Revoke first.

---

## Check your understanding

1. Why can you rotate an SSH key without touching any other machine's private
   data, but rotating a shared API key needs a coordination window?
2. A colleague stores user passwords with `sha256` and says it is fine because the
   hashes are salted. What is still wrong?
3. You `base64 -d` a Kubernetes Secret and see the plaintext. Which security
   property was violated — and which was never there to begin with?
4. Your TLS certificate renewed successfully at 03:00 and clients still see an
   expired cert at 09:00. What was missed?
5. Which of the secrets in the Scenario above cannot be rotated, and why does that
   change where you store it?

---

## Related projects

- [07 — SSH Hardening Utility](./07-ssh-hardening-utility.md) — asymmetric keys in
  practice, and how to avoid locking yourself out
- [08 — Automated Backup System](../storage-and-backup/08-automated-backup-system.md) — the
  unrotatable-secret problem, concretely
- [10 — Local Git Workflow Hook Engine](./10-local-git-workflow-hook-engine.md) —
  leak detection, the last stage of the lifecycle
- [13 — On-Prem Production Network Fabric](../networking/13-onprem-production-network-fabric.md)
  — where OpenBao, ESO, and cert-manager land in the platform
