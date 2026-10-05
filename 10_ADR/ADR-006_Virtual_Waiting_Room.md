# ADR-006: Virtual Waiting Room for Ingress Admission Control

* **Status:** Accepted
* **Context:** Controlling user admission during 500,000 req/sec flash sale traffic bursts to prevent microservice resource starvation.
* **Options Considered:**
  1. *Direct Gateway Throttling (HTTP 429 Drops):* Immediate rejection without fair queueing.
  2. *Virtual Waiting Room (Token-Bucket Queue) [CHOSEN]:* Admits users to backend at a controlled rate (100 req/sec), holding remaining users in a fair virtual queue.
* **Decision:** Selected Virtual Waiting Room.
* **Consequences & Trade-offs:** Requires client polling every 2 seconds; guarantees smooth microservice load and fair buyer experience.
