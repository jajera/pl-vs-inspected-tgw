---
title: Measure
layout: default
nav_order: 5
permalink: /measure/
description: >-
  Interactively compare PrivateLink and the TGW path on the consumer host with
  tmux, nc, pv, ss, and nping. Optional sub.py for a one-line metrics summary.
---

<div class="conduit-hero">
  <p class="conduit-kicker">after setup</p>
  <h1>Measure</h1>
  <p class="conduit-lede">
    Open both paths side by side on the consumer host. Watch the live stream and
    bitrate, then check kernel TCP stats and connect samples. Use
    <code>sub.py</code> only if you want a one-line summary for
    <a href="{{ site.baseurl }}/comparison/">Comparison</a>.
  </p>
  <div class="conduit-actions">
    <a class="conduit-btn conduit-btn--primary" href="{{ site.baseurl }}/comparison/">Next: Comparison</a>
    <a class="conduit-btn conduit-btn--ghost" href="{{ site.baseurl }}/setup/consumer/">Back: Consumer</a>
  </div>
</div>

## Before you start

| Variable | From |
| --- | --- |
| `$PL_DNS` | [Consumer]({{ site.baseurl }}/setup/consumer/) interface endpoint |
| `$RELAY_PRIVATE_IP` | [Provider]({{ site.baseurl }}/setup/provider/) relay |

SSM into the consumer instance (`AWS_PROFILE=consumer`). Measure tools
(`tmux`, `nc`, `nping`, `pv`) were installed on [Consumer]({{ site.baseurl }}/setup/consumer/).

### Hub allow (TGW path only)

Confirm the consumer **private** route table has a TGW route toward the provider
spoke CIDR. Also confirm the hub Network Firewall already allows **consumer →
provider TCP 9000** (stateful PASS). Routing alone is not enough when the policy
defaults to `drop_established`. That allow is **hub work outside this harness** —
do not change firewall rules here. PrivateLink does not need it.

{% include diagram.html file="diagrams/hub-required.svg" alt="TGW hairpin through Network Firewall required for the inspected path" %}
<p class="diagram-caption">Amber path only: consumer → TGW → Network Firewall (PASS for TCP 9000) → TGW → relay. Outside this harness.</p>

## Side-by-side stream (primary)

Same subscriber host, two targets. Left pane = PrivateLink, right pane = TGW.

{% include diagram.html file="diagrams/measure-side-by-side.svg" alt="Same consumer host measuring PrivateLink DNS and relay private IP over TGW" %}
<p class="diagram-caption">Teal = <code>$PL_DNS</code> (PrivateLink). Amber = <code>$RELAY_PRIVATE_IP</code> (TGW + inspection). Same relay, two sockets.</p>

```bash
export PL_DNS=vpce-0eeee3333ffff4444-abcd1234.vpce-svc-0aaaa1111bbbb2222.ap-southeast-6.vpce.amazonaws.com
export RELAY_PRIVATE_IP=10.50.1.10

tmux new-session -d -s plvtgw -n compare
tmux split-window -h -t plvtgw:compare

# Left — PrivateLink
tmux send-keys -t plvtgw:compare.0 "nc -v \"\$PL_DNS\" 9000 | pv -brat" C-m

# Right — TGW + inspection
tmux send-keys -t plvtgw:compare.1 "nc -v \"\$RELAY_PRIVATE_IP\" 9000 | pv -brat" C-m

tmux attach -t plvtgw
```
{: .on-host }

**What to expect**

- Both panes scroll live Wikimedia JSON almost immediately.
- `pv -brat` shows a live bitrate (and totals) under each stream.
- PrivateLink often feels snappier; do not hard-code a winner — watch both.

Detach with `Ctrl-b` then `d`. Kill when finished: `tmux kill-session -t plvtgw`.

Manual alternative (no scripting): `tmux`, `Ctrl-b` `%` to split, run each
`nc … | pv -brat` yourself.

## Kernel TCP stats (second terminal)

While the streams are up, open another pane or SSH session and watch socket RTT /
retransmits:

```bash
watch -n1 "ss -ti '( dport = :9000 )'"
```
{: .on-host }

**Validate** — two established flows (PL ENI peer and relay private IP). Look at
`rtt:` / `retrans:` under each. Ctrl-C to stop `watch`.

```text
State  Recv-Q Send-Q Local Address:Port Peer Address:Port
ESTAB  0      0      10.60.3.20:54321   10.60.3.50:9000
         cubic wscale:7,7 rto:204 rtt:0.41/0.12 ato:40 mss:1448
ESTAB  0      0      10.60.3.20:54322   10.50.1.10:9000
         cubic wscale:7,7 rto:204 rtt:0.93/0.20 ato:40 mss:1448
```
{: .output }

## Connect samples (`nping`)

Repeated TCP connects (handshake timing), not stream content:

```bash
nping --tcp -p 9000 -c 20 --delay 0.5 "$PL_DNS"
nping --tcp -p 9000 -c 20 --delay 0.5 "$RELAY_PRIVATE_IP"
```
{: .on-host }

**Validate** — RTT max/avg printed per target. Run each twice; keep the second
(cold DNS/ARP/flow on the first).

```text
# PrivateLink (peer is the interface ENI in the consumer VPC)
Max rtt: 0.621ms | Min rtt: 0.357ms | Avg rtt: 0.415ms

# TGW + inspection (peer is the relay private IP)
Max rtt: 1.640ms | Min rtt: 0.823ms | Avg rtt: 0.934ms
```
{: .output }

Quick reachability only:

```bash
nc -vz "$PL_DNS" 9000
nc -vz "$RELAY_PRIVATE_IP" 9000
```
{: .on-host }

```text
Ncat: Connected to 10.60.3.50:9000.
Ncat: Connected to 10.50.1.10:9000.
```
{: .output }

## Optional: one-line metrics (`sub.py`)

Quiet until the window ends — use for a Comparison one-liner. Copy
`scripts/sub.py` to `/opt/plvtgw/sub.py` if it is not already there
([Consumer]({{ site.baseurl }}/setup/consumer/)).

```bash
python3 /opt/plvtgw/sub.py "$PL_DNS" 9000 120
python3 /opt/plvtgw/sub.py "$RELAY_PRIVATE_IP" 9000 120
```
{: .on-host }

**Validate** — one summary line per path after ~120s (run twice; keep the second):

```text
target=vpce-0eeee3333ffff4444-abcd1234.vpce-svc-0aaaa1111bbbb2222.ap-southeast-6.vpce.amazonaws.com:9000 connect=3.6ms first_byte=4.4ms msgs=4500 rate=50.9KiB/s rtt_p50=0.47ms rtt_p95=0.75ms rtt_p99=0.75ms
target=10.50.1.10:9000 connect=3.7ms first_byte=4.9ms msgs=4200 rate=47.7KiB/s rtt_p50=1.07ms rtt_p95=1.48ms rtt_p99=1.48ms
```
{: .output }

Laptop helper (same quiet run via SSM): `./scripts/compare.sh`.

### Optional: 60 s series for charts (`capture-series.py`)

Copy `scripts/capture-series.py` next to `sub.py`, then run both paths (parallel
is fine). Each command prints one JSON object with per-second RTT and rate
samples — the shape used on [Comparison]({{ site.baseurl }}/comparison/).

```bash
python3 /opt/plvtgw/capture-series.py "$PL_DNS" 9000 60 > /tmp/pl.json &
python3 /opt/plvtgw/capture-series.py "$RELAY_PRIVATE_IP" 9000 60 > /tmp/tgw.json &
wait
```
{: .on-host }

## Read next

<div class="nav-grid">
  <a class="nav-card" href="{{ site.baseurl }}/comparison/">
    <strong>Comparison</strong>
    <span>Latency, cost, when each path wins</span>
  </a>
  <a class="nav-card" href="{{ site.baseurl }}/teardown/">
    <strong>Teardown</strong>
    <span>Delete harness resources after you measure</span>
  </a>
</div>
