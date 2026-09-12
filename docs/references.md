---
title: References
layout: default
nav_order: 8
permalink: /references/
description: Related labs and AWS documentation for PrivateLink and Transit Gateway.
---

# References
{: .no_toc }

## Related labs

| Resource | Why |
| -------- | --- |
| [PrivateLink Conduit](https://privatelink-conduit.johna.kiwi/) | PrivateLink deep dive, DNS, client IP, Auckland cross-Region gap |
| [AWS Private Connectivity Patterns](https://aws-private-connectivity-patterns-walkthrough.johna.kiwi/) | Peering, PrivateLink, Lattice, TGW, Cloud WAN comparison |

## AWS documentation

- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
- [Interface endpoint services](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-share-your-services.html)
- [Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/what-is-transit-gateway.html)
- [Centralized inspection with Gateway Load Balancer / Network Firewall patterns](https://docs.aws.amazon.com/network-firewall/latest/developerguide/arch-igw-cwl.html)
- [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)
- [Transit Gateway pricing](https://aws.amazon.com/transit-gateway/pricing/)
- [Network Firewall pricing](https://aws.amazon.com/network-firewall/pricing/)

## Feed used by the harness

- [Wikimedia EventStreams](https://stream.wikimedia.org/) — public recent-changes SSE; no API key
- User-Agent in the relay identifies this lab; be a good citizen on the firehose
