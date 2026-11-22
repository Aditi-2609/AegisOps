# ADR 0001: Use a Modular Monolith

- **Status:** Accepted for MVP target; M0 documentation ready for approval
- **Date:** 2026-11-22
- **Decision owners:** AegisOps product and engineering

## Context

AegisOps is an early customer operations platform with a local MVP for text-only damaged-product complaints and simulated refunds. The repository currently has a small FastAPI health API, Psycopg pool, and initial PostgreSQL schema. It does not contain an implemented complaint workflow, repositories, reviewer authentication, refund handling, or CI checks. Most named modules are empty placeholders.

The workflow needs consistent persistence of cases, immutable proposed actions, reviewer decisions, simulated execution, and audit events. Intake can precede customer identification. Every refund requires authenticated human approval. AI/RAG follows the deterministic workflow; no real gateway is in scope.

## Decision

Build the MVP as one Python/FastAPI application with one PostgreSQL database and explicit boundaries: transport API, application services, domain/policy/orchestration, tool adapters, repositories, and infrastructure.

HTTP handlers validate/map requests, authenticate reviewer operations, and delegate to application services. Deterministic domain/policy controls transitions and eligibility. Repositories own parameterized SQL. Local reviewer identity is derived from a locally configured HTTP Basic username/password accepted only on loopback, never selected by API callers. Persist a refund request, immutable proposed action, approval bound to its exact amount/currency, and a separate execution record linked to both that approval and action.

M2 uses deterministic decisions and predefined responses without LLM/RAG. Later AI returns validated proposals and cannot approve or execute. M2 executor is simulated only.

## Why not microservices

- One local deployment unit fits current scope without service discovery or distributed authentication.
- One relational database supports explicit transactions and constraints across case, approval, execution, and audit.
- One process makes policy/reviewer gates easier to enforce before an adapter runs.
- There is no measured workload, independent scaling need, or ownership boundary that warrants microservices.
- The repository has not implemented enough workflow to establish useful service boundaries.

## Alternatives considered

1. **Microservices first:** rejected; networking, deployment, and distributed consistency add cost without demonstrated need.
2. **Unstructured single module:** rejected; API, policy, persistence, auth, and adapters need testable boundaries.
3. **AI-agent-first workflow:** rejected; model output cannot be authority for identity, policy, approval, or execution.

## Consequences

### Benefits
- One app/database for local development and debugging.
- State, approval, simulated effect, and audit can share transaction boundaries.
- Deterministic workflow can be tested without AI/payment dependencies.
- Clear boundaries retain a future extraction option.

### Costs and constraints
- Shared process/database require dependency direction, code review, and tests.
- App scales and fails as one unit.
- Migrations and transaction boundaries require discipline.
- Local reviewer credentials are not suitable for non-local exposure; production auth/authz, TLS, secret management, and operational controls are prerequisites.
- Application-level append-only audit cannot prevent database-admin tampering; stronger protection is a production decision.

## Revisit conditions

Revisit for measured independent scaling, release cadence, ownership, security isolation, or availability needs beyond a well-structured monolith. Extraction must preserve verified association, deterministic policy authority, exact action approval, idempotent execution, and audit semantics.

## Implementation status

This is a target decision, not a claim of implemented workflow. Migration 001 currently makes `conversations.customer_id NOT NULL`, contrary to unidentified intake; M1 must add a migration making it nullable. Refund/request/action/approval/execution/audit entities, reviewer auth, deterministic policies/templates, CI, and workflow are planned and absent. No application or database files were changed for this ADR update.
