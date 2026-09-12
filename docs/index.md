---
title: Overview
layout: default
nav_order: 1
description: >-
  Compare PrivateLink and inspected Transit Gateway for a cross-account live
  stream - latency, cost, and when each path wins.
---

<div class="conduit-hero">
  <p class="conduit-kicker">jajera / pl-vs-inspected-tgw</p>
  <h1>PrivateLink vs inspected TGW</h1>
  <p class="conduit-lede">
    Same live stream across accounts — PrivateLink one way, Transit Gateway
    through your inspection hub the other. Stand it up, measure both, keep the
    path that fits.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/setup/prep/">Setup the harness</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/comparison/">Read the comparison</a>
  </div>
</div>

## Two paths, one stream

{% include diagram.html file="diagrams/two-paths.svg" alt="Two paths to one stream: PrivateLink versus TGW with inspection" %}
<p class="diagram-caption">Teal = PrivateLink (consumer + provider). Amber = TGW hairpin (consumer + network hub + provider). Same relay, same TCP 9000. Icons from <a href="https://aws-icons.johna.kiwi/">aws-icons</a>.</p>

<div class="path-grid">
  <a class="path-card" href="{{ site.baseurl }}/architecture/#path-a">
    <span class="path-card__label">PrivateLink</span>
    <strong>Endpoint -> NLB -> relay</strong>
    <span class="path-card__meta">harness adds this</span>
  </a>
  <a class="path-card" href="{{ site.baseurl }}/architecture/#path-b">
    <span class="path-card__label">TGW + inspection</span>
    <strong>Hairpin via firewall</strong>
    <span class="path-card__meta">existing hub</span>
  </a>
  <a class="path-card" href="{{ site.baseurl }}/comparison/">
    <span class="path-card__label path-card__label--warn">Decision</span>
    <strong>Latency / cost / when each wins</strong>
    <span class="path-card__meta">measure first</span>
  </a>
</div>

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/architecture/">
    <strong>1. Architecture</strong>
    <span>Diagram + what the harness adds</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/prerequisites/">
    <strong>2. Prerequisites</strong>
    <span>Hub + profiles</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/setup/prep/">
    <strong>3. Setup</strong>
    <span>Prep · provider · consumer</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/measure/">
    <strong>4. Measure</strong>
    <span>PrivateLink and TGW (interactive)</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/comparison/">
    <strong>5. Comparison</strong>
    <span>Latency, cost, decision</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/teardown/">
    <strong>6. Teardown</strong>
    <span>Delete harness resources</span>
  </a>
</div>

{: .cost }
> Billable while the harness is up: NLB, interface endpoint, and EC2 for relay and
> subscriber. Tear down when finished - the shared hub stays.
