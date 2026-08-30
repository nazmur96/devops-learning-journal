# 05 — High-Availability Proxy Gate

**Objective:** Route/balance traffic across two backend servers via a local software router.

**Tech:** Nginx or HAProxy, Linux.

## Key points

- **Reverse proxy vs forward proxy.** A reverse proxy sits *in front of* your servers
  and represents them to clients. Understand this direction — it's the foundation.
- **Load balancing algorithms.** round-robin, least-connections, ip-hash (sticky
  sessions). Know *why* you'd pick each — e.g. ip-hash for session affinity when the
  app isn't stateless.
- **Health checks — passive vs active.** Passive: mark a backend down after it fails
  real requests. Active: proactively probe (`/health`) on an interval. Nginx open-source
  does mostly *passive* (`max_fails`/`fail_timeout`); true active checks need
  Nginx Plus or HAProxy. This distinction is a real understanding checkpoint.
- **Connection draining & failover.** When a backend dies, in-flight requests and how
  the proxy retries (`proxy_next_upstream`) determine whether users see errors.
- **Worker tuning.** `worker_processes`, `worker_connections`, keepalive to upstreams —
  what actually limits concurrency and why.

## When to use it

- Scaling horizontally: two+ app instances behind one entry point.
- Zero-downtime deploys (drain one backend, update, re-add).
- Any time a single backend is a availability or capacity bottleneck.

## Scenario

You run two copies of an API. One crashes at peak traffic. With a proxy doing health
checks, requests silently route to the healthy instance; users notice nothing. Without
it, half your requests would 502 until someone woke up.

## Where AI misleads

- **Claims Nginx OSS does active health checks.** It largely doesn't — that's Nginx
  Plus or HAProxy. AI conflates them constantly. Huge real-world trap.
- **Ignoring `proxy_next_upstream`.** AI's config may not retry a failed backend, so a
  single dead server still yields errors. Verify failover actually happens.
- **keepalive misconfig.** AI often omits upstream keepalive, hurting performance, or
  sets `worker_connections` to a number the OS `ulimit` won't allow.
- **Sticky-session assumptions.** AI may round-robin a stateful app, breaking logins.
  Understand whether your app needs affinity.
- **Testing under load.** AI rarely shows you how to *prove* balancing works (`curl` in
  a loop, `ab`/`wrk`). "Looks right" ≠ verified.
