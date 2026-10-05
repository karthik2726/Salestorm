# AI-Assisted Architecture & Engineering Disclosure Note

This document discloses the role, boundary limits, and human architectural oversight applied during the development of the SALESTORM blueprint.

---

## 1. AI Tools & Models Utilized

* **IDE Environment:** Google Antigravity IDE
* **AI Model:** Gemini 3.6 Flash (High / Medium Agentic Coding Engine)

---

## 2. What AI Tools Were Used For

1. **Diagram Drafting:** Generating Mermaid syntax for C4 Level 1–3 diagrams, sequence flows, state machines, and relational ER diagrams.
2. **Schema & Specification Boilerplate:** Drafting OpenAPI 3.0 YAML specifications and PostgreSQL 16 DDL `schema.sql` skeletons.
3. **Simulation Script Construction:** Writing the `asyncio` simulation script (`simulate.py`) to execute automated mathematical assertion checks under 10,000 concurrent requests.
4. **Visualizer Web App Dashboard:** Building the Express server and HTML/CSS glassmorphism dashboard UI.

---

## 3. What Was NOT Delegated to AI (Human Architectural Authority)

1. **System Architectural Decisions:** Selecting the hybrid concurrency lock model (Redis Lua gate + PostgreSQL Aurora Multi-AZ) over pure pessimistic or optimistic locking.
2. **Concurrency & Mathematical Reasoning:** Formulating the proof argument guaranteeing $S \le N$ non-overselling.
3. **State Machine Modeling:** Defining valid versus illegal state transitions (`SHIPPED` $\rightarrow$ `CREATED`) and compensation saga refund boundaries.
4. **Trade-off Evaluation:** Identifying sacrifices between eventual consistency vs immediate UI updates, and single-writer DB limits vs horizontal scaling.

---

## 4. Output Review & Verification Process

All AI-generated code, SQL schemas, and Mermaid diagrams were inspected and verified against system constraints:
* **Syntax Validation:** Executed SQL DDL scripts and validated OpenAPI 3.0 schemas.
* **Deterministic Execution:** Fixed random seeds in `simulate.py` and validated UTF-8 console output streams across Windows environments.
* **Assertion Testing:** Confirmed 100% pass rates across all 7 core system assertions.

---

## 5. Corrections We Made

*(Note: Human engineering team review log & placeholders for custom corrections)*

1. **[Correction 1]:** Fixed stdout UTF-8 encoding handling in `simulate.py` for Windows PowerShell terminals.
2. **[Correction 2]:** Refined state transition rules in `state_reservation.md` to explicitly forbid `EXPIRED` $\rightarrow$ `CONFIRMED` jumps.
3. **[Correction 3]:** Enforced explicit `Idempotency-Key` headers on `/v1/reservations` and `/v1/payments` endpoints in `openapi.yaml`.
4. **[Placeholder for User Input]:** *Add any additional custom domain or environment tweaks here.*
