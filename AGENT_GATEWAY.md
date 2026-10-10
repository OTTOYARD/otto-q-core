# AGENT_GATEWAY — how an outside agent reads OTTO-Q and asks for changes

*Written 2026-09-28, 12:00–1:30 AM CT (05:00–06:30 UTC). **Live since 2026-10-04, 6:14–6:42 AM CT:** migrations
`0559`, `0560` and `0605`–`0608` are applied (versions in their headers), the edge function `ottoq-agent-gateway` is
deployed (version 1, JWT verification off), and the demo passcode is on. That morning's live checks are in
[PERSONAL_AGENT.md §9](PERSONAL_AGENT.md#9-verified-and-not-verified). What was verified before then, and how, is in
[§9](#9-what-was-verified-and-what-was-not). The morning checklist is [§8](#8-morning-checklist).*

A personal agent (Chase's Hermes bot), a fleet operator's own agent, or a depot-operations agent can now hold a
token, **read** the OTTOYARD Nashville Flagship twin depot inside a scope the database enforces, and **ask** for a
change. Nothing it asks for happens until a person approves it — the depot crew in OTTO-PULSE, or the fleet's own
operator — and nothing a person approves happens except through a door OTTO-Q already has. Where no door exists, the
approval is recorded as exactly that (`approved_no_engine_door`) and nothing in the engine changes.

> **The law:** OTTO-Q decides. OTTO-TWIN executes and owns world state. The renderer only draws.
> Agents **propose**, people **approve**, OTTO-Q's own doors and its L1 shield **dispose**.

This is AGENT_HARNESS.md's second-ranked gap ("no agent-facing door"), closed for **reading and asking**. It is not a
door for physical proposals (stall assignments): `ottoq_submit_external_proposal` remains that door, unchanged
(AGENT_API.md).

> **2026-10-03 — an owner's own agent (migrations `0605`/`0606`, [PERSONAL_AGENT.md](PERSONAL_AGENT.md)).** A token
> bound to one fleet with the `owner_settings` capability can also **set what its own cars need** without a person in
> between: a charge limit inside its contract, service orders, holds, undo. The database checks each against the
> contract and OTTO-Q's rules, records it (refusals included) and the engine applies it at its next tick; nothing moves a
> car, and the run's end lifts it all. The gateway gains the owner tools over MCP and `/v1/me/…`, `POST /v1/ask` (OTTO-Command
> reading the owner's words with the owner's own token), and a public `GET /v1/openapi.json`. Everything below about
> requests is unchanged.

> **2026-10-04 — any agent, with OTTOYARD's demo passcode (migrations `0607`/`0608`).** A caller with **no key** may use
> two public tools: `welcome` (what OTTOYARD is, what the passcode opens, the next call) and `enter_passcode` (the demo
> passcode opens a **session**: an `ottoq_agent_principals` row of origin `passcode`, an `oqs_` key shown once, exactly an
> owner key's capabilities, lasting 240 minutes or until the demo run ends). Over MCP the no-key endpoint lists both doors
> and every tool with a required `session` argument, answers session problems as tool results (never an HTTP 401), and
> needs no database for initialize, discovery, ping or tools/list; over REST, `GET /v1/welcome` and `POST /v1/passcode`
> are the only no-key routes, and the session key is then a Bearer. Every applied owner command now carries a
> confirmation code (`OQ-XXXX-XXXX`); `ottoq_depot_owner_board` (0608) shows OTTO-PULSE and the twin every owner's
> settings with their codes. A stop or reset of the twin ends every passcode session. [PERSONAL_AGENT.md](PERSONAL_AGENT.md) §0.

---

## 1. Architecture

```
  Hermes / an operator's agent / a depot agent
        |  HTTPS, Authorization: Bearer oqa_<64 hex>
        v
  ┌──────────────────────── edge function: ottoq-agent-gateway (deployed --no-verify-jwt) ──────────────────────────┐
  │  /.well-known/agent-card.json   public A2A card (discovery only)                                                 │
  │  /v1/*                          REST                         ─┐                                                  │
  │  /mcp                           MCP (2026-07-28 + 2025-xx)    ├─ Origin check -> token shape -> 64 KiB cap        │
  │                                                              ─┘  -> sha256(token) -> schema check -> ONE rpc     │
  └───────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────┘
                                                              │ POST /rest/v1/rpc/ottoq_agent_call (service key)
                                                              v
  ┌──────────────────────────── otto-q-core database (0559) ─────────────────────────────────────────────────────────┐
  │ ottoq_agent_call(token_hash, tool, args, transport, meta)            service_role ONLY                           │
  │   token hash -> active principal -> rate limit (from the ledger) -> capability -> tool -> call ledger (1 txn)   │
  │   READ tools   whoami · depot_status · fleet_summary · vehicle_card · recent_decisions · stall_availability ·     │
  │                list_requests          (compose ottoq_twin_run_context, ottoq_depot_cards, ottoq_vehicle_card,    │
  │                                        ottoq_activity_feed, ottoq.ottoq_stall_free_between)                      │
  │   ASK tools    send_note · submit_request  -> INSERT INTO ottoq_agent_requests, and nothing else                │
  │                                                                                                                  │
  │ ottoq_agent_request_decide(request, approved|declined, note)         authenticated; WHO = auth.uid()             │
  │   crew (yard_supervisor / ops_manager of the depot) or the fleet's bound operator                                │
  │   note           -> acknowledged                                                                                 │
  │   recall_vehicle -> ottoq_hw_recall_vehicle   -> applied | refused_by_engine | apply_failed                      │
  │   ops_action     -> ottoq_apply_ops_action    -> applied | refused_by_engine | apply_failed                      │
  │                     (only on the live run the request was made against; else approved_not_applied)              │
  │   adjustment     -> approved_no_engine_door   (recorded; nothing in the engine changes)                          │
  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
        ^                                                     ^
        │ supabase.rpc('ottoq_agent_inbox' / '..._decide')    │ ottoqRpc('ottoq_agent_requests_for_operator')  (anon;
  OTTO-PULSE: OTTO-Q > Agents (crew approve / decline)   OrchestrAV: Fleet > Agent requests (read-only)       needs 0560)
```

Files:

| | |
|---|---|
| `db/migrations/0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql` | tables, dispatcher, tools, people's doors, admin, grants, V1–V8 |
| `db/migrations/0560_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql` | optional: one `GRANT EXECUTE … TO anon` for OrchestrAV's read panel |
| `edge-functions/ottoq-agent-gateway/index.ts` | the I/O shell (≈40 lines) |
| `edge-functions/_shared/agent_gateway.ts` | the pure half: tool catalog, JSON schemas, validation, REST, MCP, A2A card, PostgREST caller |
| `tests/agent_gateway.test.mjs` | 33 contract/HTTP/MCP tests + 6 end-to-end over the real SQL |
| `tests/test_agent_gateway_sql.py` + `tests/fixtures/agent_gateway_stub_engine.sql` | 21 tests executing 0559/0560 against a stub engine whose doors are the live bodies (md5-proven) |
| `scripts/agent-gateway-smoke.mjs` | the morning smoke test (with an owner's token, also OpenAPI, `my_fleet` and a preview; `--ask` for `/v1/ask`) |
| `db/migrations/0605_…` · `0606_…` | an owner's agent sets what its own cars need; OrchestrAV's read of it ([PERSONAL_AGENT.md](PERSONAL_AGENT.md)) |
| `edge-functions/_shared/ottocommand_owner.ts` | `POST /v1/ask`: OTTO-Command for an owner's agent (model injected; dry run, tool set and step limit in code) |
| `tests/owner_agent.test.mjs` · `tests/test_owner_agent_sql.py` | 31 node tests (incl. end to end over the real SQL) · 50 SQL tests on a stub engine md5-pinned to the live catalog |
| `integrations/hermes/` | Hermes: the MCP config and the `ottoq-owner` skill |
| `db/migrations/0700_an_owner_signs_in_and_connects_their_own_agent.sql` | an owner signs in and connects their own agent: OTTOYARD accounts linked to a fleet, OAuth 2.1 (device code, authorization code + PKCE, refresh rotation, registration, revocation) through `ottoq_agent_oauth`, the person's doors ([PERSONAL_AGENT.md](PERSONAL_AGENT.md) section 10) |
| `edge-functions/_shared/agent_signin.ts` | the sign-in endpoints (`/oauth/*`, the protected-resource metadata) and the signed-in MCP address `/account/mcp` (access tokens only; anything else gets an RFC 9728 challenge) |
| `tests/agent_signin.test.mjs` · `tests/test_agent_signin_sql.py` | 19 node tests (incl. the whole device sign-in over the real SQL) · 35 SQL tests on the stub engine |
| `scripts/agent-signin-smoke.mjs` | the live smoke test: discovery, the site's metadata against the gateway's, a device sign-in approved through the page's doors, MCP with the token, disconnect |

## 2. Security model

- **The database decides everything that matters.** Who the caller is, what it may see, whether it may ask, the rate
  limit and the ledger all live in `ottoq_agent_call`. The edge function only shapes the conversation; a guardrail in
  it would be bypassed by anything that did not go through it (AGENT_HARNESS.md).
- **Tokens:** `oqa_` + 64 hex (32 bytes of `gen_random_bytes`), returned **once** by `ottoq_agent_issue_token`. Only
  `sha256(token)` is stored, and the edge function hashes before it calls, so the raw token never reaches the
  database after issue. It is never logged and never ledgered (`tests/agent_gateway.test.mjs` checks both).
- **Scope is fixed at issue, never taken from a request.** A principal is `personal`, `fleet_operator` (bound to one
  `fleet_operators.id`) or `depot_ops`, always at the twin depot (CLAUDE.md rule 8; `issue_token` refuses any other
  depot). Every tool schema is closed (`additionalProperties: false`), so a request cannot carry a `fleet_operator_id`,
  `depot_id` or principal; the tests try thirteen such keys against every tool.
- **A scope miss reads exactly like a missing vehicle** (`404 vehicle_not_found`), so an operator's agent cannot probe
  for another operator's vehicle ids. A fleet-scoped token can never ask for a depot-wide ops action (table CHECK).
- **Auth comes first, always.** A missing or malformed token is refused at the edge (401, `WWW-Authenticate`) and
  never reaches the database. A well-formed but unknown or revoked token is refused by the database — **including when
  the arguments are also malformed**: the edge function sends a schema refusal to the database flagged
  `meta.gateway_refusal`, so the database authenticates, rate-limits and ledgers it before the 400 goes back. An
  unknown token learns nothing, not even the schema.
- **Everything is revoked, then granted narrowly** (the "REVOKE that removed nothing" class of 0405): the three
  tables have RLS on with no policy and no privilege for anon, authenticated or service_role; the dispatcher and admin
  functions are service_role only; the inbox and decide door are authenticated only; the internal tool functions
  (which take a principal row) are executable by nobody but their owner. `0559` V3 asserts every bit with
  `has_function_privilege` / `has_table_privilege`.
- **No write path to world state.** `0559` V5 asserts, on comment-stripped source, that no function a token can reach
  names an engine door or writes outside `ottoq_agent_*`; the node suite asserts the same from the file. Only
  `ottoq_agent_request_decide` calls a door, only for a signed-in person with the authority below, and identity is
  read from `auth.uid()`, never an argument.
- **An approval does not launder an agent's request.** The ops door is called with
  `p_by = 'ottoq_prime:agent_gateway:<principal>'`, which `ottoq_is_agent_actor` treats as an agent, so
  `ottoq_policy_set` still applies the agent envelope and `agent_writable` guard, and AI.001 still judges it at
  `policy_write`. The two ops actions whose dials nothing reads (`raise_deploy_surge`, `extend_forecast_horizon`; G175,
  `INERT_OPS`) are refused at submission with the catalog's reason — never queued for a person.
- **Rate limit:** per principal, default 60 calls/minute (1–600), counted from the call ledger, so it holds across
  edge isolates. Failed-auth calls are ledgered too, capped at 60 a minute. **Pending cap:** default 20 open requests
  per principal (429 `too_many_pending`, no `Retry-After`: waiting does not clear it, a person deciding does).
- **Append-only evidence.** `ottoq_agent_requests` is `class='evidence'` in `ottoq_run_scope_registry` with **no FK to
  `ottoq_sim_runs`** (the 0340 pattern), so a request survives the demo-run purge of the run it was made against.
  Rows cannot be deleted or truncated; a closed request is frozen; what an agent asked is immutable after insert.
- **Browsers:** an `Origin` header not on `AGENT_GATEWAY_ALLOWED_ORIGINS` (unset by default) gets 403 before anything
  else. Agents are servers and send none. The MCP transport spec requires this check against DNS rebinding.
- **Deployed with JWT verification off**, because agent tokens are not Supabase JWTs and the platform check would
  refuse every agent before the function ran ([Supabase: Authorization headers](https://supabase.com/docs/guides/functions/auth-headers),
  read 2026-09-28). The Bearer token *is* the authentication — the same posture as `ottoq-energy-mpc`, without that
  function's defect (G69): there is no default token, and with its environment unset the gateway fails closed
  (`500 not_configured`).

## 3. Tool catalog

Every tool is available over REST and MCP. `sim_*` and `at_sim` fields are **simulation time**; `created_at`,
`expires_at`, `decided_at` are real time (UTC).

| Tool | REST | Capability | What it does |
|---|---|---|---|
| `welcome` | `GET /v1/welcome` | **none** (0607) | no key: what OTTOYARD is, what the demo passcode opens, whether a demo run is live, the next call; a key or session: who you are and until when |
| `enter_passcode` | `POST /v1/passcode` | **none** (0607; offered only to a caller without a key) | `{passcode, agent?}`: a session key (`oqs_`, shown once) that reads and adjusts the passcode's fleet until the demo run ends; wrong passcodes refused in plain English and throttled (5 per caller per 15 min) |
| `whoami` | `GET /v1/whoami` | any token | principal, scope, capabilities, limits, and how a change gets decided |
| `depot_status` | `GET /v1/depot` | `read` | live run (`ottoq_twin_run_context`), sim clock, your vehicles by state |
| `fleet_summary` | `GET /v1/fleet?state=&limit=` | `read` | your vehicles from `ottoq_depot_cards` (the cockpits' card feed) |
| `vehicle_card` | `GET /v1/vehicles/{id}` | `read` | one vehicle's work-order card (`ottoq_vehicle_card`), after the scope check |
| `recent_decisions` | `GET /v1/decisions?vehicle_id=&limit=` | `read` | OTTO-Q's latest decisions on the live run, filtered to your fleet |
| `stall_availability` | `GET /v1/stalls?stall_type=&horizon_min=` | `read` | the **three-gate** answer: pointer ∩ calendar in **sim** time ∩ charger not `Faulted`, with per-gate counts |
| `list_requests` | `GET /v1/requests?status=` · `GET /v1/requests/{id}` | any token | your own requests: status, decision, note, the engine's exact reply |
| `send_note` | `POST /v1/notes` | `note` | a note for the crew's inbox (and the operator's panel when it names their vehicle); changes nothing |
| `submit_request` | `POST /v1/requests` | `request_recall` / `request_ops_action` / `request_adjustment` | ask for a recall, the energy-reserve ops action, or an adjustment |

**An owner's tools (0605)** — offered only to a token bound to one fleet; full table and rules in
[PERSONAL_AGENT.md](PERSONAL_AGENT.md) §1–2:

| Tool | REST | Capability | What it does |
|---|---|---|---|
| `my_fleet` · `my_vehicle` · `my_settings` | `GET /v1/me/fleet` · `/v1/me/vehicles/{name}` · `/v1/me/settings` | `read` | the owner's cars, one car, what is in force: plain English + data + the OrchestrAV link |
| `my_commands` | `GET /v1/me/commands[/{id}]` | any (fleet-bound) | the owner's commands and their receipts |
| `set_charge_limit` · `clear_charge_limit` | `POST /v1/me/charge-limit` · `/clear` | `owner_settings` | how full the cars charge, inside the contract |
| `request_service` · `cancel_service` | `POST /v1/me/services` · `/cancel` | `owner_settings` | order (now, next return, every return) or withdraw an owner's service |
| `hold_vehicle` · `release_hold` | `POST /v1/me/holds` · `/release` | `owner_settings` | "not before" a sim time, at most 24 sim hours |
| `undo_command` | `POST /v1/me/undo` | `owner_settings` | reverse one applied command |
| *(plain English)* | `POST /v1/ask` | an owner's token | OTTO-Command reads the owner's words and calls the tools above with that token |

`GET /v1/tools` lists the tools **your** token may use with their JSON Schemas; `GET /v1` lists every endpoint;
`GET /v1/openapi.json` is the OpenAPI 3.1 document, generated from the same catalog (public).
`POST` accepts an `Idempotency-Key` header (or `idempotency_key` in the body): resending returns the first request.

**Request kinds**

| kind | needs | on approval |
|---|---|---|
| `note` (via `send_note`) | `title` | `acknowledged` — delivered; nothing to apply |
| `recall_vehicle` | `vehicle_id` in scope | `ottoq_hw_recall_vehicle` queues a `begin_charge` command for the twin → `applied` / `refused_by_engine` (e.g. `already_returning_or_home`) |
| `ops_action` | `action: enable_energy_reserve`; no vehicle; depot-wide tokens only | `ottoq_apply_ops_action` on the live run it was asked on → `applied` (incl. `no_change`) / `refused_by_engine`; `approved_not_applied` if that run is no longer live |
| `adjustment` | `adjustment` (snake_case, e.g. `charge_target`), optional `value`, optional `vehicle_id` | `approved_no_engine_door` — recorded, nothing changes; OTTO-Q has no door for it |

**Statuses:** `pending` → `declined` | `expired` | `acknowledged` | `applied` | `refused_by_engine` |
`approved_no_engine_door` | `approved_not_applied` | `apply_failed`. Only `applied` means the engine's door
accepted it. A request lapses after its TTL (notes 24 h, others 2 h by default; 5 min–7 days).

**REST envelope** (the `otto-q-api` shape): `{"data": …, "meta": {"tool", "call_id", "principal": {"name","kind"}}}`
or `{"error": {"code","message","hint?","details?"}, "meta": {…}}`. `call_id` is the row in
`ottoq_agent_call_ledger` — quote it when something looks wrong.

## 4. The approval flow

1. The agent calls `send_note` or `submit_request`. The database checks the capability, the vehicle's scope, the
   pending cap and (for ops actions) that a run is live and the dial is agent-writable, and inserts one row into
   `ottoq_agent_requests` with status `pending`. Nothing else is written.
2. **OTTO-PULSE → OTTO-Q → Agents** shows the request (`ottoq_agent_inbox`, any staff of the depot may read). A
   **yard supervisor or ops manager** approves or declines it (`ottoq_agent_request_decide`) — the same authority
   PULSE already requires for `ai.approve_action`. A note is acknowledged or dismissed.
3. **OrchestrAV → Fleet → Agent requests** shows a fleet operator its own fleet's requests (read-only; needs 0560).
   The database already lets the fleet's *bound* operator decide its own fleet's requests (never a depot-wide one),
   but OrchestrAV cannot use that yet — see §6.
4. On approval the request goes to the engine's own door and the reply is recorded **exactly** (`engine_door`,
   `engine_reply`, `applied_at`). The agent reads it back with `list_requests`; it sees that the crew or the operator
   decided, never who.

## 5. Protocols

**MCP**, one endpoint `POST /mcp`, stateless (no session is ever minted), JSON responses (no SSE):

- **2026-07-28**: requests carry `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method` (and `Mcp-Name` for
  `tools/call`) mirrored from the body, and `_meta["io.modelcontextprotocol/protocolVersion"]`. Mismatches are
  `-32020`, unknown versions `-32022` with the supported list, unknown methods HTTP 404, notifications 202, GET/DELETE
  405. Methods: `server/discover`, `ping`, `tools/list` (`cacheScope: private` — the list varies by token),
  `tools/call` (`resultType: complete`, `structuredContent` + a text copy).
- **Initialize-based revisions** 2025-11-25, 2025-06-18, 2025-03-26 on the same endpoint for older clients:
  `initialize` negotiates, then `MCP-Protocol-Version` is sent on each request.
- A tool's own refusal (not found, forbidden, invalid arguments) is a tool result with `isError: true` that an agent
  can read and act on. Only 401 (`-32001`), the rate limit (429, `-32002`) and an unreachable engine (5xx) are
  transport errors.
- **Authorization:** a static Bearer token in the `Authorization` header. OAuth / protected-resource-metadata
  discovery is **not** implemented; configure the client with the header directly.

**A2A** (1.0.0): `GET /.well-known/agent-card.json` (also `/.well-known/agent.json`) is a public **discovery** card —
`supportedInterfaces` points at `/mcp` and `/v1` as custom bindings, `securitySchemes` declares the Bearer token, and
`skills` mirrors the tools. The gateway does not implement A2A's task operations (`SendMessage` etc.).

Specs, read 2026-09-28:
[MCP 2026-07-28 Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) ·
[versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning) ·
[tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools) ·
[caching](https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching) ·
[server/discover](https://modelcontextprotocol.io/specification/2026-07-28/server/discover) ·
[release notes](https://blog.modelcontextprotocol.io/posts/2026-07-28/) ·
[A2A specification §8 (Agent Card)](https://a2a-protocol.org/latest/specification/) ·
[Supabase: Authorization headers / verify_jwt](https://supabase.com/docs/guides/functions/auth-headers) ·
[Supabase: MCP server on Edge Functions (`--no-verify-jwt`, `/<function>/*` routing)](https://supabase.com/docs/guides/functions/examples/mcp-server-mcp-lite).

## 6. What is NOT done, and what could bite

1. **Nothing is applied or deployed.** Deliberately (overnight hard limit). §8 is the path.
2. **The recall door's effect is unproven.** `ottoq_hw_recall_vehicle` is real, but `issued_by='cockpit_recall'`
   appears on exactly **one** command in the engine's life (2026-08-16 03:50 UTC) and it ended `expired` without
   executing. An approved recall records the door's reply faithfully (`queued`); whether the twin then brings the
   vehicle home has **not** been observed. The first real recall should be watched in `ottoq_vehicle_commands`.
3. **OrchestrAV cannot decide.** It reaches this database with the anon key only; `fleet_operators.auth_user_id` is
   NULL for all four operators (measured 2026-09-28). The database door for an operator exists and is tested; using it
   needs OrchestrAV to sign its users in to this project and each operator row to be bound. Until then the crew
   decides in PULSE. OrchestrAV's read panel needs **0560**, an explicit exposure decision (0560 §2): anyone holding
   the public anon key who knows an operator's id can read that operator's agent requests.
4. **`adjustment` requests have no engine door** (`approved_no_engine_door`, nothing changes). Charge targets,
   holds, etc. would each need a door OTTO-Q does not have.
5. **No retention for `ottoq_agent_call_ledger`** and **no schedule for `ottoq_agent_expire_lapsed()`** — pg_cron was
   out of bounds overnight. Reads already show a lapsed request as `expired` (`lapsed: true`); the recorded status
   flips when it is next touched or when `expire_lapsed` runs. A retention decision is needed before the ledger is
   large (worst case 60 calls/min/principal ≈ 86k rows/day/principal).
6. **HERMES.md says Hermes's database use is read-only.** A gateway note is an API call, not SQL, but it does put a
   row in `ottoq_agent_requests` on Hermes's behalf. Tell Hermes the gateway is the sanctioned channel for notes
   (or amend HERMES.md) — this PR does not edit Hermes's instructions. Separately: Hermes also holds a Management API
   token with postgres-role SQL, which the gateway's model cannot constrain.
7. **Not wired:** a KPI-4 touch event for a person's approval (2.9 `touch_events_per_turn`); streaming / SSE; MCP
   resources and prompts; OAuth discovery; A2A task operations; a per-isolate pre-database rate limiter (every
   well-formed request costs one database call, bounded by the ledger caps).
8. **Findings are not given G-numbers here.** PR #211 is concurrently claiming G265–G273; the items above should be
   numbered after both merge.
9. **Numbering and merge conflicts.** These files were written as 0550 and 0551, leaving 0547–0549 for the
   concurrent charger work (PR #211). That work grew to 0554 (PR #213: 0550–0554 are its fault door, charge line,
   bay holds and bay seats), so at the merge of 2026-09-28 these were renumbered 0555 and 0556. They merged under
   those numbers (PR #212) while PR #214, still open, had already APPLIED its own 0555–0558 (the faulted-car
   repairs, whose `ottoq_cert_lineage` rows carry those numbers). Nothing checks for a repeated number, since the
   names differ, so these two were renumbered a second time, to **0559 and 0560**, before either was applied; the
   angled-stall migration became 0561 for the same reason. Conflicts are expected in the generated files
   (`MIGRATION_LOG.md` index, the manifest in `scripts/check-drift.sql`): rebase and re-run
   `bash scripts/regen-artefacts.sh`, never resolve them by hand.
10. **Edge drift:** `_MANIFEST.md` lists the function as committed-not-deployed. `scripts/check-edge-drift.sh` only
    walks deployed functions, so it will not report this one until it is deployed.

## 7. For Hermes: copy-paste

```bash
export OTTOQ_GATEWAY=https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway
export OTTOQ_AGENT_TOKEN=oqa_...          # from §8 step 4; a secret: never in a chat, a file in git, or a URL
H="Authorization: Bearer $OTTOQ_AGENT_TOKEN"

curl -sS "$OTTOQ_GATEWAY/v1/whoami" -H "$H"                              # who am I, what may I do
curl -sS "$OTTOQ_GATEWAY/v1/depot" -H "$H"                               # is a run live; sim clock (SIMULATION time)
curl -sS "$OTTOQ_GATEWAY/v1/fleet?state=charging_dcfc&limit=20" -H "$H"
curl -sS "$OTTOQ_GATEWAY/v1/stalls?stall_type=dcfc&horizon_min=30" -H "$H"
curl -sS "$OTTOQ_GATEWAY/v1/decisions?limit=5" -H "$H"

# the first note (lands in OTTO-PULSE > OTTO-Q > Agents)
curl -sS -X POST "$OTTOQ_GATEWAY/v1/notes" -H "$H" -H "Content-Type: application/json" \
  -H "Idempotency-Key: hermes-first-note" \
  -d '{"title":"Hermes here: first note through the agent door","body":"Testing the OTTO-Q agent gateway.","priority":"normal"}'

# ask for a recall (needs a token with request_recall)
curl -sS -X POST "$OTTOQ_GATEWAY/v1/requests" -H "$H" -H "Content-Type: application/json" \
  -d '{"kind":"recall_vehicle","title":"Bring Waymo-AV-012 home: tire warning","vehicle_id":"<uuid from /v1/fleet>"}'

# what became of it
curl -sS "$OTTOQ_GATEWAY/v1/requests?status=pending" -H "$H"
curl -sS "$OTTOQ_GATEWAY/v1/requests/<request_id>" -H "$H"
```

MCP, for a client that speaks it (initialize-era shown; 2026-07-28 clients add `Mcp-Method` / `Mcp-Name` and
`_meta` as in §5):

```bash
curl -sS -X POST "$OTTOQ_GATEWAY/mcp" -H "$H" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"hermes","version":"1"}}}'
curl -sS -X POST "$OTTOQ_GATEWAY/mcp" -H "$H" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"send_note","arguments":{"title":"Hermes via MCP"}}}'
```

A generic MCP client entry: URL `$OTTOQ_GATEWAY/mcp`, transport Streamable HTTP, header
`Authorization: Bearer <token>` (for example `claude mcp add --transport http ottoq "$OTTOQ_GATEWAY/mcp" --header "$H"`,
syntax per [Claude Code: MCP](https://code.claude.com/docs/en/mcp), read 2026-09-28).

Every example above was run against a local rehearsal of the gateway over the real 0559 SQL (§9), not against
production.

## 8. Morning checklist

All times CT. Nothing below is urgent; each step is safe to stop after.

1. **Review and merge** the otto-q-core PR (and, when ready, the OTTO-PULSE and OrchestrAV PRs — their panels show
   "Agent access is built but not enabled yet" until steps 2–3 are done, so they are safe to merge first).
2. **Apply 0559 per `scripts/APPLYING.md`.** Dry-run first (§3b): its P0–P2 premises were dry-run read-only against
   live at 12:41 AM CT and every P1/P2 premise held. **P0 will refuse while the recert runner is certifying** (cron
   746 fires every minute and certifies for up to ~10½ minutes; it was mid-sweep at 12:41 AM CT) — if it refuses, wait
   a few minutes and apply again. Apply the **whole, unedited file** (≈129 KB) with the Supabase MCP `apply_migration`,
   name `an_outside_agent_asks_through_one_door_and_a_person_decides`. It creates only new objects, touches no
   existing function, and classifies itself `forces_recert = false`, `forces_dial_restart = false` (so neither the
   canon streaks nor the dial experiments restart). Record the version, run `bash scripts/regen-artefacts.sh`, log it
   in `MIGRATION_LOG.md`, commit.
3. **Decide on 0560** (optional). Apply it only if OrchestrAV's read-only "Agent requests" panel is worth the anon
   exposure in 0560 §2. Skip it and the panel says honestly that it is not enabled.
4. **Deploy the edge function, JWT verification OFF:**
   ```bash
   supabase functions deploy ottoq-agent-gateway --project-ref gxdrcyphqjzjsuhxuqtg --no-verify-jwt
   ```
   (The MCP `deploy_edge_function` tool also works: deploy `edge-functions/ottoq-agent-gateway/index.ts` plus
   `edge-functions/_shared/agent_gateway.ts` and `edge-functions/_shared/agent_dial_discipline.ts`, with
   `verify_jwt: false`.) No secrets to set: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the
   platform. Log it in `MIGRATION_LOG.md` and add its row to `edge-functions/_MANIFEST.md`.
5. **Issue Hermes a token** — SQL editor or MCP `execute_sql`, run once; **the token is shown once**:
   ```sql
   SELECT ottoq_agent_issue_token(
     'hermes',                                   -- name
     'personal',                                 -- kind: personal | fleet_operator | depot_ops
     ARRAY['read','note'],                       -- start with read + note; add request_recall etc. later
     NULL,                                       -- fleet_operator_id (only for kind fleet_operator)
     '11111111-1111-1111-1111-111111111111',     -- the twin depot (the only one allowed)
     'Chase''s Hermes bot',                      -- note
     60,                                         -- calls per minute
     20);                                        -- max pending requests
   ```
   Copy `token` from the result into Hermes's secret store. Only its SHA-256 is kept; a lost token is revoked and
   re-issued, never recovered.
6. **Smoke test** from any machine with Node 18+:
   ```bash
   GATEWAY_URL=https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway \
   AGENT_TOKEN=oqa_... node scripts/agent-gateway-smoke.mjs
   ```
   Seven steps: card, a wrong token refused, whoami, depot, MCP, a note, the note read back. Add `--no-note` to skip
   the write.
7. **See it land:** OTTO-PULSE → OTTO-Q → **Agents** (signed in as a yard supervisor or ops manager) shows the note;
   Acknowledge it; `GET /v1/requests/<id>` then reads `acknowledged`.
8. **Let Hermes send its own note** with §7's curl (and tell it the gateway is the sanctioned channel — §6 item 6).

**Operating it:**

```sql
-- who holds a token
SELECT name, kind, fleet_operator_id, capabilities, status, created_at, last_used_at FROM ottoq_agent_principals;
-- revoke (by name or principal_id); also expires its open requests
SELECT ottoq_agent_revoke('hermes', 'rotated', true);
-- what agents have been doing
SELECT called_at, principal_name, transport, tool, http_status, error_code, latency_ms
  FROM ottoq_agent_call_ledger ORDER BY call_id DESC LIMIT 50;
-- open requests
SELECT created_at, principal_name, kind, title, status, expires_at FROM ottoq_agent_requests
 WHERE status = 'pending' ORDER BY created_at DESC;
-- record lapsed requests as expired (reads already treat them so)
SELECT ottoq_agent_expire_lapsed();
```

A token's scope cannot be edited (the guard refuses it): issue a new principal and revoke the old one.

## 9. What was verified, and what was not

**Verified (2026-09-28, 12:00–1:30 AM CT):**
- `0559` and `0560` applied cleanly to a scratch PostgreSQL 16 over `tests/fixtures/agent_gateway_stub_engine.sql`,
  whose ten engine functions (the two doors, `ottoq_policy_set`, `ottoq_dial_clamp`, `ottoq_is_agent_actor`,
  `ottoq_policy_get`, `ottoq.ottoq_stall_free_between`, `ottoq_twin_run_context`, `ottoq_vehicle_card`,
  `ottoq_check_run_scope_registry`) are byte-identical to the live catalog (md5, read-only). All in-file checks
  (P0–P2, V1–V8 including the rolled-back V7 round trip) pass there; a second apply refuses; the probe leaves nothing.
- `tests/test_agent_gateway_sql.py`: 21 passed. `tests/agent_gateway.test.mjs`: 39 passed (33 + 6 end-to-end through
  the HTTP handler over the real SQL). Mutation-checked: forwarding the raw token, opening a schema, skipping the
  database on a refusal, disabling the Origin check, not authenticating notifications, dropping the fleet filter in
  SQL, and leaving `forces_dial_restart` NULL each turn the suite red.
- 0559's P1/P2 premises dry-run read-only against live at 12:41 AM CT: all hold (P0 correctly saw the recert runner).
- The smoke script and every curl in §7 were run against a local HTTP rehearsal (node:http → the shared handler →
  the real SQL in a scratch database): 7 of 7 steps passed.
- The shared module and the shell type-check under `tsc --strict` (with a Deno shim), and import under Node 22.18+
  type stripping.

**Not verified:**
- Anything on the Supabase platform: the deploy, `--no-verify-jwt` in practice, the request URL the runtime presents
  (the code accepts both `/functions/v1/ottoq-agent-gateway/…` and `/ottoq-agent-gateway/…`), PostgREST's handling of
  the call, real latency.
- Deno's own type checker (none available here; `tsc` with a shim is the substitute).
- The recall door's downstream effect (§6 item 2), and the ops door against a live run.
- Real MCP clients (Claude Code, Hermes) — the protocol behaviour is tested against the spec text, not a client.
