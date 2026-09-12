---
title: Comparison
layout: default
nav_order: 6
permalink: /comparison/
description: >-
  Latency, cost shape, and decision guidance for PrivateLink versus inspected
  Transit Gateway — with lab charts from a live side-by-side run.
---

<div class="conduit-hero">
  <p class="conduit-kicker">after measure</p>
  <h1>Comparison</h1>
  <p class="conduit-lede">
    Same stream, same subscriber, two paths. Charts and tables below are from a
    live <a href="{{ site.baseurl }}/measure/">Measure</a> run in
    <code>ap-southeast-6</code>.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/teardown/">Next: Teardown</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/measure/">Back: Measure</a>
  </div>
</div>

## Two paths, one stream

{% include diagram.html file="diagrams/two-paths.svg" alt="PrivateLink versus TGW with inspection to the same relay" %}
<p class="diagram-caption">Teal = PrivateLink (consumer ENI → provider NLB). Amber = TGW hairpin through Network Firewall. Same <code>relay.py</code>, same TCP 9000.</p>

| | PrivateLink | TGW + inspection |
| --- | --- | --- |
| TCP peer from the subscriber | Interface ENI in the **consumer** VPC | Relay private IP in the **provider** VPC |
| Hops on the data path | Endpoint → PrivateLink → NLB → relay | Spoke → TGW → NFW → TGW → relay |
| Hub dependency | None for the data path | TGW + inspection VPC + stateful PASS |
| Shared CIDR required? | No | Yes (routable spoke CIDRs) |

{: .finding }
> PrivateLink wins on **in-path RTT** because the subscriber’s peer is local.
> TGW pays for **two Transit Gateway crossings** and a stateful firewall. At
> firehose rates both paths still deliver the **same** upstream bytes — latency
> diverges; throughput does not.

---

## Lab run (`ap-southeast-6`)

One 60 s `capture-series.py` run per path, started together from the same consumer
host, then a warm `sub.py` summary and `nping` probes ([Measure]({{ site.baseurl }}/measure/)).
Both sockets sit on the same relay process, so they receive the identical broadcast —
that is why the rates match rather than merely being close.

| Signal | How it is measured |
| --- | --- |
| In-stream RTT | `PING <seq>` / `PONG <seq>` on the **established** stream socket, one per second, timed on the consumer clock only |
| Series RTT point | Median of that second's samples — with one PING per second, effectively a single sample |
| `connect` | `socket.create_connection`, so it includes DNS resolution and interpreter overhead |
| `first_byte` | Measured from the **start of connect**, not from connect completion |
| Sustained rate | Stream bytes over the run window, KiB/s |
| `nping` | SYN → SYN/ACK handshake timing, 20 probes, no stream content |

{: .note }
> Single run, one Region, one AZ pair, ~60 RTT samples per path — so p95 carries real
> uncertainty and the ratios are directional, not a benchmark. `connect` and `nping`
> disagree by a couple of milliseconds because they measure different things (see the
> table above); the ratio between paths is what to read.

{% include diagram.html file="diagrams/comparison-summary.svg" alt="Summary bars for RTT, nping, and sustained rate" %}
<p class="diagram-caption">~2.5× in-stream RTT on TGW, ~1.6× on <code>nping</code> handshake probes, nearly identical KiB/s.</p>

### Side-by-side RTT

{% include diagram.html file="diagrams/comparison-rtt.svg" alt="Line chart of in-stream RTT over 60 seconds for both paths" %}
<p class="diagram-caption">One <code>PING</code>/<code>PONG</code> sample per second on the established stream. PrivateLink ~0.4 ms; TGW ~1.1 ms.</p>

### Side-by-side rate

{% include diagram.html file="diagrams/comparison-rate.svg" alt="Line chart of sustained KiB/s over 60 seconds for both paths" %}
<p class="diagram-caption">Same Wikimedia firehose through one relay — rates overlap; path tax is delay, not bandwidth.</p>

### Results

| Signal | PrivateLink | TGW + inspection | Insight |
| --- | --- | --- | --- |
| In-stream RTT p50 / p95 (60 s) | **0.43 / 0.71 ms** | **1.07 / 1.31 ms** | ~2.5× p50 — hairpin + NFW |
| Mean series RTT | 0.45 ms | 1.09 ms | Gap holds for the full minute |
| Sustained rate (60 s) | **55.1 KiB/s** | **55.1 KiB/s** | Same upstream |
| Warm `connect` / `first_byte` | 2.7 / 3.4 ms | 3.4 / 4.5 ms | Handshake same order |
| `nping` TCP avg (20 probes) | **0.66 ms** | **1.07 ms** | ~1.6× |

{: .finding }
> The durable signal is **in-stream RTT**, not warm connect. Both handshakes
> land in a few milliseconds; the hairpin shows up on the established flow.

---

## Why the gap exists

| Factor | PrivateLink | TGW + inspection |
| --- | --- | --- |
| Peer location | ENI next to the subscriber | Relay IP across accounts |
| Path structure | Endpoint ENI → PrivateLink → NLB | Two TGW attachment crossings (hairpin) |
| Middlebox | None on the data path | Network Firewall stateful inspection |
| Failure mode | Endpoint / NLB / SG | Route without hub **PASS** → handshake completes, then the stream stalls (`drop_established` default) |

### Streaming differences

| Topic | PrivateLink | TGW + inspection |
| ----- | ----------- | ---------------- |
| Idle timeout | NLB TCP idle (default **350 s**, **60–6000 s** configurable) | Firewall / TGW flow idle timeouts |
| Client attribution | NLB node address; Proxy Protocol v2 adds the consumer address **and** endpoint ID | Real consumer private IP at the relay |
| Flow stickiness | Endpoint / NLB AZ affinity | Appliance mode pins both directions to one firewall endpoint |
| Access model | Allowed principals on the endpoint service | Routes + SGs + hub firewall PASS |
| Overlapping CIDRs | Supported | Not supported without NAT |

---

## Cost shape

On-Demand list prices for **`ap-southeast-6`** (Asia Pacific — New Zealand), from the
AWS Price List API in September 2026. Re-check before you quote them
([PrivateLink](https://aws.amazon.com/privatelink/pricing/),
[Transit Gateway](https://aws.amazon.com/transit-gateway/pricing/),
[Network Firewall](https://aws.amazon.com/network-firewall/pricing/),
[ELB](https://aws.amazon.com/elasticloadbalancing/pricing/)).

| Meter | PrivateLink | TGW + inspection |
| --- | --- | --- |
| Fixed (hourly) | Interface endpoint **$0.01365/hr per AZ** + NLB **$0.02646/hr** (+ NLCU) | TGW VPC attachment **$0.07/hr** + Network Firewall **$0.705/hr** first endpoint, **$0.282/hr** each secondary AZ endpoint |
| Data processing | VPC endpoint **$0.01/GB** (0–1 PB) | TGW **$0.02/GB** on every pass into the gateway + NFW **$0.065/GB** |

The hairpin sends the stream into the TGW twice — spoke → inspection, then
inspection → provider — so **~$0.04/GB** TGW + **$0.065/GB** NFW ≈ **$0.105/GB**.

| Path | New for this lab | Already running in the hub |
| --- | --- | --- |
| **PrivateLink** | Endpoint hours + NLB hours + endpoint GB | — |
| **TGW + inspection** | Data processing only | Attachment hours + firewall endpoint hours |

New PrivateLink fixed cost is two AZ endpoints plus one NLB; the crossover is that
fixed bill divided by the per-GB gap:

```text
privatelink_fixed_monthly = (2 × 0.01365 + 0.02646) × 730  ≈ $39
break_even_GB_per_month   = 39 / (0.105 − 0.01)            ≈ 410 GB
```
{: .formula }

Both lines exclude NLB capacity units. NLCUs bill at **$0.0063/NLCU-hour** here and
bandwidth converts at roughly 1 GB/hour per NLCU, so if the bandwidth dimension
binds, PrivateLink costs nearer **$0.016/GB** and the crossover moves to about
**440 GB/month**. Treat 410 GB as the floor.

| Volume posture | Likely outcome | Why |
| --- | --- | --- |
| Lab / low continuous KiB/s | Hub cheaper **if already sunk** | New PrivateLink fixed hours (endpoint + NLB) dominate; per-GB barely matters |
| High sustained GB through one service | PrivateLink often cheaper | ~$0.01–0.016/GB vs ~$0.105/GB hairpin+NFW once volume clears the ~410–440 GB break-even |
| Many ports / whole CIDR estate | Hub (capability, not per-GB) | TGW+NFW per-GB stays **higher**; PrivateLink does not replace L3 estate access without **many** endpoint services (+ NLB each) |

---

## When each wins

{% include diagram.html file="diagrams/measure-side-by-side.svg" alt="Same consumer host targeting PL DNS and relay private IP" %}
<p class="diagram-caption">The run behind the numbers: one subscriber host, two targets. The decision is which peer the subscriber talks to — an endpoint you publish, or an address you route to.</p>

| Choose | When |
| ------ | ---- |
| **PrivateLink** | One (or a few) services; client-initiated; IAM **principals** instead of CIDR routes; lower latency; overlapping CIDRs OK |
| **TGW + inspection** | Many hosts/ports or bidirectional estate access; mandatory east–west inspection; hub already exists below the PrivateLink break-even |

---

## Decision

**Service product with a clear consumer boundary → PrivateLink. Network platform
with mandatory inspection → stay on the hub and pay the hairpin.**

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/teardown/">
    <strong>Teardown</strong>
    <span>Delete harness resources</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/measure/">
    <strong>Measure</strong>
    <span>Re-run interactive compare</span>
  </a>
</div>
