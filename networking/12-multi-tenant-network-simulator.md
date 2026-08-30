# 12 — Multi-Tenant Private Network Simulator

**Objective:** Model isolated environments mimicking enterprise network structures.

**Tech:** Linux network namespaces, iproute2, veth pairs.

## Key points

- **Network namespaces (netns) are the core primitive.** A netns is an isolated copy of
  the network stack — its own interfaces, routing table, iptables/nftables rules. This
  is literally the building block containers (Docker/Podman) use for network isolation.
  Understanding netns means understanding *how container networking actually works*.
- **veth pairs = virtual cables.** A `veth` is a pair of linked virtual interfaces:
  packets into one come out the other. You put one end in a namespace and the other in a
  bridge/router namespace to "wire them together". This is the mental model.
- **Routing tables per namespace.** Each netns has its own routes. "Two tenants share an
  uplink but can't see each other" = careful routing + no forwarding path between them.
- **`ip` (iproute2) is the modern tool.** `ip netns`, `ip link`, `ip addr`, `ip route` —
  understand you're manipulating kernel objects, not editing files.
- **Isolation must be *tested*, not assumed.** The deliverable is proving tenant A
  cannot reach tenant B (`ping` fails) while both reach the uplink (`ping` succeeds).
- **`net.ipv4.ip_forward`** controls whether the kernel routes between interfaces —
  central to making (or preventing) cross-namespace reachability.

## When to use it

- Learning container/VM networking from first principles.
- Prototyping network topologies (multi-tenant, DMZ) without hardware or clouds.
- Testing firewall/isolation rules safely on one machine.

## Scenario

You need to prove two customer environments on shared infrastructure can't snoop each
other's traffic. Instead of spinning up cloud VPCs, you build it with namespaces in
minutes: two tenant netns, a router netns with the uplink, veth cables between them.
You `ping` across and confirm isolation holds — a repeatable, free experiment.

## Where AI misleads

- **Forgetting `ip_forward` / the uplink path.** AI's setup often can't route at all, or
  routes *too much* (breaking isolation). You must verify both reachability *and*
  isolation explicitly.
- **Namespaces vanish on reboot.** AI presents them as permanent; manually-created netns
  are ephemeral. AI rarely mentions persistence.
- **veth peer confusion.** AI mixes up which end lives where, so nothing connects. Draw
  the topology yourself.
- **iptables vs nftables on Fedora.** Isolation rules differ; AI may use legacy iptables
  syntax that behaves unexpectedly under Fedora's nftables backend.
- **No verification step.** AI declares "isolated" without the ping/tcpdump tests that
  actually prove it. In networking, untested = unknown.
- **Cleanup.** AI leaves dangling namespaces/veths; know `ip netns del` to reset.
