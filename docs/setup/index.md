---
title: Setup
layout: default
nav_order: 4
has_children: true
permalink: /setup/
description: >-
  Prep the laptop, stand up the provider relay and PrivateLink service, then
  wire the consumer endpoint. Shared TGW and inspection stay untouched.
---

<div class="conduit-hero">
  <p class="conduit-kicker">harness only</p>
  <h1>Setup</h1>
  <p class="conduit-lede">
    Three passes: prep on the laptop, provider account work, then consumer.
    Leave the hub alone. Measuring both paths is a separate page after setup.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/setup/prep/">Start with Prep</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/prerequisites/">Prerequisites</a>
  </div>
</div>

{: .cost }
> Billable while up: NLB, interface endpoint (per AZ), data processing. Tear
> down when finished — the hub stays.

{: .note }
> Every code block is labelled. **run** is your laptop, **run on the host** is
> inside the SSM session, and **expected output** is what you should see — that
> one is not something to paste.

## Sections

<div class="path-grid">
  <a class="path-card" href="{{ site.baseurl }}/setup/prep/">
    <span class="path-card__label">1</span>
    <strong>Prep</strong>
    <span class="path-card__meta">Clone · profiles</span>
  </a>
  <a class="path-card" href="{{ site.baseurl }}/setup/provider/">
    <span class="path-card__label">2</span>
    <strong>Provider</strong>
    <span class="path-card__meta">relay.py · EC2 · NLB · endpoint service</span>
  </a>
  <a class="path-card" href="{{ site.baseurl }}/setup/consumer/">
    <span class="path-card__label">3</span>
    <strong>Consumer</strong>
    <span class="path-card__meta">EC2 · VPCE · measure tools</span>
  </a>
</div>

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/setup/prep/">
    <strong>Prep</strong>
    <span>Clone the repo</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/measure/">
    <strong>Measure</strong>
    <span>PrivateLink and TGW (interactive)</span>
  </a>
</div>
