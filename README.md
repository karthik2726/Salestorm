# SALESTORM: High-Scale Flash-Sale E-Commerce System Architecture Blueprint

Welcome to **SALESTORM** — a design-first architecture blueprint for high-scale flash-sale e-commerce platforms. Engineered to handle **500,000 req/sec peak ingress**, SALESTORM guarantees **zero overselling**, **zero double-charging**, **zero duplicate orders**, and **100% data recovery** across service outages.

---

## 📁 Repository Deliverable Index

* 📜 [`01_Requirements/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/01_Requirements/requirements.md): Functional/non-functional specifications, p95/p99 latency SLAs, 500k rps traffic math, and strict guarantees vs targets table.
* 🏛️ [`02_HLD/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/02_HLD/hld_overview.md): High-Level Design featuring C4 Level 1 Context, C4 Level 2 Container, Multi-AZ deployment, sync vs async matrix, and bottleneck scalability.
* 🔧 [`03_LLD/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/03_LLD/demo_traces.md): Low-Level Design detailing C4 Level 3 Class diagrams, sequence flows, state machine transition matrices, and 7 test scenario traces.
* 🗄️ [`04_Database/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/04_Database/schema.sql): PostgreSQL 16 schema DDL, 18-entity Mermaid ERD, and transaction boundaries under `READ COMMITTED` isolation.
* 🌐 [`05_API/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/05_API/openapi.yaml): Complete OpenAPI 3.0 specification, mandatory `Idempotency-Key` headers, status code dictionary, and Apache Kafka event architecture.
* 🧱 [`06_SOLID/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/06_SOLID/solid_mapping.md): Object-oriented mapping of SRP, OCP, LSP, ISP, and DIP principles to concrete codebase class names with trade-off justifications.
* 🎨 [`07_Design_Patterns/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/07_Design_Patterns/pattern_mapping.md): Architectural application of 8 design patterns (Strategy, Factory, State, Observer, Adapter, Repository, Facade, Circuit Breaker) and developer extension guides.
* ⚡ [`08_Scalability_Reliability/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/08_Scalability_Reliability/scalability_reliability.md): Concurrency locking comparison, atomic Lua script (`reserve_stock.lua`), non-oversell proof, 50x traffic engineering, and failure scenario runbooks.
* 🔒 [`09_Security_Observability/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/09_Security_Observability/security_observability.md): Security threat matrix, stateless JWT auth, PCI scope reduction, structured JSON logs, OpenTelemetry tracing, and Prometheus alerts.
* 📋 [`10_ADR/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/10_ADR/ADR-001_SQL_vs_NoSQL.md): 9 formal Architectural Decision Records (ADRs 001–009) documenting key trade-offs across storage, concurrency, messaging, and caching.
* 🧪 [`11_AI_Assisted_Validation/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/11_AI_Assisted_Validation/validation_report.md): AI-assisted system validation report and automated assertion test suite results for the 10,000-buyer scenario.
* 🎤 [`12_Presentation/`](file:///f:/system%20design%20hack/SALESTORM_TEAM/12_Presentation/slides_outline.md): Hackathon pitch presentation outline, crisp jury Q&A defense guide, and spoken 90-second execution walkthrough script.

---

## 💻 Live Visualizer Dashboard & Simulation

Launch the interactive web dashboard to simulate 10,000 concurrent buyers, test 30-second Order Service outages, inject 2% duplicate requests, and verify automated assertions in real time:

```bash
node server.js
```
👉 Open Dashboard: **[http://localhost:3000](http://localhost:3000)**
