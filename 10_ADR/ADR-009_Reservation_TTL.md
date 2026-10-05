# ADR-009: Inventory Reservation Time-to-Live (10-Minute TTL Window)

* **Status:** Accepted
* **Context:** Defining the expiration window for temporary inventory reservations to prevent unpurchased items from being held indefinitely.
* **Options Considered:**
  1. *2-Minute TTL:* Too short; legitimate users fail checkout if payment gateway takes $>60\text{s}$ or requires 3D-Secure authentication.
  2. *30-Minute TTL:* Too long; locks up inventory for abandoning buyers, delaying stock availability for waiting customers.
  3. *10-Minute TTL [CHOSEN]:* Optimal window accommodating 3D-Secure payment authorization while ensuring fast stock recycling upon abandonment.
* **Decision:** Selected 10-Minute TTL (`TTL = 600s`).
* **Consequences & Trade-offs:** Sweeper job runs every 30s to replenish expired stock; provides fair balance between user experience and inventory velocity.
