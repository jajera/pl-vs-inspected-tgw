---
title: Architecture
layout: default
nav_order: 2
permalink: /architecture/
description: >-
  What already exists in the hub versus what the harness adds for PrivateLink
  and the stream relay.
---

<div class="conduit-hero">
  <p class="conduit-kicker">paths and harness</p>
  <h1>Architecture</h1>
  <p class="conduit-lede">
    Same relay, two ways in. This lab builds the PrivateLink path; the TGW
    inspection path already exists in your hub.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/prerequisites/">Prerequisites</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/setup/prep/">Setup the harness</a>
  </div>
</div>

## Two paths, one stream

{% include diagram.html file="diagrams/two-paths.svg" alt="Two paths to one stream: PrivateLink versus TGW with inspection" %}
<p class="diagram-caption">Teal = PrivateLink (consumer + provider). Amber = TGW hairpin (consumer + network hub + provider). Icons from <a href="https://aws-icons.johna.kiwi/">aws-icons</a>.</p>

<div class="path-grid">
  <div class="path-card" id="path-a">
    <span class="path-card__label">Path A</span>
    <strong>PrivateLink</strong>
    <span class="path-card__meta">EP → NLB → relay · harness adds this</span>
  </div>
  <div class="path-card" id="path-b">
    <span class="path-card__label">Path B</span>
    <strong>TGW + inspection</strong>
    <span class="path-card__meta">hairpin via NFW · existing hub</span>
  </div>
  <div class="path-card" id="path-c">
    <span class="path-card__label path-card__label--warn">Path C</span>
    <strong>TGW without inspection</strong>
    <span class="path-card__meta">diagram only · not measured live</span>
  </div>
</div>

**Path A** uses the endpoint service allowed-principals list (consumer account). No route between VPC CIDRs.

**Path B** targets the relay private IP. Same `relay.py` process as Path A.

**Path C** is the mental model for the hairpin tax (extra TGW hop + firewall). This lab does not re-associate spoke route tables during a run.

## What the harness adds

<div class="path-grid">
  <div class="path-card">
    <span class="path-card__label">Provider</span>
    <strong>Relay EC2 + <code>relay.py</code></strong>
    <span class="path-card__meta">ingest + fan-out on :9000</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Provider</span>
    <strong>NLB + endpoint service</strong>
    <span class="path-card__meta">allows consumer principal</span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Consumer</span>
    <strong>Interface endpoint</strong>
    <span class="path-card__meta">DNS name used by <code>sub.py</code></span>
  </div>
  <div class="path-card">
    <span class="path-card__label">Consumer</span>
    <strong><code>sub.py</code></strong>
    <span class="path-card__meta">subscribe · PING/PONG RTT · rate</span>
  </div>
</div>

## Naming

| Thing | Value |
| ----- | ----- |
| Resource prefix | `plvtgw-` |
| Tag | `demo=pl-vs-inspected-tgw` |
| Stream port | `9000` |

Use the tag for teardown discovery if state files are lost.

## Client IP

| Path | What the relay sees |
| ---- | ------------------- |
| TGW | Consumer host private IP |
| PrivateLink | NLB node address (unless Proxy Protocol v2 on the target group) |

Proxy Protocol matters for audit logging. Optional for the latency comparison.

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/prerequisites/">
    <strong>Prerequisites</strong>
    <span>Hub checklist and profiles</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/setup/prep/">
    <strong>Setup</strong>
    <span>Prep · provider · consumer</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/comparison/">
    <strong>Comparison</strong>
    <span>Latency, cost, decision</span>
  </a>
</div>
