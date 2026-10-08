---
title: "Kubernetes Networking, Explained Simply"
description: "ALB, NGINX, Traefik, Cilium, F5: most of them don't compete. Kubernetes networking is five jobs, and you pick one tool per job. Three real setups, from all-in on AWS to runs-anywhere."
crosspost:
  devto: full
  linkedin: summary
  tags: [kubernetes, networking, aws, devops]
  hashtags: [Kubernetes, DevOps]
  canonical_url: https://github.com/nazmur96/devops-learning-journal/blob/main/networking/kubernetes-networking-explained.md
  linkedin_image:
    path: img/k8s-networking-5-jobs.png
    alt: "Kubernetes networking is 5 jobs, not one tool fight. 1, Pod networking (CNI): AWS VPC CNI, Cilium, Calico, Flannel. 2, Front door load balancer: AWS ALB (L7), AWS NLB (L4), F5, HAProxy, MetalLB. 3, Routing rules: Gateway API or the older Ingress, which do nothing alone. 4, Rule follower: AWS Load Balancer Controller, NGINX, Traefik, Kong, Cilium. 5, Service mesh, optional: Istio, Linkerd, Cilium. Gateway API stays the same everywhere; swap the tool that follows it."
  summary: |
    Kubernetes networking looks like a turf war: ALB vs NGINX vs Traefik vs Cilium vs F5. Most of them aren't competing. They do different jobs. So the useful question isn't "which tool is best?" but "which job needs doing, and which tool does it?"

    There are five jobs. Pod networking (CNI) wires up every Pod. A front-door load balancer takes traffic from the internet. Routing rules say where traffic goes. A controller actually follows those rules. And an optional service mesh secures traffic between your own services. Pick one tool per job, and only for the jobs you need.

    The trap: Gateway API does nothing on its own. It's rules written down, and something like the AWS Load Balancer Controller, Cilium or Traefik makes them real. With the community ingress-nginx controller retired in March 2026, a lot of teams are moving to Gateway API right now.

    I built the same small shop three ways: all-in on AWS (VPC CNI + ALB), AWS outside with Cilium inside (NLB + Cilium), and runs-anywhere (HAProxy + Traefik + Istio). Gateway API stays identical in all three. The real choice is how much you hand to AWS versus run yourself.

    The full write-up draws all three setups, explains L4 vs L7 with a mail sorter, and shows where MetalLB fits. Link below.
---

![Kubernetes networking is 5 jobs, not one tool fight: Pod networking, front door, routing rules, rule follower, service mesh](https://raw.githubusercontent.com/nazmur96/devops-learning-journal/main/networking/img/k8s-networking-5-jobs.png)

## 0. Two words you need first

- **Pod:** a running copy of your app. Pods come and go, and their addresses change.
- **Service:** a stable name and address that always points to the right Pods, even when they change. Other parts of the system talk to the Service, not to Pods directly.

That's all the Kubernetes you need for the rest of this.

## 1. The big idea: sort tools by job, not by rivalry

When you see a list like ALB, NGINX, Traefik, Cilium, F5, it looks like they're all fighting each other. Most of them aren't. They do different jobs.

So don't ask "which tool is best?" Ask:

> "What job needs doing, and which tool will do it?"

## 2. The 5 networking jobs

Think of a Kubernetes cluster like an office building:

| # | Job | Simple question | Building analogy | Common tools |
|---|---|---|---|---|
| 1 | Pod networking (CNI) | How does each Pod get an address and talk to others? | Wiring and room numbers inside the building | AWS VPC CNI, Cilium, Calico, Flannel |
| 2 | External load balancer | Who receives traffic from the internet first? | The front door | AWS ALB, AWS NLB, F5, HAProxy |
| 3 | Routing rules (written) | How do I describe where traffic should go? | The sign on the wall: "Sales → 2nd floor" | Ingress (older), Gateway API (newer) |
| 4 | Routing implementation | Who actually follows those rules? | The receptionist who reads the sign and sends people the right way | AWS Load Balancer Controller, NGINX, Traefik, Kong, Cilium |
| 5 | Service-to-service control (mesh) | How do services inside talk to each other safely and reliably? | Internal security and hallway rules | Istio, Linkerd, Cilium |

CNI stands for Container Network Interface. It's just the name for "the plugin that gives Pods their networking."

**Important:** Job 3 is just rules written down. Gateway API does nothing on its own. It needs a tool from Job 4 to make the rules real.

You pick one tool per job, and only for the jobs you actually need. A service mesh (Job 5), for example, is optional.

### Why Gateway API instead of Ingress?

Both are ways to write routing rules. The difference:

- **Ingress** can only describe simple things, like "this URL goes to that Service." For anything fancier (splitting traffic 90/10, matching on headers), every tool invented its own custom add-ons, so your rules only worked with that one tool.
- **Gateway API** builds those features into the standard itself, so your rules work the same way no matter which tool follows them.

The popular community ingress-nginx controller was retired in March 2026, which is pushing many teams to switch to Gateway API now.

## 3. One key idea: "L4" vs "L7" front doors

You'll see these terms everywhere. They describe how much a load balancer looks at before passing traffic on.

| Type | What it does | Mail analogy | AWS example |
|---|---|---|---|
| L4 | Passes connections through without looking inside. Fast and simple. | A mail sorter that only reads the building address | NLB |
| L7 | Opens the request and reads it (the URL, headers, etc.), then decides where to send it. Smarter. | A mail sorter that also reads "Attention: Sales department" | ALB |

Keep this in mind. It explains why the projects below pick different front doors.

## 4. The example app

We'll build the same small online shop three different ways:

```text
frontend   →  the website
api        →  the backend logic
payment    →  handles payments
database   →  stores data
```

About the database: it isn't part of the incoming-traffic story. Internet users never reach it directly. Only the api and payment services talk to it. In AWS setups it often lives outside the cluster as a managed service (Amazon RDS). So in the pictures below, it sits at the very end.

## 5. Project 1: The "let AWS do it" setup

**Mindset:** "I use Kubernetes, but I want AWS to handle as much networking as possible."

Very common in AWS-heavy companies.

| Job | Tool |
|---|---|
| Pod networking | AWS VPC CNI |
| Front door | AWS ALB (L7) |
| Routing rules | Gateway API |
| Who makes the rules real | AWS Load Balancer Controller |
| Service-to-service | None yet (no mesh) |

```text
            INTERNET
                │
                ▼
            AWS ALB  ◄──── AWS Load Balancer Controller
                │          (reads your Gateway API rules
                │           and sets up the ALB to match)
                ▼
        ┌───────┴───────┐
        ▼               ▼
    frontend           api
                        │
                        ▼
                     payment
                        │
                        ▼
                    database
                 (Amazon RDS,
               outside the cluster)

Underneath: AWS VPC CNI gives every Pod a real IP from your AWS VPC
```

**How a request travels.** A user visits `https://shop.example.com/api`:

1. The request hits the AWS ALB.
2. Because the ALB is L7, it reads the URL and sees "/api goes to the api service."
3. The request reaches the api Pod.

**Worth knowing:** the AWS Load Balancer Controller is not in the path the traffic takes. It works behind the scenes: it reads your Gateway API rules and sets up the ALB to match them. The traffic itself goes ALB → Pod.

**When would you add a service mesh later?** When you start needing things like:

- encrypted traffic between your own services (called mTLS)
- automatic retries when a service briefly fails
- detailed numbers on how each service is talking to the others

Until then, skipping the mesh keeps things simpler.

**Why choose this setup:** less to install and maintain yourself, because AWS runs the hard parts. The downside is that you're tied to AWS.

## 6. Project 2: AWS outside, open-source inside

**Mindset:** "We use AWS for the cloud, but we want the Kubernetes networking to not depend on AWS."

| Job | Tool |
|---|---|
| Pod networking | Cilium |
| Front door | AWS NLB (L4) |
| Routing rules | Gateway API |
| Who makes the rules real | Cilium |
| Service-to-service | Cilium |

```text
            INTERNET
                │
                ▼
            AWS NLB        (L4: just passes traffic in)
                │
                ▼
             Cilium        (reads the URL and follows
                │           your Gateway API rules)
     ┌──────────┼──────────┐
     ▼          ▼          ▼
 frontend      api      payment
     └──────────┴──────────┘
                │
                ▼
            database

   Cilium also controls traffic and
   security between the services
```

Notice: one tool, Cilium, does many jobs at once:

- Pod networking (CNI)
- Network policy (who is allowed to talk to whom)
- Following your Gateway API rules
- Both simple (L4) and smart (L7) traffic handling

**Why the NLB instead of the ALB?** This is where L4 vs L7 matters. The NLB is a simple front door that just passes traffic through, and Cilium makes the smart routing decisions. If you used the ALB, it would do the routing itself, and that's exactly the AWS-specific part you're trying to avoid.

**Why choose this setup:** if you ever move off AWS, most of your Kubernetes networking (Cilium + Gateway API) comes with you. Only the NLB needs replacing.

## 7. Project 3: Mostly open-source, runs anywhere

**Mindset:** "The same platform has to run on AWS, Azure, our own servers, bare metal and private cloud."

| Job | Tool |
|---|---|
| Pod networking | Cilium |
| Front door | HAProxy |
| Routing rules | Gateway API |
| Who makes the rules real | Traefik |
| Service-to-service | Istio |

```text
            INTERNET
                │
                ▼
            HAProxy        OUTSIDE the cluster
                │          (stable front door)
   - - - - - - -│- - - - - - - - - - - - -
                ▼
            Traefik        INSIDE the cluster
                │          (follows your Gateway API rules)
     ┌──────────┼──────────┐
     ▼          ▼          ▼
 frontend      api      payment
     └──────────┴──────────┘
                │
                ▼
            database

   Istio controls traffic between services
   (encryption, retries, monitoring)

Underneath: Cilium gives every Pod networking
```

**Why two proxies in a row (HAProxy, then Traefik)?** They do different jobs:

- **HAProxy** sits outside the cluster. Its job is to be a stable front door with a fixed address. If a server inside the cluster dies, HAProxy just stops sending traffic there. It doesn't need to understand Kubernetes at all.
- **Traefik** sits inside the cluster. It understands Kubernetes, reads your Gateway API rules, and knows which Pods are running right now.

Think of HAProxy as the building's front door and Traefik as the receptionist inside.

**Why choose this setup:** almost nothing here is tied to a cloud provider, so the same design works everywhere.

**The cost:** you run and maintain everything yourself. There are more moving parts, more to learn and more that can break.

## 8. All three side by side

| Job | Project 1 (AWS-heavy) | Project 2 (mixed) | Project 3 (open-source) |
|---|---|---|---|
| Pod networking | AWS VPC CNI | Cilium | Cilium |
| Front door | AWS ALB (L7) | AWS NLB (L4) | HAProxy |
| Routing rules | Gateway API | Gateway API | Gateway API |
| Rule follower | AWS LB Controller | Cilium | Traefik |
| Service-to-service | None (yet) | Cilium | Istio |
| Tied to AWS? | A lot | A little | Barely |
| Effort to run | Lowest | Medium | Highest |

Notice: Gateway API stays the same in all three. That's its whole point. It's a standard way to write routing rules, and you can swap out the tool that follows them.

## 9. Where does MetalLB fit?

People sometimes call MetalLB "Kubernetes' version of HAProxy." That's not quite right.

**The problem it solves:** in Kubernetes, you can create a Service of `type: LoadBalancer`, which basically means "give me an address the outside world can reach."

- On AWS, Azure or GCP, the cloud automatically creates a load balancer and gives you that address.
- On bare metal or your own servers, nobody does this. The Service just sits there stuck on `<pending>` forever.

MetalLB fills that gap. It hands out outside-reachable addresses to your LoadBalancer Services, doing the job the cloud would normally do.

So a better way to think of it:

> MetalLB = "the cloud's load-balancer feature, for clusters that don't have a cloud."

**How it connects to Project 3:** when Project 3 runs on bare metal, something has to give the entry point a stable address. MetalLB is a common way to do that. It can be used alongside HAProxy, or in simpler setups it can replace the need for a separate outside proxy, giving Traefik its address directly.

In the 5-job list, MetalLB belongs to Job 2 (the front door), but only for clusters without a cloud provider.

## 10. One-sentence summary

Split networking into 5 jobs, pick one tool per job, and remember that the tools mostly work together rather than compete. How much you hand over to AWS versus run yourself is the real choice you're making.
