# AGENT_API — the door an outside agent calls, exactly as it is today

*Written 2026-09-13 05:40 UTC (12:40 AM CT) from the live function bodies in
`otto-q-core` (`gxdrcyphqjzjsuhxuqtg`). This page documents what EXISTS. It
deploys nothing and grants nothing. Where a step is not yet proven end-to-end it
says so in the same breath.*

`AGENT_HARNESS.md` names "no agent-facing door" as the second-ranked gap. That is
half right and worth stating precisely: **the door exists as a database RPC with
the right identity and refusal semantics; what does not exist is an HTTP surface
in front of it, a published schema, and a client that has exercised it as a
plain authenticated user.** This file is the contract for the first half.

## The three calls

### 1. Read the world — `ottoq_build_decision_frame(depot_id, sim_run_id) → jsonb`

`LANGUAGE sql`, `STABLE`, `SECURITY DEFINER`. Five top-level keys: `vehicles`
(13 fields each), `stalls` (7), `sessions` (6), `energy` (6), `bess` (5).

**Know what it does not carry, or your proposals will be refused for reasons you
cannot see** (`db/checks/0186`, finding L-61): per stall it omits `reserved_by`,
`reservation_expires_at`, the charger's `station_state` and `last_heartbeat_at`,
and `ocpp_charger_id` — which is the join key the proposal selector's own filter
uses. Per vehicle it does not say whether the vehicle already holds a reservation
or a booking. Migration `0263` is the fix; until it lands, a proposer planning
from the frame alone will name stalls that are reserved for somebody else,
occupied since the frame was built, or attached to a `Faulted` charger. That is
exactly how 90 CP-SAT proposals reached the door and none were followed.

### 2. Propose — `ottoq_submit_external_proposal(sim_run_id, depot_id, action_context, entity_type, entity_id, proposal jsonb, source, ttl_seconds) → uuid`

`SECURITY DEFINER`. The only way in. Its semantics, read off the body:

- **Identity is the server's to assign, never the client's** (`0198`). An
  `anonymous` caller is refused outright (`OTTOQ_PROPOSAL_UNAUTHENTICATED`,
  SQLSTATE 42501). A `system` caller (cron, a migration, an edge function holding
  `service_role`) may name its own `source`. **An operator — any ordinary
  authenticated user — has its source overwritten with `operator:<auth_uid>`
  whatever the client typed.** So an outside agent cannot impersonate `cuopt`, and
  cannot ever be mistaken for a certified proposer.
- **Posture A refuses a stranger in a certification arm** (`0241`). If the target
  run's `run_by` is `cert_harness` and the server-derived source is not a row in
  `ottoq_certified_proposers`, the call raises `OTTOQ_PROPOSAL_REFUSED_CERT` —
  *before* the supersede below, so a refused proposal cannot even displace a
  pending one on its way out. The error text names the two legitimate routes:
  register the proposer, or record and replay (`ottoq_proposal_replay_capture`
  then `ottoq_determinism_pair_replay`).
- **One pending proposal per (run, context, entity_type, entity).** Submitting
  supersedes the previous pending row for that key. Not an error, a lifecycle.
- **The tick is the run's to state, not the caller's** (`0236`): `tick_seq` is read
  from `ottoq_sim_runs.tick_count` at insert.
- **The TTL is wall-clock**: `expires_at = now() + ttl_seconds`. The sweep in
  `ottoq_decide_tick` additionally floors freshness at `created_at + 35 minutes`,
  so a very short TTL does not expire a proposal mid-tick.
- Returns the new `proposal_id`.

### 3. Read what happened — `ottoq_decisions` and the proposal's own status

The disposer records one `ottoq_decisions` row per decision with
`proposed_action`, `enacted_action`, `overridden`, `override_rule_codes`,
`rule_results` and `outcome_status`. Your proposal's row then ends at one of:

| status | meaning |
|---|---|
| `enacted` | the decision at that tick for that entity was yours, and the enacted action carried your source |
| `superseded` | the entity was decided that tick, but not by your proposal |
| `expired` | freshness ran out before the entity was decided |
| `pending` | still live, not yet consumed |

Read `enacted` as **credit, not influence**: the closer matches
`enacted_action->>'source'` against your source string, so a path that rewrites or
drops `source` loses the credit even when it followed you (`db/checks/0188`).

## What the kernel guarantees you, and what it refuses you

Measured with `has_table_privilege` / `has_function_privilege`:

| role | INSERT on `ottoq_external_proposals` | INSERT on `ottoq_stall_bookings` | EXECUTE the door |
|---|---|---|---|
| `anon` | no | no | **no** |
| `authenticated` | **no** | **no** | yes |
| `service_role` | yes | yes | yes |

So: **an agent may propose and may not write.** Not by convention — by privilege.
`service_role` is the trusted server key and is the honest exception; it is why
`bridge/proposer_bridge.py` contains no `INSERT` statement at all and a test pins
that fact.

Then the kernel disposes. The L1 shield — **20 of 29 active rule codes, at four
probe points** (`db/checks/0192`) — evaluates the
proposed action; the stall calendar's `EXCLUDE` constraint makes a double booking
physically impossible; a refusal is a row with rule codes, not a silent drop. Two
of the fourteen certification atoms (`h_prop`, `h_defr`) hash the proposal and
deferral streams, so a proposer cannot change a certified run without the
verdict moving.

## The minimum viable agent loop

```sql
-- 1. what does the depot look like right now
SELECT public.ottoq_build_decision_frame(
         '11111111-1111-1111-1111-111111111111'::uuid,   -- depot
         '<sim_run_id>'::uuid);

-- 2. propose one stall for one vehicle (identity is assigned server-side)
SELECT public.ottoq_submit_external_proposal(
         '<sim_run_id>'::uuid,
         '11111111-1111-1111-1111-111111111111'::uuid,
         'stall_assignment', 'vehicle', '<vehicle_id>'::uuid,
         jsonb_build_object('verb','assign_stall', 'abstain', false,
                            'vehicle_id','<vehicle_id>',
                            'stall_id','<stall_id>', 'stall_type','dcfc',
                            'requested_kw', 150,
                            'rationale', jsonb_build_object('why','lowest SoC, DCFC free')),
         'my_agent', 600);
-- To decline honestly, submit the same shape with abstain=true and a reason. An
-- abstention is a ledger row that says "this proposer had nothing to offer for
-- this vehicle at this tick", which is a different and more useful fact than
-- silence. `requested_kw` is computed from the plug and the stall by the
-- reference client, never trusted from a model (bridge/llm_proposer.py law 2).

-- 3. read the verdict for that entity at the tick it was decided
SELECT tick_seq, outcome_status, overridden, override_rule_codes,
       proposed_action->>'verb' AS proposed, enacted_action->>'verb' AS enacted
  FROM public.ottoq_decisions
 WHERE sim_run_id = '<sim_run_id>'::uuid AND entity_id = '<vehicle_id>'::uuid
 ORDER BY tick_seq DESC LIMIT 5;
```

`bridge/proposer_bridge.py` is the reference implementation of exactly this loop,
with two guards any unattended caller needs: it refuses to fire while
`pg_stat_activity` shows a certification or A/B pair in flight, and it refuses a
run whose `run_by` is `cert_harness`.

## What is NOT true yet

1. **No HTTP surface is deployed for this.** The 27 committed edge functions do
   other jobs; none of them is a general proposal endpoint, and nothing here
   deploys one.
2. **No client has exercised the door as a plain `authenticated` user.** The
   privilege table proves an operator *can*, and the body proves its source would
   be rewritten to `operator:<uuid>`; no run has done it. That is the cheapest
   remaining proof and it belongs with the first external agent.
3. **No published JSON schema for `proposal`.** The shield validates meaning, and
   `bridge/` validates shape for its own rows; an outside agent currently learns
   the expected verbs by reading this page. A declared schema per
   `action_context` is the right next artifact.
4. **The frame does not yet show what the selector filters on** (`0263`), so a
   well-behaved agent can still be refused for invisible reasons. Until that
   lands, an outside agent should expect `superseded` far more often than
   `enacted` and should not read that as the kernel ignoring it.
