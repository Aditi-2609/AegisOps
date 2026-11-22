# AegisOps Milestones

This roadmap orders delivery from M0 documentation to the local damaged-product/refund MVP and later extensions. A milestone passes only when every listed check passes. Module names, sample data, empty tests, and config files are not evidence of implementation.

## M0 — Product and architecture baseline

**Goal:** establish an internally consistent, reviewable MVP specification and architecture decision.
**Dependencies:** none.
**Deliverables:** PRD, architecture, this roadmap, and modular-monolith ADR at the specified paths.

**Acceptance criteria:**
- All four documents exist and are non-empty.
- Each distinguishes implemented repository facts, planned behavior, and open decisions.
- All agree: unidentified intake, nullable customer association, authenticated approval for every refund, simulated execution only, and no M2 LLM/RAG dependency.
- Architecture separates request, immutable action, approval, execution, idempotency, recovery, and audit.
- Milestones specify dependencies and observable checks.

**Status:** Documentation content is complete and ready for user approval. User approval is the remaining M0 gate. No application behavior is claimed complete.

## M1 — Deterministic backend, schema, local reviewer auth, and CI

**Goal:** establish safe local foundation without AI.
**Dependencies:** M0 approved. Product/operations must decide M2-blocking eligibility, amount, currency, evidence sufficiency, and identity-verification rules before M2.

**Deliverables:**
- Migration/schema for nullable conversation customer FK, cases, verified associations, refund requests, immutable actions, approvals, executions, attempts, and audit.
- Psycopg repositories and transaction boundaries; unique constraints for one execution/action, idempotency key, and attempt number/execution.
- Loopback-only HTTP Basic reviewer authentication with locally configured username/password; derive identity server-side and document credential provisioning/rotation.
- Deterministic policy/template interfaces, API error mapping, DB pool lifecycle, and local setup.
- **CI implementation and validation:** supported Python, install project/dev dependencies, run pytest/Ruff/mypy, verify triggers and failure reporting.

**Acceptance criteria:**
- Clean local setup starts API/PostgreSQL; health/readiness behavior includes 503 when DB is unavailable.
- Migration permits null conversation customer FK and retains referential integrity.
- Constraints enforce refund/action/approval/execution links and uniqueness.
- Repository tests cover parameterized lookups, rollback, verified order/customer association, FKs, and uniqueness.
- Reviewer tests prove missing/invalid credentials fail and caller identity cannot alter principal.
- CI runs on supported Python for configured triggers and reports pytest/Ruff/mypy failures as failed checks. **M1 cannot pass if a required check is absent or failing.**

## M2 — Deterministic text-only damaged-product/refund workflow

**Goal:** complete journey with deterministic policy/templates and no LLM, RAG, image upload, object store, or gateway.
**Dependencies:** M1 complete; product/operations has decided policy, identity, and evidence rules listed in PRD.

**Deliverables:** unidentified complaint intake, verification/association, deterministic states/policy, text damage description, response templates, request/action proposal, authenticated reviewer decision, simulated execution, idempotency/recovery, append-only audit.

**Acceptance criteria:**
- Intake without identity stores null customer link, creates no fake customer, and returns clarification template.
- Failed verification leaves links unchanged; success associates existing customer/order and appends association event.
- Tests cover each finalized policy rule and values below/at/above each boundary.
- Every refund requires authenticated review of the exact immutable action and amount; approval stores the approved amount/currency and execution links to that approval/action. Unauthenticated/mismatched/rejected action cannot execute.
- Changed amount creates a new action requiring new approval; approved action has no normal update/delete path.
- Repeated/concurrent execution with same key yields one result; DB rejects duplicate action execution and keys.
- Tests cover durable intent, known failure, same-key retry, lost response after completion, and uncertain reconciliation; uncertain outcome is not auto-retried.
- Required audit events include case/action links and commit in the state-change transaction; API has no audit edit/delete operation.
- Full journey passes with AI/RAG unavailable, uses templates, and makes no payment call.

## M3 — Optional bounded AI proposals and safety evaluation

**Goal:** add AI assistance without changing deterministic authority.
**Dependencies:** M2 complete and typed contracts stable; provider, credentials, and data terms selected.

**Deliverables:** optional provider, Pydantic proposals, bounded classification/extraction/drafting, input/output checks, injection handling, repeatable eval runners.

**Acceptance criteria:**
- Disabling/unavailable AI leaves every M2 journey functional.
- Invalid/conflicting/adversarial proposals cannot change policy, identity, approval, amount, or execution.
- Fixed routing/red-team datasets run and emit documented metrics; pass thresholds are recorded before release.
- Tests prove AI cannot approve or execute refunds.

## M4 — Approved-policy retrieval and operational hardening

**Goal:** add grounded responses and diagnostics if product demonstrates need.
**Dependencies:** M2 policy ownership/audit; M3 only if answers use LLM. Retrieval is optional and never required by deterministic workflow.

**Deliverables:** versioned policy ingestion and retrieval if approved; structured logs/tracing; AI cost/latency measurement if enabled; operational config.

**Acceptance criteria:**
- If enabled, retrieval reports metrics on a fixed dataset against thresholds approved before the run.
- M2 templates remain available when retrieval is down; responses do not state unsupported policy facts.
- Tests verify correlation IDs across request/workflow/action and absence of credentials/full complaint text in standard logs.
- Provider/retrieval failure returns a defined clarification or escalation template.

## M5 — Channel expansion and non-local release readiness

**Goal:** add channels/external deployment only after prioritization and security review.
**Dependencies:** M2 complete; M3/M4 only if used; production security controls before non-local exposure.

**Deliverables:** prioritized channel adapters; production identity/access design; deployment, privacy/retention, backup/recovery, monitoring, support runbooks.

**Acceptance criteria:**
- Channel contract tests preserve verified identity association, reviewer gate, action binding, audit, and idempotency.
- Before exposure, review auth, authorization, TLS, secrets, limits, retention, DB access, backup/recovery, monitoring, and incident response.

## Dependency overview

```text
M0 approval
  -> M1 schema, local auth, deterministic foundation, required CI
      -> M2 finalized rules -> deterministic text-only workflow
          -> M3 optional AI
          -> M4 optional retrieval/operations (M2 works without it)
          -> M5 channels/non-local deployment after security gates
```

No business policy values are silently selected. M2 waits for PRD decisions. Every M2 refund requires human approval; configurable thresholds are future scope.
