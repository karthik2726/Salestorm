# 90-Second Flash Sale Execution Spoken Walkthrough Script

*Speaker Instructions: Deliver with confident, clear pacing. Target duration: 90 seconds (225 words).*

---

## The Spoken Script

"Here is exactly what happens when **10,000 buyers** click 'Buy Now' simultaneously for **100 units of Product X**:

At **t = 0.0 seconds**, 10,000 requests hit Cloudflare Edge. Cloudflare’s Virtual Waiting Room immediately intercepts traffic, holding 9,900 buyers in a rate-limited queue with HTTP 202 status, while admitting exactly **100 requests** to our core Inventory Service.

At **t = 0.2 seconds**, these 100 admitted requests execute our single-threaded **Redis Lua script**. Redis evaluates stock, verifies user purchasing limits, and decrements available stock from 100 down to **exactly zero** in under 1.5 milliseconds. All 100 buyers receive a 10-minute reservation token. 

Because stock is now zero, Redis emits an event setting Cloudflare’s Edge KV flag **`SOLD_OUT = true`**. All remaining 9,900 waiting buyers are immediately short-circuited at the edge with a static 'Sold Out' response, receiving zero load on our core databases.

Next, the 100 reservation holders hit our Payment Service. **95 payments succeed**, while **5 fail** due to card declines. The 5 failed payments immediately trigger an idempotent Lua release script, returning 5 units back to stock for queue backfill.

Finally, the 95 successful payments write `PaymentConfirmed` events to **Apache Kafka** using the **Transactional Outbox pattern**. Even if our Order Service suffers a 30-second container crash at this exact moment, Kafka retains all 95 events durably. When the Order Service recovers, it checks the `processed_event` table and idempotently creates **all 95 confirmed orders** with **zero double-charging**, **zero overselling**, and **zero data loss**. Thank you."
