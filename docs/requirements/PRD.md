# AegisOps Product Requirements Document

**Status:** M0 documentation ready for approval
**Scope:** local MVP for text-only damaged-product complaints and simulated refunds

## 1. Product summary

AegisOps is an AI-powered customer operations platform. Its first workflow receives a damaged-product complaint, verifies customer and order facts, evaluates eligibility using deterministic rules, obtains an authenticated human decision for every refund, and records a simulated refund outcome. Development is local-first from VS Code.

**Core principle:** The model proposes; deterministic application code validates and executes. An LLM cannot establish facts, determine eligibility, approve a refund, or execute a refund. The first complete workflow uses no LLM or retrieval-augmented generation (RAG).

## 2. Goals and scope

### MVP goals
1. Accept a text complaint before customer identification; do not create placeholder or fake customer records.
2. Associate a customer and order only after the defined verification step succeeds.
3. Persist complaint, conversation, request, decisions, and audit history in PostgreSQL.
4. Apply deterministic, testable eligibility rules and return predefined customer response templates.
5. Create an immutable proposed refund action, require an authenticated human reviewer to approve or reject that exact action and amount, and simulate execution only after approval.
6. Make retries idempotent and recover execution safely without blindly repeating uncertain operations.
7. Run the deterministic workflow with no AI provider credentials or network call.
8. Use Python, FastAPI, Pydantic, Psycopg, and PostgreSQL in a modular monolith suitable for local VS Code development.

### Out of scope
- Real payment processing, payment credentials, or external refund gateways.
- LLM/RAG dependency for intake, policy, approval, response templates, or simulated execution.
- Image attachments, object storage, voice, messaging integrations, and other multimodal evidence.
- Production multi-tenant hosting or non-local exposure before production authentication and authorization are implemented and reviewed.
- Configurable approval thresholds or approval policies. Every MVP refund requires human approval.
- General-purpose support beyond the damaged-product/refund workflow.

## 3. Actors and trust boundaries

- **Customer:** submits a complaint, text description of damage, and identifiers for verification.
- **Reviewer:** authenticates through the local MVP reviewer mechanism and approves/rejects a specific proposed action. Identity is derived from authentication, never a caller-supplied reviewer ID.
- **Operator/developer:** runs the local app/database and configures local secrets.
- **AegisOps:** validates input, stores state, applies deterministic rules, gates execution on reviewer approval, and records outcomes.

The local MVP is for a trusted developer workstation and loopback access. Its minimal reviewer credential mechanism is not production authentication. Do not expose the service beyond the local machine until production-grade authentication, authorization, transport security, secret management, and deployment controls are implemented and reviewed.

## 4. Functional requirements

### Intake, identity, and evidence
- **FR-01:** Accept a text complaint and damage description without requiring an identified customer.
- **FR-02:** Create a conversation with nullable customer association. Do not fabricate a customer record or identifier.
- **FR-03:** Persist incoming/outgoing text messages and workflow status with timestamps.
- **FR-04:** Ask for missing identifiers or verification details using deterministic prompts. Associate customer/order only after the documented verification succeeds; audit the association.
- **FR-05:** MVP evidence is text description only. No image uploads or object storage. Image/multimodal evidence is future scope.

### Deterministic policy and responses
- **FR-06:** Load customer/order facts through parameterized repository queries after verification.
- **FR-07:** Apply deterministic rules for eligibility, amount, and required text evidence. Product/operations must decide exact values before M2; do not infer values from a model or sample data.
- **FR-08:** Record decision inputs, outcome, and policy version/reference.
- **FR-09:** M2 uses predefined response templates selected by deterministic workflow outcome. No LLM or RAG is required.

### Refund request, action, review, and execution
- **FR-10:** Represent the customer refund request separately from a proposed refund action. A request may exist before eligibility or amount is determined.
- **FR-11:** A proposed action has a stable ID and immutable amount/currency and references its request/case. Changed terms require a new action proposal.
- **FR-12:** Every refund action requires approval by an authenticated reviewer. Approval/rejection binds to the exact immutable action ID and amount; an approval stores the confirmed amount and currency. Reviewer identity comes from the auth principal, not an API field.
- **FR-13:** Rejection prevents execution. Approval does not itself execute; a separate execution step re-checks action state and approval.
- **FR-14:** Simulated refunds only; no real gateway. Execution references both the approval and the same action; its amount/currency must match the approved action.
- **FR-15:** Enforce unique idempotency key and at most one execution record per action. Repeated calls with the same key return or reconcile the existing execution.
- **FR-16:** Record execution intent, attempts, failures, completion, and reconciliation. Check persisted state before retry; never blindly retry an uncertain financial operation.

### Audit, security, and operations
- **FR-17:** Append events for case creation, customer/order association, triage, eligibility decisions, action proposals, approvals, rejections, execution attempts, failures, reconciliation, and completion. Events reference the relevant case/action.
- **FR-18:** Audit is append-only at the application level; no ordinary application operation edits or deletes audit history.
- **FR-19:** Authenticate reviewer actions; fail closed on missing/invalid credentials and derive recorded reviewer principal from authentication. Never trust caller-supplied reviewer identity.
- **FR-20:** Liveness is independent of DB; readiness reports DB failure without credentials.
- **FR-21:** Return validation/not-found errors without stack traces or secrets. Log correlation IDs and workflow outcome codes; do not log credentials, auth headers, or unnecessary complaint/customer data.

## 5. Non-functional requirements

- **Safety:** no payment integration; no AI authority over policy, approval, or execution; deterministic validation at state/tool boundaries.
- **Integrity:** relational constraints, transactions, immutable action proposals, exact action/approval binding, and unique idempotency constraints.
- **Recoverability:** durable execution intent/attempts; retries reuse the key; uncertain states require reconciliation, not blind retry.
- **Auditability:** persist required events with actor, references, time, outcome, and policy version as applicable; normal app paths cannot mutate/delete history.
- **Privacy:** collect only needed data, keep secrets out of source control, and redact sensitive values from logs.
- **Testability:** policy, transitions, auth gates, constraints, transactions, idempotency, and recovery are testable without LLM/payment provider.

## 6. Unresolved decisions

1. **Before M2:** eligibility rules, purchase-age/order-status constraints, text evidence sufficiency, amount calculation/limits, and policy versioning.
2. **Before M2:** supported currency and rounding. Store integer minor units plus explicit currency; do not infer from region.
3. **Before M2:** exact identity verification questions and success criteria. An order ID alone is not proof unless approved by product.
4. **M1:** use HTTP Basic authentication with one locally configured reviewer username/password, accepted only on loopback. Derive the reviewer principal from the authenticated username; compare credentials safely and never accept caller-selected identity. Document local credential provisioning/rotation. This mechanism is development-only.
5. **Before non-local exposure:** production auth/authz, TLS, secret management, privacy/retention, backup/recovery, and audit protection.
6. **Future:** AI provider/data terms, multimodal evidence, configurable approval policy.

## 7. Current repository status

### Implemented
- Package metadata declares Python 3.11+, FastAPI/Uvicorn, Pydantic Settings, Psycopg, and HTTPX.
- `app/main.py` creates a FastAPI app and registers only the health router.
- `app/api/routes_health.py` implements `/health` and `/health/db`.
- `app/db/session.py` provides a Psycopg connection pool.
- Migration 001 creates customers, orders, conversations, and messages. Its `conversations.customer_id` is **NOT NULL**, so it does not satisfy finalized intake.
- One health test has source; most named tests, repositories, workflow modules, and CI workflow are empty placeholders.

### Planned, not implemented
Nullable conversation identity, verified association, cases/refunds, reviewer auth, policy, templates, approvals, immutable actions, simulation, idempotency, recovery, append-only audit, CI checks, and complete workflow. Existing paths/sample data do not mean behavior exists. AI/RAG are later milestones, not M2 capabilities.

## 8. MVP acceptance criteria

All checks must pass against a clean local setup:
1. Unidentified intake persists a conversation with `customer_id IS NULL`, creates no customer row, and returns a clarification path.
2. Successful verification associates existing customer/order; failure leaves links unchanged and emits no association event.
3. Text damage description persists; image upload is unsupported/rejected and no object storage is configured.
4. Policy tests cover every approved rule and boundary; decision records contain inputs, outcome, and policy version.
5. Each refund action has immutable ID, integer minor-unit amount, and explicit currency. Changed terms get a new ID and approval.
6. Unauthenticated review fails. Authenticated decisions record identity derived from credentials; caller-supplied reviewer ID cannot change actor.
7. Execution before approval of the exact action and amount is impossible; rejection creates no execution record.
8. DB constraints reject duplicate execution per action and duplicate idempotency keys; completed same-key retry returns original result.
9. Failure tests cover durable intent, attempt/failure records, same-key retry for known-safe failure, and uncertain-state reconciliation without blind retry.
10. Audit tests cover every required event, case/action references, and no ordinary edit/delete operation.
11. Full workflow passes without AI credentials/dependencies, uses deterministic templates, and makes no payment call.
12. CI runs pytest, Ruff, and mypy on supported Python and fails if any required check is missing or failing.
