# 15 — Production Secrets & Identity (Roadmap)

**Objective:** The other 20–30% of secrets work — the part a *platform* automates
with identity and policy, not the part you do by hand. Project 14 taught what a
secret is and how its lifecycle works. This one is about how an organisation runs
that lifecycle at scale.

**Status:** Roadmap, not a build. Each section below is a future mini-project to
attempt against a real homelab decision. Do **not** learn these abstractly —
every one of them only makes sense once you have a concrete thing that needs it.

**Prerequisite:** [project 14](./14-secrets-management-reference.md). If the three
secret types and the generate→store→inject→use→rotate→revoke→detect lifecycle
aren't second nature yet, these topics will feel like ritual.

---

## The one idea that ties it together

Project 14's world: *you hold a secret and must protect it.*

This project's world: **stop holding secrets. Prove identity instead, and let a
system issue short-lived credentials on demand.**

Almost everything below is a variation on that shift — from *"who knows the
password"* to *"who is allowed, right now, and for how long."* A credential that
lives 15 minutes and is scoped to one action is a fundamentally smaller problem
than a permanent key in a file.

Read the topics in roughly this order; later ones assume the earlier.

---

## 15.1 — IAM and least privilege

**The concept.** Authentication is *who you are*; authorization is *what you may
do*. Least privilege means each identity gets the narrowest permission set that
still works, scoped and time-bound. This matters **more than encryption** — most
breaches are an over-permissioned identity, not cracked crypto.

**When it bites.** The moment more than one human or service touches a system. "It
works" and "only the right things can do it" are different questions.

**Homelab hook.** Kubernetes RBAC: a ServiceAccount with exactly the verbs it
needs on exactly the resources it touches. Kanidm/OIDC groups mapped to roles.

**Where AI misleads.** It hands you `cluster-admin` or a `*` policy to make the
error go away. That's not a fix, it's the vulnerability. Also conflates the roles:
authn vs authz is the distinction to hold.

**Try:** give one workload read access to one Secret in one namespace — and prove
it *cannot* read a second namespace's Secret.

---

## 15.2 — Workload identity / OIDC federation

**The concept.** A workload proves *what it is* to get credentials, instead of
holding a static key. A pod presents a signed ServiceAccount token; a GitHub
Actions job presents an OIDC token; the receiver validates it against a trusted
issuer and mints a short-lived credential. No long-lived secret to steal.

**When it bites.** Every static cloud key in CI or a pod is a standing liability.
Workload identity removes the secret entirely — this is the single highest-impact
topic in this list.

**Homelab hook.** Projected ServiceAccount tokens; SPIFFE/SPIRE for issuing
workload identities (SVIDs); OpenBao's Kubernetes auth method exchanging a pod's
token for a Vault token.

**Where AI misleads.** Defaults to "create a service account key and put it in a
Secret" — the exact anti-pattern federation exists to kill. Ask specifically for
OIDC/workload-identity and it usually can, but won't volunteer it.

**Try:** authenticate a pod to OpenBao using its ServiceAccount token — zero
stored secrets — and pull a value.

---

## 15.3 — Cloud KMS and envelope encryption

**The concept.** You rarely touch the root key. A KMS (AWS KMS, GCP KMS, Vault
Transit) holds a Key Encryption Key that never leaves it. To encrypt data you ask
KMS for a Data Encryption Key, use it, then store the *encrypted* DEK next to the
data. That nesting is **envelope encryption**. Rotating the KEK re-wraps DEKs
without re-encrypting terabytes of data.

**When it bites.** Encrypting data at scale, meeting compliance, or needing a
central audited chokepoint for "what can decrypt this."

**Homelab hook.** Vault/OpenBao Transit as a software KMS; Kubernetes
`EncryptionConfiguration` with a KMS provider so etcd Secrets are actually
encrypted at rest (see project 14 — they aren't by default).

**Where AI misleads.** Blurs the KEK/DEK layers, and suggests home-rolled
encryption where a KMS belongs. Rolling your own key management is the classic
own-goal.

**Try:** encrypt/decrypt through OpenBao Transit without ever seeing the key.

---

## 15.4 — PKI at scale

**The concept.** Project 14's TLS section, industrialised. An internal CA issues
certificates automatically; services present them for **mTLS** (both sides prove
identity); certificates are short-lived and auto-renewed so revocation is mostly
moot. Includes chains, intermediates, and **SSH certificates** — CA-signed, so you
stop managing `authorized_keys` by hand.

**When it bites.** Zero-trust internal networking, service mesh, or more than a
handful of machines to SSH into.

**Homelab hook.** cert-manager with a private issuer; OpenBao PKI as the CA; SSH
CA so hosts trust a signature instead of a key list.

**Where AI misleads.** Suggests long-lived certs (defeats the model), forgets the
service reload after renewal (project 14's classic failure), and glosses over
chain-of-trust so clients get "unknown authority" errors.

**Try:** stand up an internal CA, issue a 24-hour cert, and watch it auto-renew.

---

## 15.5 — Dynamic secrets

**The concept.** The payoff of the whole roadmap. Instead of storing a database
password, the vault **creates one on request**, scoped and expiring (e.g. a
Postgres role valid 1 hour). Nothing static exists to leak, and rotation is
automatic because credentials simply expire.

**When it bites.** Any datastore or cloud account where a static credential would
otherwise sit in a config forever.

**Homelab hook.** OpenBao database secrets engine issuing CloudNativePG
credentials on demand.

**Where AI misleads.** Defaults to a static password in a Secret because that's
the common example in its training data. Dynamic secrets are strictly better and
rarely suggested unless you ask.

**Try:** have OpenBao mint a temporary Postgres login, use it, and watch it die.

---

## 15.6 — Secret-zero (bootstrapping trust)

**The concept.** If the vault holds every secret, how does the *first* client
authenticate to the vault? This is the secret-zero / turtles-all-the-way-down
problem. Solutions anchor trust in something not-a-stored-secret: a TPM (project
14's `systemd-creds`), a cloud instance identity document, a k8s ServiceAccount
token, or a tightly-scoped single-use token (Vault response-wrapping / AppRole).

**When it bites.** Designing any automated system that retrieves its own secrets —
you always hit "but what unlocks the unlocker?"

**Homelab hook.** How OpenBao itself is unsealed (auto-unseal via TPM or a KMS),
and how the *first* pod authenticates.

**Where AI misleads.** Ignores the problem and leaves a plaintext bootstrap token
in a file — quietly recreating the very thing you were avoiding.

**Try:** trace, on paper, every step from cold boot to a running service holding a
live credential. Find where trust is first anchored.

---

## 15.7 — CI/CD secret handling

**The concept.** Pipelines are a prime exfiltration target — they legitimately
hold credentials and run arbitrary code. Modern practice: **OIDC federation**
(15.2) so the runner gets a short-lived cloud credential with no stored key;
plus masking, and awareness that masking is best-effort (base64 or split strings
slip through, and logs/artifacts/caches leak).

**When it bites.** The first time a pipeline needs to deploy or pull a private
dependency.

**Homelab hook.** Gitea Actions / GitHub Actions runners; OIDC to OpenBao;
ephemeral per-job credentials.

**Where AI misleads.** Says "add it to repository secrets" and stops — missing
that OIDC removes the stored secret entirely, and that masking is not containment.

**Try:** deploy from a pipeline using an OIDC-issued short-lived credential, no
stored key anywhere.

---

## 15.8 — Audit and incident response

**The concept.** Prevention fails eventually, so you need *who read what, when*,
and a rehearsed response: revoke at the issuer, rotate, assess blast radius,
review the audit log. A secret with no audit trail is one you can't reason about
after a compromise.

**When it bites.** After any suspected leak — and you'll wish you'd enabled the
audit log *before*.

**Homelab hook.** OpenBao audit devices; Kubernetes audit policy; alerting on
Secret reads.

**Where AI misleads.** Treats generation as the end of the story and never
mentions detection or response. "Delete the commit" (project 14) reappears here —
revoke first, always.

**Try:** enable OpenBao's audit log, read a secret, find yourself in the log.

---

## 15.9 — HSMs and hardware-backed keys

**The concept.** The high-assurance floor. A Hardware Security Module holds root
keys such that they *physically cannot* be exported; you send data in and get
signatures/ciphertext out. TPMs (project 14) are the consumer-grade cousin. This
is where a KMS's KEK ultimately lives in regulated environments.

**When it bites.** Compliance regimes (PCI, FIPS), or protecting a root CA / signing
key whose compromise is catastrophic.

**Homelab hook.** Mostly conceptual on one server — but your TPM plus
`systemd-creds` is the same idea at small scale, so you can genuinely learn the
model.

**Where AI misleads.** Conflates "encrypted key file" with "key that cannot be
extracted." The whole point of an HSM is non-extractability, not just encryption.

**Try:** articulate why a TPM-sealed key differs from a `chmod 600` key file.
(This is project 14's check-question #? — the non-extractability property.)

---

## 15.10 — Supply-chain signing

**The concept.** Secrets protect data at rest and in transit; **signing** protects
*integrity and provenance* — proof that an artifact is what it claims and came from
who it claims. Sign container images and releases (cosign/Sigstore), generate
provenance (SLSA), and **verify at admission** so unsigned artifacts can't run.
Uses the same asymmetric keys from project 14, for a different purpose.

**When it bites.** The moment you run software from anywhere but your own hands —
which is always.

**Homelab hook.** cosign-sign images in the Gitea pipeline; a Kyverno policy that
refuses unsigned images (the architecture doc already runs Kyverno).

**Where AI misleads.** Treats signing as optional polish, and confuses signing
(prove origin, public verification) with encryption (hide content). Different goals,
opposite direction of secrecy.

**Try:** sign an image, then have Kyverno reject an unsigned one.

---

## Suggested exploration order

Grounded in the homelab build, easiest-payoff first:

1. **IAM / least privilege** (15.1) — underlies everything else.
2. **Dynamic secrets** (15.5) — most visceral "aha", and OpenBao is already planned.
3. **Workload identity** (15.2) — removes the most standing risk.
4. **PKI at scale** (15.4) — cert-manager is already in the stack.
5. **KMS / envelope encryption** (15.3) — fixes etcd-at-rest from project 14.
6. **Secret-zero** (15.6) — you'll hit it naturally unsealing OpenBao.
7. **CI/CD secrets** (15.7) — when the Gitea runner needs credentials.
8. **Audit & IR** (15.8) — enable early, appreciate later.
9. **Supply-chain signing** (15.10) — when images flow to the cluster.
10. **HSMs** (15.9) — mostly conceptual until there's a root key worth the cost.

---

## Where AI misleads (the whole topic)

- **Static over dynamic, every time.** Its default answer is a stored key, because
  that dominates its training data. The modern answer — federate, issue short-lived
  — must be asked for explicitly.
- **Over-permissioning to clear an error.** `cluster-admin`, `*`, `chmod 777`,
  `0.0.0.0/0`. Fixes the symptom, opens the hole.
- **Prevention without detection or response.** Generation is treated as done;
  audit, revocation, and rotation-after-compromise go unmentioned.
- **Confidently outdated cloud specifics.** IAM condition keys, OIDC trust-policy
  syntax, and KMS APIs change; AI states old versions with full confidence. Verify
  against current provider docs.
- **Signing ≠ encryption.** Regularly conflated. One proves origin (public
  verification); the other hides content. Opposite goals.
- **The bootstrap hand-wave.** Elaborate secret management resting on a plaintext
  token in a file it never flags.

---

## Related

- [14 — Secrets Management Reference](./14-secrets-management-reference.md) — the
  foundation this assumes
- [13 — On-Prem Production Network Fabric](../networking/13-onprem-production-network-fabric.md)
  — where OpenBao, ESO, cert-manager, and Kyverno actually run
- [07 — SSH Hardening](./07-ssh-hardening-utility.md) — SSH certificates (15.4)
  supersede hand-managed keys
- [10 — Git Workflow Hook Engine](./10-local-git-workflow-hook-engine.md) — leak
  detection feeds audit/IR (15.8)
- `homelab-architecture-hetzner-dedicated-server.md` — the platform: OpenBao, ESO,
  Kanidm, cert-manager, Kyverno
