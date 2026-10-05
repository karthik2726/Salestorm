# ADR 003: Virtual Waiting Room for Ingress Admission Control

* **Status:** Accepted
* **Deciders:** Senior System Architecture Team
* **Date:** 2026-10-05

---

## Context and Problem Statement
During flash sales, peak ingress traffic can reach 500,000 req/sec. Passing uncontrolled traffic directly to core application microservices causes cascading CPU starvation, thread pool exhaustion, and service crashes. The system requires an admission control mechanism to smooth out traffic spikes and protect downstream services.

---

## Options Considered

1. **Option 1: Direct Gateway Load Shedding (HTTP 429 Drops)**
   * *Pros:* Zero queue state storage required.
   * *Cons:* Poor user experience; buyers are immediately rejected without a fair chance to purchase.
2. **Option 2: Edge Virtual Waiting Room (Token-Bucket Queue) [CHOSEN]**
   * *Pros:* Places excessive buyers into a virtual queue, admitting requests to the backend at a controlled rate (e.g., 100 req/sec). Guarantees smooth system load and fair FIFO ordering.
   * *Cons:* Requires clients to poll queue status endpoints every 2 seconds.

---

## Decision Outcome
**Chosen Option: Option 2 (Virtual Waiting Room).**

---

## Consequences & Trade-Offs
* **Positive:** Prevents core service degradation; controls resource contention cleanly.
* **Negative:** Adds user polling traffic to queue endpoints.
* **Mitigation:** Polling status responses are cached at CDN edge nodes for 1 second.
