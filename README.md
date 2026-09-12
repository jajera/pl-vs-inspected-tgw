# pl-vs-inspected-tgw

Compare PrivateLink and inspected Transit Gateway for cross account stream latency and cost.

The shared hub (Transit Gateway, inspection VPC, Network Firewall) is a **prerequisite**.
This repo adds a thin harness — stream relay, PrivateLink endpoint, subscriber — and focuses
on **measurement and when each path wins**.

## Docs

| Page | Purpose |
| ---- | ------- |
| [Overview](docs/index.md) | Framing and reading order |
| [Prerequisites](docs/prerequisites.md) | Existing hub and profiles |
| [Architecture](docs/architecture.md) | Paths and what the harness adds |
| [Setup](docs/setup/) | Prep · provider · consumer |
| [Measure](docs/measure.md) | Interactive compare (`tmux` / `nc` / `pv` / `ss` / `nping`) |
| [Comparison](docs/comparison.md) | Latency, cost, decision |
| [Teardown](docs/teardown.md) | Delete harness resources |
| [References](docs/references.md) | Conduit, patterns walkthrough, AWS docs |

Published site: `https://pl-vs-inspected-tgw.johna.kiwi/`
(GitHub Pages custom domain; DNS via [`johna-kiwi-infra`](https://github.com/platformfuzz/johna-kiwi-infra) `sites.yaml`).

Local preview:

```bash
chmod +x scripts/docs-serve.sh
./scripts/docs-serve.sh
```

Brand assets (favicons, social card) are rasterised from
`docs/assets/images/icon.svg` and `docs/assets/images/og-image.svg`:

```bash
./scripts/build-brand.sh   # needs ImageMagick 7 with the rsvg delegate
```

## Harness scripts

| Script | Role |
| ------ | ---- |
| `scripts/relay.py` | Provider: live Wikimedia SSE fan-out on TCP `:9000` |
| `scripts/sub.py` | Optional: one-line connect / rate / RTT summary |
| `scripts/capture-series.py` | Optional: 60 s JSON RTT/rate series for Comparison charts |
| `scripts/setup-privatelink.sh` | Optional: NLB / endpoint service / interface VPCE only (hosts must already exist) |
| `scripts/teardown.sh` | Optional: delete harness AWS resources by state/tag |
| `scripts/compare.sh` | Optional SSM wrapper around `sub.py` on both paths |

```bash
# Follow docs/setup/ for the full walkthrough. Optional helpers:
./scripts/setup-privatelink.sh   # NLB + PrivateLink wiring only
./scripts/compare.sh
./scripts/teardown.sh
```

## Related

- [PrivateLink Conduit](https://privatelink-conduit.johna.kiwi/)
- [AWS Private Connectivity Patterns](https://aws-private-connectivity-patterns-walkthrough.johna.kiwi/)

## License

MIT — see [LICENSE](LICENSE).
