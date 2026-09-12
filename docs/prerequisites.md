---
title: Prerequisites
layout: default
nav_order: 3
permalink: /prerequisites/
description: >-
  Existing hub and spoke environment this comparison assumes, plus CLI profiles
  and tools for the demo harness.
---

<div class="conduit-hero">
  <p class="conduit-kicker">before you measure</p>
  <h1>Prerequisites</h1>
  <p class="conduit-lede">
    You need an existing Transit Gateway and inspection VPC. This lab only adds
    the stream harness on top.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/architecture/">See architecture</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/setup/prep/">Setup the harness</a>
  </div>
</div>

## Existing hub

{% include diagram.html file="diagrams/hub-required.svg" alt="Required hub environment with three accounts" %}
<p class="diagram-caption">Appliance mode on the inspection attachment. Allow consumer CIDR to provider TCP 9000. Icons from <a href="https://aws-icons.johna.kiwi/">aws-icons</a>.</p>

<div class="path-grid">
  <div class="path-card">
    <span class="path-card__label">TGW</span>
    <strong>Spoke attachments</strong>
    <span class="path-card__meta">two spokes attached</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Inspection</span>
    <strong>VPC + Network Firewall</strong>
    <span class="path-card__meta">hairpin route tables</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Sticky</span>
    <strong>Appliance mode</strong>
    <span class="path-card__meta">same firewall endpoint both ways</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">CIDRs</span>
    <strong>Non-overlapping spokes</strong>
    <span class="path-card__meta">two spoke accounts</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Spokes</span>
    <strong>VPC + private / private-lb</strong>
    <span class="path-card__meta">EC2 in private; NLB in private-lb</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Allow</span>
    <strong>Firewall policy</strong>
    <span class="path-card__meta">consumer → provider :9000 (hub; not this repo)</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Egress</span>
    <strong>NAT for live ingest</strong>
    <span class="path-card__meta">relay reaches Wikimedia</span>
  </div>
</div>

## Accounts and profiles

<div class="path-grid">
  <div class="path-card">
    <span class="path-card__label">Provider</span>
    <strong><code>shared-services</code></strong>
    <span class="path-card__meta">EC2 · relay · NLB · endpoint service</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Consumer</span>
    <strong><code>consumer</code></strong>
    <span class="path-card__meta">subscriber · interface EP</span>
  </div>
</div>

Walkthrough pages set the profile per step:

```bash
export AWS_PROFILE=shared-services   # provider
export AWS_PROFILE=consumer          # consumer
```

Optional script helpers use `PROVIDER_PROFILE` / `CONSUMER_PROFILE` (same defaults). The network hub is a prerequisite you already operate — no profile required for this harness.

## Toolchain

| Tool | Used for |
| ---- | -------- |
| AWS CLI v2 | `shared-services` and `consumer` profiles |
| Session Manager plugin | SSM into the spoke hosts |
| On consumer host | `tmux`, `nc` (`nmap-ncat`), `nping` (`nmap`), `pv` — install in [Consumer]({{ site.baseurl }}/setup/consumer/) |
| Python 3 | `relay.py` / optional `sub.py` (stdlib only) |
| `bash` | Optional helpers under `scripts/` |

Same Region for both paths. Cross-Region limits: [PrivateLink Conduit](https://privatelink-conduit.johna.kiwi/).

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/architecture/">
    <strong>Architecture</strong>
    <span>What the harness adds on top of this hub</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/setup/prep/">
    <strong>Setup</strong>
    <span>Prep · provider · consumer</span>
  </a>
</div>
