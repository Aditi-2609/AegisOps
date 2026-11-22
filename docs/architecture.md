# AegisOps Architecture

**Status:** M0 target architecture, ready for approval. This describes intended MVP, not current behavior.

## 1. Design

AegisOps is a local-first Python modular monolith: one FastAPI application and one PostgreSQL database with explicit module boundaries. Pydantic defines contracts; Psycopg implements persistence. Workflow, policy, reviewer gate, and simulated execution are deterministic.

**The model proposes; deterministic application code validates and executes.** M2 requires no model or RAG. M2 uses deterministic rules and predefined response templates. AI proposals/retrieval are later optional capabilities and cannot authorize or execute refunds.

```text
Customer text API -> Intake service -> Deterministic workflow/policy -> Templates
                                             |
Reviewer API -> Local authentication -> Approval service -> Simulated execution
                         \                    /
                       Repositories / Psycopg
                                |
                            PostgreSQL
                                |
                   append-only application audit

Later optional: workflow -> LLM proposal -> schema/fact validation -> workflow
```

## 2. Boundaries and responsibilities

| Boundary | Responsibility | Current status |
|---|---|---|
| `app/api` | HTTP validation, reviewer auth dependency, mapping | Only health router implemented/mounted. Intake/reviewer APIs planned. |
| Application services | Coordinate transactions and call domain/repositories; keep handlers thin | Not implemented. |
| `app/domain` | Case/request/action types, transitions, policy contracts | Empty placeholders. |
| `app/orchestration` | Deterministic workflow, clarification/escalation | Empty placeholders. |
| `app/tools` | Policy/adapters and simulated refund boundary | Empty; no real payment adapter in MVP. |
| `app/db` | Psycopg pool, migrations, repositories | Pool and migration 001 exist; repositories empty. Migration 001 has non-null conversation customer FK, to be changed by future migration. |
| Reviewer auth | Verify locally configured credential and derive principal server-side | Not implemented; never accept caller-supplied identity. |
| `app/llm`, `app/rag`, `app/agents` | Optional later proposals/retrieval | Empty placeholders; not M2 dependencies. |
| `app/guardrails`, `app/observability`, `app/control_plane` | Later extensions | Empty placeholders; core M2 safety/audit remains required. |
| `app/channels` | Channel adapters | Empty; M2 uses text HTTP API. |

Handlers validate transport input, authenticate reviewer calls, invoke services, and map domain outcomes. They do not implement policy, issue SQL, trust request-body identity, or independently execute side effects. Repositories own parameterized SQL. Domain/policy does not depend on FastAPI, PostgreSQL, or LLM SDKs.

## 3. MVP data flow

1. Text intake creates a case/conversation with no customer association, stores text complaint/damage description, and returns deterministic clarification. No placeholder customer is created.
2. Verification checks facts using the approved procedure. Only successful verification attaches existing customer/order records and appends an association audit event atomically. Failure leaves links unset.
3. Deterministic policy evaluates verified facts and text description, recording policy version, inputs, and result. Product-defined policy values block M2 until decided.
4. If eligible, persist a refund request and separate immutable proposed action with integer minor-unit amount and explicit currency. Changed terms create a new action ID.
5. An authenticated local reviewer approves/rejects the exact action. Identity derives from the auth principal. Decision is persisted against that action; rejection cannot execute.
6. A separate execution operation verifies approval and simulates the result. Templates communicate clarification, ineligibility, pending review, rejection, and completion.
7. Required audit events commit with each associated durable state change. Failures leave explicit state and recorded attempt/failure when persistence is available.

M2 calls no LLM, RAG, image processor, object store, or payment gateway.

## 4. Proposed database entities and relationships

Only customers, orders, conversations, and messages exist in migration 001. All additions below are planned. A future migration must make `conversations.customer_id` nullable (retain FK); do not create synthetic customers.

| Entity | Relationship and invariant | Status |
|---|---|---|
| `customers` | Customer PK. | Implemented in migration 001. |
| `orders` | FK to customer; integer minor units today, but no currency yet. | Implemented, incomplete for refund workflow. |
| `conversations` | Nullable customer FK; associate only after verification. | Current migration is NOT NULL; nullable target planned. |
| `messages` | FK to conversation; text/time/role. No image blobs in MVP. | Implemented schema; repositories planned. |
| `support_cases` | One case per journey, unique FK to conversation, nullable FK to verified order, status/timestamps. Customer identity is read through the conversation; no duplicate customer link is stored on the case. | Planned. |
| Verified association | Store the verified customer on `conversations.customer_id` and verified order on `support_cases.order_id`; both remain nullable until verification. One case belongs to one conversation. Verify the order belongs to that customer in the association transaction. Audit event records the verified IDs and time; no separate association table is needed for MVP. | Planned. |
| `refund_requests` | FK to case; customer request, text reason, optional requested amount/currency, status/time. Separate from action. | Planned. |
| `refund_actions` | FK to request; immutable action ID, amount, currency, terms/policy reference, proposed time. Changed terms mean new ID. | Planned. |
| `refund_approvals` | FK to exact action; decision, derived reviewer principal, confirmed amount/currency for approval, time/reason. Unique action decision; amount/currency must equal immutable action. Changed terms need new action/approval. | Planned. |
| `refund_executions` | FK to both the approved `approval_id` and same `action_id` (enforce the pair); amount/currency match approval. Unique `action_id` and globally unique idempotency key. Status: intent, completed, failed-known-no-effect, needs-reconciliation. | Planned. |
| `refund_execution_attempts` | FK to execution; unique `(execution_id, attempt_number)`; start/result/failure/time. Retry reuses parent key. | Planned. |
| `audit_events` | FK to case, optional action FK, actor/type/time/policy reference/safe details. App inserts only; normal services lack update/delete. | Planned. |
| Local reviewer credential | One username/password configured locally; HTTP Basic accepted only on loopback. Derive principal from authenticated username, compare credentials safely, and never accept identity as caller data. | Planned; provisioning/rotation documented in M1. |

All money requires integer minor units and explicit currency; never infer it from region. Constrain statuses, FKs, amounts, and uniqueness. Make action immutability enforceable for the application DB role: it may insert/read proposed actions but has no ordinary update/delete path. Approval stores and binds the confirmed amount/currency for the exact immutable action; execution references that approval and action and matches the approved amount/currency. A policy/action change requires a new proposal and approval.

## 5. Transactions, idempotency, and recovery

- **Intake transaction:** insert case, conversation (null customer FK), initial message/status, and case-created audit event together; any failure rolls all back.
- **Association transaction:** lock case/conversation, verify the existing order belongs to the existing customer, set `conversations.customer_id` and `support_cases.order_id`, and append association event atomically. Failed verification changes no links.
- **Policy/proposal transaction:** persist decision and audit; if eligible, insert request, immutable action, and proposal event together.
- **Review transaction:** authenticate first; lock action; ensure pending/unchanged; store the action ID and exact amount/currency in the single decision and append audit atomically. Decisions are not edited. Changed proposal requires a new action and decision.
- **Execution intent transaction:** verify approval; insert one execution row with server-issued idempotency key and intent status; append intent event and commit before processing.
- **Simulation transaction:** lock execution/action, validate approved decision, exact approval/action/amount linkage, insert attempt, write simulated result, mark completed (or known failure), and append events in one DB transaction. Simulated effect cannot commit without completion record.
- **Retry/reconciliation:** reuse same execution ID/key. After lost response, read by key and return completed result if present. An intent with no attempt may process under same key. Known no-effect failure may retry under same key with next attempt. If outcome cannot be established, retain/mark needs-reconciliation, stop automatic retry, inspect durable state, then explicitly reconcile. Never create a new key or blindly repeat uncertain operation.
- **Audit:** event writes share transaction with associated state transition. Ordinary app paths cannot update/delete. DB administrator tampering is outside this guarantee and needs production controls.

## 6. Security and privacy

MVP binds to loopback and uses one locally configured reviewer username/password via HTTP Basic. Accept Basic credentials only on loopback; derive principal from the authenticated username and compare credentials safely. Request schemas have no trusted reviewer ID. Missing/invalid credentials fail closed. Keep credentials in local environment configuration, excluded from source control; never log credentials/auth headers. Log correlation ID, event/outcome codes, and needed technical metadata; omit full complaint text and unnecessary personal data. Reviewer routes require authentication.

Loopback/local credentials are development controls only. Before non-local exposure, implement/review production authentication and role authorization, TLS, secret management/rotation, rate limiting, privacy/retention, DB access control, backup/recovery, and monitoring. Do not expose MVP publicly.

## 7. Implemented versus target

**Implemented:** FastAPI app; `/health`, `/health/db`; Pydantic Settings; Psycopg pool; migration 001 customer/order/conversation/message tables; one health test.

**Known gap:** migration 001 makes conversation customer FK NOT NULL. M1 must add migration to make it nullable. No migration is included in this documentation update.

**Planned, not implemented:** intake, nullable-customer migration, repositories/services, verification, policy/templates, refund entities, reviewer auth, approval, simulation, idempotency/recovery, audit, CI. AI/RAG are later. Filenames and sample content are not working features.

## 8. Architecture acceptance criteria

- M2 runs as one FastAPI app and one PostgreSQL DB; deterministic journey works with AI/RAG unavailable.
- Unidentified intake stores null customer FK and no fake row; failed verification leaves links unchanged.
- Every refund action is immutable; authenticated approval stores the exact action amount/currency; execution references both that approval and action.
- Constraints/tests prevent duplicate executions/keys; retries and uncertain outcomes follow section 5.
- Required events commit atomically with state changes; normal app has no audit edit/delete path.
- Reviewer identity derives from local authentication, and MVP binds loopback-only.
- No gateway, AI/RAG provider, image storage, or distributed service is needed for M2.
