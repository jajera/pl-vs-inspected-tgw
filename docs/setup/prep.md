---
title: Prep
layout: default
parent: Setup
nav_order: 1
permalink: /setup/prep/
description: >-
  Clone the harness repo on your laptop.
---

<div class="conduit-hero">
  <p class="conduit-kicker">setup / 1</p>
  <h1>Prep</h1>
  <p class="conduit-lede">
    Clone the harness on your laptop. Provider and Consumer pages each say
    which CLI profile to use.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/setup/provider/">Next: Provider</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/setup/">Setup overview</a>
  </div>
</div>

## Clone

```bash
git clone https://github.com/jajera/pl-vs-inspected-tgw.git
cd pl-vs-inspected-tgw
```

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/setup/provider/">
    <strong>Provider</strong>
    <span>Profile shared-services · relay · NLB</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/prerequisites/">
    <strong>Prerequisites</strong>
    <span>Hub and profile checklist</span>
  </a>
</div>
