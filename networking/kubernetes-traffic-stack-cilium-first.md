---
title: "Kubernetes Traffic Stack: From NLB vs ALB to a Cilium-First Setup"
description: "An NLB forwards connections; an ALB routes requests. Why your in-cluster gateway sits behind an NLB, whether a five-tool Cilium + HAProxy + Traefik + Istio stack is worth it, and a Cilium-first setup that adds tools only for a named need."
crosspost:
  devto: full
  linkedin: summary
  tags: [kubernetes, aws, networking, devops]
  hashtags: [Kubernetes, Cilium]
  canonical_url: https://github.com/nazmur96/devops-learning-journal/blob/main/networking/kubernetes-traffic-stack-cilium-first.md
  linkedin_image:
    path: img/cilium-first-traffic-stack.png
    alt: "An NLB forwards connections; an ALB routes requests. Top: User to NLB, which reads IP and port only, to Cilium Gateway, which decrypts, reads and decides, to Services. Below it: User to ALB, which decrypts, reads host, path and headers and decides, to Services. Then a table, Cilium first, add a tool only for a named need. Pod networking and policy: Cilium, swap basically never. Observability: Hubble, add Prometheus or OpenTelemetry for app metrics. External IP on bare metal: Cilium BGP or L2, HAProxy plus keepalived for a separate edge box. External IP on AWS: NLB, ALB if you need WAF or AWS login. Ingress routing: Cilium Gateway, Envoy Gateway or Traefik for rate limits and OIDC login. Service mesh: nothing yet, Istio ambient for strict identity and canaries. Everywhere: cert-manager and ExternalDNS."
  summary: |
    When you run your own gateway inside Kubernetes, it usually sits behind an NLB, not an ALB. Why? An NLB only reads the envelope: IP and port. It forwards the connection. An ALB opens the envelope and reads the letter: host, path, headers. It routes the request itself.

    So with an NLB, the routing decision happens inside your cluster, in YAML you control, and the same setup runs on AWS, GCP or bare metal. With an ALB it happens in AWS, but you get WAF, ACM certificates and Cognito login without running anything in the cluster.

    Then I looked at a popular five-tool stack: Cilium, HAProxy, Gateway API, Traefik and Istio. The idea is solid (a dumb front door, smart routing inside), but it isn't more versatile. It's more pieces. Cilium and Istio can both already do Traefik's job.

    Where I landed: Cilium first. It covers pod networking, network policy, external IPs, Gateway API routing and Hubble observability. Add Envoy Gateway only when you need rate limits or OIDC login, and Istio ambient only when you need strict service identity. Every extra tool needs a named reason.

    The full write-up has the diagrams, the things that bite when you combine these tools, and what it looks like in a homelab vs on EKS. Link below.
---

![An NLB forwards connections, an ALB routes requests, and a Cilium-first table of which tool to use at each layer](https://raw.githubusercontent.com/nazmur96/devops-learning-journal/main/networking/img/cilium-first-traffic-stack.png)

**Short version:** an NLB only forwards connections, so a gateway inside the cluster makes the routing decisions; an ALB routes requests itself. The best-of-both-worlds setup uses Cilium at every layer by default and adds another tool only for a named need.

This builds up in four parts: (1) NLB vs ALB, (2) a five-tool combo, (3) Cilium everywhere, (4) the recommended stack.

## Part 1: How traffic gets in, NLB vs ALB

When you run your own gateway (for example Cilium Gateway) in the cluster, it usually sits behind an NLB. The NLB only passes traffic through, so your gateway makes the routing decisions. An ALB would do the routing itself.

Every request has two layers of information:

- **The envelope (Layer 4):** source IP, destination IP, port. "Someone at 1.2.3.4 wants to talk on port 443."
- **The letter inside (Layer 7):** the actual HTTP request. "GET `shop.example.com/api/cart`, with these headers and cookies."

An **NLB** (Network Load Balancer) only reads the envelope. An **ALB** (Application Load Balancer) opens the envelope and reads the letter.

**NLB + Cilium Gateway.** The NLB sees "TCP connection on port 443" and forwards it to the gateway pods. It never reads the HTTP part, and the traffic is usually still encrypted as it passes. The gateway then decrypts TLS (it holds the certificate), reads hostname, path and headers, applies your `HTTPRoute` rules, and sends the request to the right Service.

**ALB on its own.** The ALB decrypts TLS, reads the HTTP request and applies routing rules itself. The AWS Load Balancer Controller turns your Kubernetes Ingress or Gateway objects into ALB rules. Traffic goes straight to the pods: the ALB *is* the gateway.

```text
NLB + in-cluster gateway
  User ──► NLB ─────────────────► [ Cilium Gateway ] ──► Services
           reads IP + port only     decrypts TLS, reads     cart · catalog · ui
           forwards the connection  host, path, headers;
                                    DECIDES

ALB alone
  User ──► [ ALB ] ─────────────────────────────────────► Services
           decrypts TLS, reads host, path, headers; DECIDES   cart · catalog · ui
           managed by AWS, rules from your Ingress/Gateway YAML

[ brackets ] = where the routing decision is made
```

With an NLB, the routing decision happens inside your cluster; with an ALB, it happens in AWS before traffic reaches the cluster.

### Why pick one over the other

| | NLB + your own gateway | ALB alone |
|---|---|---|
| Who routes | Gateway pods in the cluster | The ALB (managed by AWS) |
| Where rules live | Kubernetes YAML only | Kubernetes YAML turned into AWS rules |
| Portability | Same setup on AWS, GCP, bare metal | AWS only |
| Features | Everything the gateway can do: retries, traffic splitting, header rewrites, mTLS | More limited routing, but native ACM certificates, WAF and Cognito login |
| Cost of running | You run and scale the gateway; if it breaks, nothing gets in | Nothing extra to run in the cluster |

### Caveats about "only passes traffic through"

- An NLB **can** terminate TLS if you attach a certificate. It still won't route by host or path.
- An NLB still does real work: health checks, spreading load, preserving the client's source IP.
- You *can* put an ALB in front of an in-cluster gateway, but that's two Layer 7 routers in a row. Only worth it if you want the ALB for WAF and the gateway for everything else.

**In one line:** an NLB forwards connections, an ALB routes requests.

## Part 2: The five-tool combo, is it more versatile?

A stack that comes up a lot:

| Layer | Tool |
|---|---|
| Pod networking | Cilium |
| Front door | HAProxy |
| Routing rules | Gateway API |
| Who makes the rules real | Traefik |
| Service-to-service | Istio |

Is it more versatile? Partly. The core idea is right: HAProxy can replace the NLB as a "dumb pipe" front door, and the routing rules still live in the cluster. That's a real, common pattern, especially on bare metal and in homelabs.

But this exact combo isn't really *more versatile*. It's *more pieces*. Several of these tools can do each other's jobs, so you'd be running overlapping software.

### What's good about it

- **HAProxy as the front door works.** Run it in **TCP mode** (Layer 4), and it behaves like an NLB: it forwards connections on 80/443 to Traefik without reading the HTTP. Turn on the **PROXY protocol** on both HAProxy and Traefik, or every request will look like it came from HAProxy's IP instead of the real user.
- **Routing stays in the cluster.** Your `Gateway` and `HTTPRoute` YAML is the source of truth, and Traefik turns it into real routing.
- **Gateway API at both levels.** Traefik uses it for traffic coming *into* the cluster, and Istio can use the same `HTTPRoute` objects for traffic *between* services. That gives you one rule language for both.

### Where it overlaps

Traefik is the most "extra" piece: both Cilium and Istio can implement Gateway API themselves, so it adds one more proxy to run, upgrade, and debug.

| Job | Your pick | Who else in the stack can already do it |
|---|---|---|
| Pod networking | Cilium | — |
| Front door / external IP | HAProxy | Cilium (LB-IPAM + BGP or L2 announcements) |
| Gateway API implementation | Traefik | Cilium, Istio |
| Service-to-service (mTLS, retries) | Istio | Cilium (partly, via its mutual auth and Envoy features) |

### Things that will bite you

1. **Traefik has to join the Istio mesh.** If Istio enforces strict mTLS, Traefik can't talk to your services unless it's in the mesh too. That means a sidecar in the Traefik pod, or enrolling its namespace in Istio ambient mode.
2. **Cilium and Istio need tuning to coexist.** It works, but Cilium's socket-level load balancing can bypass Istio's sidecars unless you configure it for that. It's a known setting in Cilium's Istio docs, but easy to miss.
3. **Only one Gateway API controller should own each Gateway.** If Cilium's Gateway API support is also switched on, keep it off or make sure the GatewayClass names are clearly separate.
4. **HAProxy itself needs high availability.** One HAProxy box is a single point of failure. On bare metal, run two with keepalived and a floating IP. On AWS, floating IPs don't work the same way, which is exactly the problem a managed NLB solves for you, so replacing the NLB there usually isn't worth it.

### Leaner versions that keep the same idea

| Version | Stack | When to pick it |
|---|---|---|
| Cilium-heavy | Cilium for networking, external IPs (BGP or L2) and Gateway API; HAProxy in front only if you have a separate edge box | Fewest moving parts |
| Istio-heavy | Cilium for networking, HAProxy at the edge, Istio for both ingress gateway and mesh; drop Traefik | One proxy family, Gateway API rules everywhere |
| No mesh | Cilium, HAProxy, Traefik | You don't need mTLS or traffic policies between services yet |

### Bottom line on the combo

The architecture idea is solid: a dumb front door, with smart routing inside the cluster. The specific tool list just has redundancy.

If your goal is *learning* each tool, the full combo is a fine lab, since you'll learn a lot from making them cooperate. If your goal is something you'd *run*, pick one of the leaner versions.

## Part 3: What if Cilium did every layer?

Mostly a good idea. Cilium for networking, external IPs, Gateway API, network policy and observability (Hubble) means one tool, one Helm chart, one upgrade and one set of docs instead of four or five. It's very well proven: the 2025 annual Cilium report found over 60% of surveyed production deployments on Cilium, and more than 75% on Cilium-based data planes once managed services like Azure CNI powered by Cilium and GKE Dataplane V2 are counted ([InfoQ](https://www.infoq.com/news/2026/02/cilium-119)).

Three corrections matter:

1. **Cloud independence comes mainly from Gateway API, not from Cilium.** `Gateway` and `HTTPRoute` YAML is a Kubernetes standard, so it would work on Traefik or Istio too. The front door (the public IP) is never portable:
   - Bare metal / homelab: Cilium announces the IP itself (BGP or L2). No extra tool.
   - AWS: Cilium can't create a public IP. Its Gateway creates a `LoadBalancer` Service and AWS still puts an NLB in front.
   - The CNI install itself also has cloud-specific settings, such as ENI mode on EKS.
2. **"Does everything" isn't "best at everything."** Cilium is excellent at networking, policy and ingress. Its service mesh is thinner than Istio's: in the 1.19 release, maintainers disabled the existing mutual authentication feature by default and pointed mTLS users toward a ztunnel-based path ([InfoQ](https://www.infoq.com/news/2026/02/cilium-119)). For strict service identity or advanced traffic shifting, Istio (ambient mode) is still stronger, and it runs alongside Cilium.
3. **One tool means one blast radius.** If the Cilium agent misbehaves or an upgrade goes wrong, pod networking, ingress, policy and mesh fail *together*. With separate tools, a broken Traefik upgrade only breaks ingress. Manage it with careful upgrades, a staging cluster, and knowing Hubble well.

**Takeaway:** "Cilium for everything except the mesh" is the best default today. Add Istio ambient only when a concrete need appears.

## Part 4: Best of both worlds, Cilium first

The rule: **Cilium is the default at every layer; another tool comes in only when a specific requirement shows up that Cilium doesn't handle well.**

| Layer | Default | Bring in something else when… | …and use |
|---|---|---|---|
| Pod networking + kube-proxy replacement | **Cilium** | basically never | — |
| Network policy (L3/L4, L7 HTTP/DNS rules) | **Cilium** | — | — |
| Traffic observability | **Cilium Hubble** | you need app metrics/traces, not just traffic | Prometheus + Grafana, OpenTelemetry |
| Node-to-node encryption | **Cilium WireGuard** | — | — |
| Multi-cluster networking | **Cilium Cluster Mesh** | — | — |
| External IP (bare metal / homelab) | **Cilium LB-IPAM + BGP or L2** | a separate edge box outside the cluster, or several clusters behind one IP | HAProxy (TCP mode) + keepalived |
| External IP (cloud) | cloud NLB (AWS Load Balancer Controller) | you need WAF or AWS-native login at the edge | ALB, or a WAF in front of the NLB |
| Ingress routing (Gateway API) | **Cilium Gateway** | you need rate limiting, OIDC/JWT login, request auth, rich middleware | Envoy Gateway or Traefik |
| Service-to-service mTLS + traffic shifting | nothing at first | strict per-service identity, % or header canaries between services, per-service retries/timeouts | Istio **ambient** mode |

Every setup also needs, whatever the networking stack: **cert-manager** for TLS certificates (Let's Encrypt) and **ExternalDNS** to create DNS records from your Gateways.

### The two most likely swaps, and why

1. **Cilium Gateway → Envoy Gateway or Traefik.** Cilium's gateway handles standard Gateway API routing well: hosts, paths, headers, gRPC, TLS. The extras that live *on top of* the standard, like "log users in with Keycloak before they reach the app" or "100 requests/minute per IP", are where dedicated gateways are much stronger.
2. **Adding Istio ambient.** Cilium already encrypts traffic between nodes. Istio adds *identity* ("only the cart service may call the payment service, proven by certificate") and fine-grained traffic control between services. Ambient mode coexists cleanly with Cilium and doesn't put a sidecar in every pod.

Everything else stays Cilium: a low tool count, and each extra tool arrives with a named reason attached.

### What it looks like in practice

```text
Homelab / bare metal
  [Cilium LB-IPAM]      ──► [Cilium Gateway]     ──► Services
  BGP or L2 from router     Gateway API routing      pods on Cilium networking

AWS (EKS)
  AWS NLB               ──► [Cilium Gateway]     ──► Services
  via AWS LB Controller     Gateway API routing      pods on Cilium networking

Grown-up: real requirements showed up
  NLB or HAProxy        ──► Envoy Gateway        ──► Services
  plain TCP pass-through    Gateway API routing      pods on Cilium networking
  (HAProxy only with        + OIDC login,            + Istio ambient (mTLS)
   an edge box)               rate limits

  ┌──────────────────────────────────────────────────────────────────────┐
  │ [Cilium] underneath all three: pod networking, network policy,       │
  │          Hubble, WireGuard                                           │
  └──────────────────────────────────────────────────────────────────────┘
  Also in all three: cert-manager (TLS certificates) and ExternalDNS (DNS records)

[ brackets ] = Cilium
```

The homelab and AWS setups differ only at the front door; the grown-up version swaps in Envoy Gateway and adds Istio ambient once a named need appears, while Cilium stays underneath.

## Bonus: things only an NLB can do

The flip side of "an ALB routes requests" is that some jobs need the plain connection-forwarder:

| Only with an NLB | Why an ALB can't |
|---|---|
| **Static IPs** (one fixed or Elastic IP per AZ) | An ALB's IPs change. You'd need an NLB or Global Accelerator in front of it. |
| **Non-HTTP traffic** (raw TCP, UDP: databases, MQTT, game servers, DNS) | An ALB only understands HTTP and HTTPS. |
| **PrivateLink** (sharing your service privately with another VPC or account) | An endpoint service has to sit on an NLB (or a Gateway Load Balancer). |
| **TLS passthrough** (the encrypted connection goes untouched to the pod) | An ALB always decrypts. |

## Sources

- [Cilium at Ten Years: Stronger Encryption, Safer Policies, and Clearer Visibility for Large Clusters (InfoQ, Feb 2026)](https://www.infoq.com/news/2026/02/cilium-119)
