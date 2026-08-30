# 13 — On-Prem Production Network Fabric (Proxmox + Kubernetes)

**Objective:** Build the *infrastructure networking* layer of a self-hosted platform the
way on-prem DevOps/SRE teams actually run it — routed subnets, segmentation, NAT,
BGP-advertised load balancing, and a hub-and-spoke fabric — growing from one Hetzner
dedicated server to several.

**Tech:** Proxmox VE (incl. SDN zones), VyOS or FRR, nftables, Linux routing/policy
routing, VLAN + VXLAN/EVPN, BGP, Cilium (BGP control plane + LB-IPAM), Talos Linux,
Hetzner vSwitch.

**Status:** Planned, gradual. Not a weekend build. Nothing implemented yet.

**Prerequisite:** project [12](./12-multi-tenant-network-simulator.md). Network
namespaces and `veth` pairs let you build this entire topology — public subnet, private
subnet, NAT router, hub-and-spoke — on the Fedora workstation, today, at zero cost and
zero risk. Every mistake is undone by deleting a namespace. Do that before spending
money on hardware; the routing concepts are identical and nothing is done for you.

**Related:** the platform stack itself is described in
`homelab-architecture-hetzner-dedicated-server.md` (Talos, Sidero Omni, Argo CD,
OpenBao, Envoy Gateway, observability). That document specifies *Kubernetes*
networking and stops there. This project covers the layer underneath it, which is the
part being learned here. Consider moving that document into this repo so it is
versioned alongside the roadmap.

---

## Key points

- **Underlay vs overlay.** The underlay is the routed network that moves packets
  between hosts. The overlay is the tenant network riding on top — VXLAN/Geneve
  encapsulation with a control plane distributing reachability (BGP EVPN in real
  fabrics, or the CNI's own control plane). Cloud VPCs are themselves overlays; that
  is why VXLAN is a closer analogue than VLAN.
- **A VRF is the on-prem equivalent of a VPC**, not a VLAN. A VLAN is layer-2
  tagging. A VRF is a separate routing table, so overlapping IP space can coexist
  with no leakage. Routing isolation is the actual primitive behind tenant isolation.
- **Layer 3 to the host is current practice.** Large flat layer-2 domains were
  abandoned for good reasons: broadcast overhead, STP convergence time, MAC table
  limits, and a failure blast radius covering the whole segment. Modern designs route
  to the rack or host and distribute reachability with BGP, using ECMP for multipath.
- **Load balancing on-prem is a routing problem.** With no cloud LB, service IPs are
  *advertised*. BGP (Cilium BGP control plane + LB-IPAM, or MetalLB BGP mode) gives
  route withdrawal on failure and ECMP across nodes. ARP/L2 announcement modes work
  but are the beginner path: one node answers, failover depends on ARP propagation,
  no multipath, and all nodes must share one L2 segment.
- **A mesh overlay VPN is not a fabric.** Tailscale/NetBird give flat L3 reachability
  with identity and ACLs. That is remote *access* (the Client VPN / Site-to-Site role),
  not the routed, segmented network being built here. Using a mesh as the fabric hides
  exactly the mechanics worth learning.
- **Failure domain** is the organising concept for everything below. Two things share a
  failure domain if one event can take out both — host reboot, kernel panic, disk
  failure, bad firewall push, power event. Virtualisation isolates software faults, not
  the host, NIC, disk, or power. This is why phase boundaries below are drawn at
  *physical machine* count, not at software features.
- **Separate networks by function**, as production Proxmox does: management, cluster
  heartbeat (corosync), storage, workload, and any DMZ. Corosync in particular is
  latency-sensitive — sharing it with congested storage traffic causes fencing and
  node reboots.
- **MTU is a first-class concern.** Every encapsulation layer costs bytes (VXLAN adds
  roughly 50). Mismatched MTU produces the classic silent failure: small packets and
  handshakes succeed, large transfers hang. Hetzner's vSwitch also requires a reduced
  MTU — verify the current value in their docs rather than assuming.

---

## Phased roadmap

Each phase is drawn where a new *physical* machine unlocks something that cannot be
learned honestly on fewer.

### Phase 1 — one server (virtualised topology)

Goal: learn routing, segmentation, NAT, firewall policy, and route advertisement.

- Proxmox VE on bare metal using a **routed** network setup: the host holds the public
  IP, VMs sit on private bridges, the host forwards and SNATs. Do **not** bridge VMs
  onto the public NIC (see Safety).
- A **router VM** (VyOS or FRR) acting as top-of-rack. Every VM network hangs off it,
  so routing, NAT, and firewall policy are things you configure rather than things
  Proxmox quietly does. VyOS is attractive because its config is declarative and
  diffable, which fits the GitOps discipline of the platform doc.
- **Proxmox SDN**, starting with a VLAN zone. Learn zones and vnets as concepts rather
  than hand-editing bridges.
- Segmentation into management / cluster / storage / workload zones, with explicit
  inter-zone firewall policy on the router.
- Talos: make all three nodes control-plane so etcd has genuine quorum mechanics to
  observe, even though the failure domain is shared.
- **Cilium BGP control plane + LB-IPAM**, peering to the router VM. Watch service
  prefixes appear, withdraw on drain, and load-share.
- Envoy Gateway, cert-manager (DNS-01), external-dns — all of which require the domain.

Honest limits at this phase: storage replication is an illusion (Longhorn replicas
across three VMs on one NVMe die together), "HA" is simulated, and hardware redundancy
(LACP bonding, dual ToR, MLAG) cannot be practised at all.

### Phase 2 — second server (real cluster, real failure domains)

- **Hetzner vSwitch** for a private VLAN between dedicated servers — the realistic
  private fabric between physical nodes. Account for the reduced MTU.
- Proxmox cluster across two nodes: a two-node cluster needs a **QDevice/witness** for
  quorum, otherwise split-brain. Corosync wants low latency and, ideally, two rings.
- Live migration, which forces a real conversation about shared or replicated storage.
- Spread Kubernetes control planes across hosts — the first genuine failure-domain
  separation.
- BGP between physical nodes rather than only VM-to-router-VM.

Learn: quorum, fencing, corosync ring design, migration, cross-host routing.

### Phase 3 — third server (quorum, distributed storage, real overlay)

- Three-node quorum makes Proxmox, etcd, and Ceph all meaningful at once (Ceph wants
  three nodes for replica 3).
- Ceph (Rook or Proxmox-managed) with separate public and cluster networks, and the
  MTU/jumbo-frame discussion that comes with it.
- **Proxmox SDN EVPN zone** — VXLAN with a BGP EVPN control plane, which is what
  enterprise data-centre fabrics actually run.
- ECMP/multipath and BFD for fast failure detection.
- Verify HA by pulling a node during a rolling upgrade, with drain, cordon, and PDBs.

### Cross-cutting, from the start

- **Access control plane placement.** Whatever grants access (NetBird's control plane,
  a bastion) must not live on the machine it protects. A separate small VPS, ideally a
  different provider or region. A VM on the same host does not count.
- **Break-glass path** that never traverses the overlay: Hetzner console and rescue
  system, verified *before* it is needed.
- **CIDR plan, written down.** Avoid `100.64.0.0/10` (Tailscale's CGNAT range) and
  Docker's `172.17.0.0/16` plus adjacent user-network ranges. Carve `10.x` deliberately,
  and document pod and service CIDRs alongside it.
- **Domain registration** is the blocking prerequisite: cert-manager DNS-01,
  external-dns, and self-hosted NetBird all need a public name.
- **Keep the agent-brain out of the lab.** It stays on its own cloud VPS; a platform you
  are deliberately breaking is not where a memory system lives.

---

## When to use it

- Any self-hosted or on-prem platform where there is no cloud provider supplying
  subnets, route tables, NAT gateways, or load balancers — you supply all of them.
- Preparing for on-prem/hybrid SRE work, where BGP, VRFs, quorum, and fabric design are
  daily concerns rather than abstractions behind an API.
- Understanding cloud networking more deeply by building the machinery it hides.

---

## Scenario

A service in the cluster needs a public address. In a cloud you request a load balancer
and move on. Here: LB-IPAM assigns an address from a pool you defined, Cilium
advertises that prefix over BGP to the router, the router installs it and redistributes
it, and traffic arrives. Then a node drains — the route is withdrawn, and traffic shifts
without a DNS change or an ARP timeout. Later a large transfer hangs while small
requests keep working, and the cause is 50 bytes of VXLAN overhead against an
unadjusted MTU. Every layer in that story is one you configured, which is why you can
debug it.

---

## Where AI misleads

- **Hetzner bridging advice is actively dangerous.** AI will confidently tell you to
  bridge VMs onto the public NIC and assign public IPs. Unregistered MAC addresses can
  trip Hetzner's abuse detection and get the server's switch port disabled — a support
  ticket, not a reboot. Use a routed setup.
- **L2 announcement presented as production load balancing.** MetalLB L2 mode and
  Cilium L2 announcements are the beginner path; AI recommends them as the on-prem
  answer, and the platform doc currently reflects that.
- **Flat VLAN designs described as modern.** This is roughly a decade out of date for
  data-centre practice.
- **`iptables` on an nftables system.** Fedora and modern Debian are nftables-backed and
  firewalld owns the ruleset; hand-written rules get wiped on reload. AI ignores this
  routinely.
- **`ip_forward` as the whole answer.** Forwarding also needs firewalld policy, and
  `rp_filter` will silently drop asymmetric return traffic while you debug the wrong
  layer.
- **VLAN conflated with VRF, and VRF conflated with VPC.** Ask which one provides
  routing isolation and the confusion surfaces immediately.
- **MTU ignored.** Encapsulation overhead is omitted from nearly every generated
  example.
- **Two-node clusters described as HA.** Without a QDevice that is a split-brain
  generator.
- **Replica counts presented as durability** when all replicas share one physical disk.
- **"Just use k3s."** Fine for convenience, but it hides the control-plane HA mechanics
  that are part of the point here.

---

## Safety / lock-yourself-out risks

- Building a router or firewall on the machine carrying your only SSH session ends that
  session the moment a default route changes or a `DROP` policy lands. Use a timed
  auto-rollback and verify console access first.
- Hetzner abuse detection on bridged setups with invented MACs (above).
- A BGP misconfiguration can blackhole management traffic as effectively as a firewall
  mistake.
- Corosync sharing a congested link causes fencing — nodes reboot themselves.

---

## Open decisions

1. Router platform: VyOS vs FRR on Debian vs OPNsense.
2. Proxmox SDN progression: how long to stay on a VLAN zone before EVPN.
3. Pod networking: native routing with BGP vs overlay encapsulation.
4. Storage at phase 3: stay on Longhorn or move to Rook/Ceph.
5. NetBird adoption timing, and which separate VPS hosts its control plane.
6. Domain registrar and DNS provider (the platform doc assumes Cloudflare).
