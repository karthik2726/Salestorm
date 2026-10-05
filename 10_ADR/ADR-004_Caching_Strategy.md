# ADR-004: Multi-Tier Caching & Edge Invalidation Strategy

* **Status:** Accepted
* **Context:** Offloading ingress traffic during flash sales to shield core microservices and databases.
* **Options Considered:**
  1. *Centralized DB Caching Only:* Low resilience to traffic spikes.
  2. *Multi-Tier Edge & Memory Caching [CHOSEN]:* Cloudflare Edge CDN for static pages + Edge KV `SOLD_OUT` flag; Redis Cluster for rate limits, active stock counters, and idempotency keys.
* **Decision:** Implemented Multi-Tier Edge Caching. Redis stock depletion events set Cloudflare KV flag `SOLD_OUT = true`.
* **Consequences & Trade-offs:** Edge KV propagation takes ~100-200ms; shields core infrastructure by shedding 98% of post-depletion buyer traffic at the edge.
