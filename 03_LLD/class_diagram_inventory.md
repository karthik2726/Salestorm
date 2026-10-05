# Low-Level Class Diagram: Inventory & Reservation Service

This document specifies the internal Object-Oriented software design for the Inventory & Reservation microservice.

```mermaid
classDiagram
    class InventoryController {
        -ReservationService reservationService
        -RequestValidator validator
        +createReservation(ReservationRequest req) ReservationResponse
        +getReservationStatus(String reservationId) ReservationResponse
    }

    class RequestValidator {
        +validateReservationPayload(ReservationRequest req) void
        +validateIdempotencyKeyHeader(String key) boolean
    }

    class ReservationService {
        <<interface>>
        +reserveStock(String saleId, String customerId, String productId, String idempotencyKey) ReservationResult
        +releaseStock(String reservationId) boolean
    }

    class InventoryServiceImpl {
        -RedisLuaEngine luaEngine
        -InventoryRepository postgresRepo
        -OutboxPublisher outboxPublisher
        +reserveStock(String saleId, String customerId, String productId, String idempotencyKey) ReservationResult
        +releaseStock(String reservationId) boolean
    }

    class RedisLuaEngine {
        -RedisTemplate redisTemplate
        -String scriptSha
        +executeReserveScript(String productKey, String idempKey, String customerKey, String reservationId, int ttl) LuaResponse
        +executeReleaseScript(String productKey, String customerKey, String reservationKey) boolean
    }

    class InventoryRepository {
        <<interface>>
        +findById(String productId) Inventory
        +decrementAvailableQuantity(String productId, int qty, long version) int
        +saveReservation(InventoryReservation reservation) void
        +updateReservationStatus(String reservationId, String status) void
    }

    class PostgresInventoryRepositoryImpl {
        -DataSource dataSource
        +findById(String productId) Inventory
        +decrementAvailableQuantity(String productId, int qty, long version) int
        +saveReservation(InventoryReservation reservation) void
        +updateReservationStatus(String reservationId, String status) void
    }

    class ReservationSweeperJob {
        -InventoryRepository postgresRepo
        -RedisLuaEngine luaEngine
        +sweepExpiredReservations() void
    }

    class OutboxPublisher {
        -KafkaTemplate kafkaTemplate
        -OutboxRepository outboxRepo
        +publishEvent(String aggregateId, String eventType, Object payload) void
    }

    class Inventory {
        -String inventoryId
        -String productId
        -int availableQuantity
        -int reservedQuantity
        -int soldQuantity
        -long version
        +hasStock(int qty) boolean
    }

    class InventoryReservation {
        -String reservationId
        -String customerId
        -String productId
        -String idempotencyKey
        -ReservationStatus status
        -Instant expiresAt
        +isExpired() boolean
    }

    InventoryController --> RequestValidator
    InventoryController --> ReservationService
    ReservationService <|.. InventoryServiceImpl
    InventoryServiceImpl --> RedisLuaEngine
    InventoryServiceImpl --> InventoryRepository
    InventoryServiceImpl --> OutboxPublisher
    InventoryRepository <|.. PostgresInventoryRepositoryImpl
    ReservationSweeperJob --> InventoryRepository
    ReservationSweeperJob --> RedisLuaEngine
    PostgresInventoryRepositoryImpl ..> Inventory
    PostgresInventoryRepositoryImpl ..> InventoryReservation
```

---

## Component Responsibilities & Exception Boundary Mapping

1. **`InventoryController` & `RequestValidator` (Validation Boundary):**
   * Validates structural REST/gRPC input parameters.
   * Throws `InvalidPayloadException` (HTTP 400) or `MissingIdempotencyKeyException` (HTTP 400).
2. **`RedisLuaEngine` (Idempotency & Fast Gate):**
   * Encapsulates Redis interaction. Catches `RedisConnectionException` and gracefully degrades by logging a critical error or querying PostgreSQL fallback.
   * Returns structured `LuaResponse` (`SUCCESS`, `OUT_OF_STOCK`, `ALREADY_PROCESSED`).
3. **`InventoryServiceImpl` & `PostgresInventoryRepositoryImpl` (Persistence Boundary):**
   * Manages DB persistence. Catches `OptimisticLockException` if version verification fails.
   * Ensures outbox events are written in the same local SQL transaction block.
4. **`ReservationSweeperJob` (Background Cleanup):**
   * Polling thread. Scans expired records in PostgreSQL (`expires_at < NOW()`) and executes idempotent inventory release via `RedisLuaEngine`.

---

## Architectural Trade-Offs

* **Interface Abstraction Overhead:**
  * *Trade-off:* Creating `ReservationService` and `InventoryRepository` interfaces adds boiler-plate interface files.
  * *Justification:* Satisfies Dependency Inversion Principle (DIP). Allows mocking datastores during unit testing and swapping PostgreSQL/Redis driver implementations without refactoring controller logic.
