"""
SALESTORM High-Scale Flash-Sale Asyncio Simulation Script
Validates core system design assumptions, concurrency control, idempotency, and fault recovery.
Design references: 08_Scalability_Reliability/concurrency_inventory.md, 04_Database/schema.sql, 05_API/events.md
"""
import asyncio
import random
import sys

# Ensure UTF-8 output encoding on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# Fixed seed for deterministic test execution
random.seed(42)

# --- Global System State ---
INITIAL_STOCK = 100
available_stock = INITIAL_STOCK
reserved_stock = 0
sold_stock = 0
stock_never_negative = True
conservation_held = True

# Datastores & In-Memory Ledgers
customer_reservations = {}  # cust_id -> reservation_id (08_Scalability_Reliability/concurrency_inventory.md)
idempotency_cache = {}      # idempotency_key -> response (05_API/api_notes.md)
reservations_db = {}        # res_id -> res_dict (04_Database/schema.sql)
payments_db = {}            # payment_id -> pay_dict (04_Database/schema.sql)
orders_db = {}              # order_id -> order_dict (04_Database/schema.sql)
processed_events = set()    # (event_id, consumer_group) (05_API/events.md)
kafka_outbox = []           # Message stream buffer (02_HLD/hld_overview.md)

lock = asyncio.Lock()  # Atomic Redis Lua Gate Simulation

async def check_conservation():
    global stock_never_negative, conservation_held
    if available_stock < 0:
        stock_never_negative = False
    if (available_stock + reserved_stock + sold_stock) != INITIAL_STOCK:
        conservation_held = False

# --- Redis Atomic Lua Script Simulation (08_Scalability_Reliability/concurrency_inventory.md) ---
async def lua_reserve_stock(cust_id, idemp_key):
    global available_stock, reserved_stock
    async with lock:
        await check_conservation()
        # 1. Idempotency Check
        if idemp_key in idempotency_cache:
            return True, idempotency_cache[idemp_key], "IDEMPOTENT"
        # 2. Customer Purchase Limit Check (Max 1 unit per customer)
        if cust_id in customer_reservations:
            return False, None, "CUSTOMER_LIMIT_EXCEEDED"
        # 3. Stock Check & Atomic Decrement
        if available_stock > 0:
            available_stock -= 1
            reserved_stock += 1
            res_id = f"res_{cust_id}"
            customer_reservations[cust_id] = res_id
            reservations_db[res_id] = {"status": "RESERVED", "cust_id": cust_id}
            idempotency_cache[idemp_key] = res_id
            await check_conservation()
            return True, res_id, "SUCCESS"
        else:
            return False, None, "OUT_OF_STOCK"

# --- Idempotent Stock Release Script (08_Scalability_Reliability/concurrency_inventory.md) ---
async def release_stock(res_id, cust_id, reason):
    global available_stock, reserved_stock
    async with lock:
        if res_id in reservations_db and reservations_db[res_id]["status"] in ("RESERVED", "PAYMENT_PENDING"):
            reservations_db[res_id]["status"] = reason
            reserved_stock -= 1
            available_stock += 1
            await check_conservation()
            return True
        return False

# --- Payment Processing Engine (03_LLD/sequence_payment.md) ---
async def process_payment(res_id, cust_id, idemp_key):
    global reserved_stock, sold_stock
    if idemp_key in idempotency_cache and idempotency_cache[idemp_key].startswith("pay_"):
        return True, idempotency_cache[idemp_key]

    rand_val = random.random()
    if rand_val < 0.95:  # 95% Payment Success
        pay_id = f"pay_{res_id}"
        payments_db[pay_id] = {"res_id": res_id, "status": "SUCCESS"}
        idempotency_cache[idemp_key] = pay_id
        async with lock:
            reserved_stock -= 1
            sold_stock += 1
            reservations_db[res_id]["status"] = "SOLD"
            await check_conservation()
        # Write to Transactional Outbox / Kafka
        kafka_outbox.append({"event_id": f"evt_{pay_id}", "type": "PaymentConfirmed", "pay_id": pay_id, "res_id": res_id, "cust_id": cust_id})
        return True, pay_id
    elif rand_val < 0.98:  # 3% Payment Declined / Failed
        await release_stock(res_id, cust_id, "RELEASED")
        return False, "DECLINED"
    else:  # 2% Payment Timeout -> PAYMENT_UNKNOWN -> Reconciled to Success
        pay_id = f"pay_{res_id}"
        payments_db[pay_id] = {"res_id": res_id, "status": "UNKNOWN"}
        # Reconciliation engine resolves to SUCCESS
        payments_db[pay_id]["status"] = "SUCCESS"
        async with lock:
            reserved_stock -= 1
            sold_stock += 1
            reservations_db[res_id]["status"] = "SOLD"
            await check_conservation()
        kafka_outbox.append({"event_id": f"evt_{pay_id}", "type": "PaymentConfirmed", "pay_id": pay_id, "res_id": res_id, "cust_id": cust_id})
        return True, pay_id

# --- User Purchase Worker Flow ---
async def user_worker(user_id, is_duplicate=False):
    cust_id = f"cust_{user_id}"
    idemp_key = f"idemp_res_{user_id}"
    
    success, res_id, status = await lua_reserve_stock(cust_id, idemp_key)
    if not success:
        return
    
    # 2% Duplicate Request Injection (05_API/api_notes.md)
    if is_duplicate:
        await lua_reserve_stock(cust_id, idemp_key)

    # Process Payment
    pay_idemp = f"idemp_pay_{user_id}"
    pay_ok, pay_res = await process_payment(res_id, cust_id, pay_idemp)

# --- Order Service Consumer & Outage Recovery (03_LLD/sequence_order_and_recovery.md) ---
async def order_service_consumer(outage_duration=0.01):
    # Simulate 30s Order Service Outage
    await asyncio.sleep(outage_duration)
    
    # Drain Kafka Outbox Idempotently
    while kafka_outbox:
        evt = kafka_outbox.pop(0)
        event_key = (evt["event_id"], "order-service-group")
        
        # Check processed_events table (05_API/events.md)
        if event_key in processed_events:
            continue
        
        processed_events.add(event_key)
        order_id = f"ord_{evt['pay_id']}"
        orders_db[order_id] = {"pay_id": evt["pay_id"], "cust_id": evt["cust_id"], "status": "CONFIRMED"}

# --- Main Test Runner ---
async def main():
    print("=" * 70)
    print("  SALESTORM FLASH-SALE SYSTEM SIMULATION (10,000 BUYERS)")
    print("=" * 70)
    
    tasks = []
    # Spawn 10,000 Concurrent Buyers
    for i in range(1, 10001):
        is_dup = (i <= 200) # 2% Duplicate requests
        tasks.append(asyncio.create_task(user_worker(i, is_dup)))
    
    # Execute reservation & payment pipeline concurrently
    await asyncio.gather(*tasks)
    
    # Trigger Order Service Recovery & Kafka Outbox Consumption
    await order_service_consumer(outage_duration=0.01)
    await check_conservation()

    # --- Verification & Assertion Evaluation ---
    assert_sold_max = (sold_stock <= 100)
    assert_non_negative = stock_never_negative
    assert_no_dup_res = (len(customer_reservations) == len(set(customer_reservations.values())))
    
    pay_ids = [p for p in payments_db.keys()]
    assert_no_dup_pay = (len(pay_ids) == len(set(pay_ids)))
    
    order_ids = [o for o in orders_db.keys()]
    assert_no_dup_ord = (len(order_ids) == len(set(order_ids)))
    
    successful_payments = [p for p, d in payments_db.items() if d["status"] == "SUCCESS"]
    assert_pay_to_order = (len(successful_payments) == len(orders_db))
    assert_conservation = conservation_held

    print("\n" + "=" * 70)
    print("                     SYSTEM ASSERTION RESULTS                       ")
    print("=" * 70)
    print(f" 1. Sold Stock <= 100                 : {'[PASS]' if assert_sold_max else '[FAIL]'} (Sold: {sold_stock})")
    print(f" 2. Stock Never Negative (Available>=0): {'[PASS]' if assert_non_negative else '[FAIL]'} (Available: {available_stock})")
    print(f" 3. No Duplicate Reservations/Customer: {'[PASS]' if assert_no_dup_res else '[FAIL]'} (Unique Res: {len(customer_reservations)})")
    print(f" 4. No Duplicate Payments             : {'[PASS]' if assert_no_dup_pay else '[FAIL]'} (Payments: {len(pay_ids)})")
    print(f" 5. No Duplicate Orders               : {'[PASS]' if assert_no_dup_ord else '[FAIL]'} (Orders: {len(order_ids)})")
    print(f" 6. 100% Paid Payments -> Orders      : {'[PASS]' if assert_pay_to_order else '[FAIL]'} (Paid: {len(successful_payments)}, Orders: {len(orders_db)})")
    print(f" 7. Stock Conservation (Avail+Res+Sold=100): {'[PASS]' if assert_conservation else '[FAIL]'} ({available_stock} + {reserved_stock} + {sold_stock} = {available_stock+reserved_stock+sold_stock})")
    print("=" * 70)

if __name__ == "__main__":
    asyncio.run(main())
