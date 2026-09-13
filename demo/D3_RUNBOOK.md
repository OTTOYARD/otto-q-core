# D3 — "Agents propose, solver disposes" — the runbook

V1_DEMO_PLAN D3. The claim on stage: *a proposer submits a schedule; the shield refuses the
unsafe parts with reason codes; the accepted parts are hashed into the verdict.* This file is
the exact sequence that produces that evidence, each step with the query that proves it. Every
number quoted from a demo run carries the run id.

**Preconditions (do not skip):** 0259 and 0260 applied (both `PENDING` until the round-39
window; `pg_stat_activity` clear, no `r<NN>_*` jobs scheduled), CI green on the head, and the
last certification round judged. Never start a demo run while a certification pair is scheduled:
`ottoq_sim_run_scenario` supersedes any running run on the depot.

## 1. Start a demo run, slow enough for an out-of-process proposer

```sql
SELECT public.ottoq_sim_run_scenario('busy_day', 424242, 'proposer_demo') AS run_id;
-- <run> below is the returned uuid
SELECT ottoq_policy_set('run', '<run>', 'cuopt_propose_enabled',          0, 'd3_demo');  -- no NVIDIA; ledgered as policy_disabled
SELECT ottoq_policy_set('run', '<run>', 'proposer_hold_enabled',          1, 'd3_demo');  -- the one-tick hold GATE, for any holds_tick source (0259; key registered by 0262)
SELECT ottoq_policy_set('run', '<run>', 'cuopt_first_refusal_max_defers', 1, 'd3_demo');  -- the hold ARM: 0152 set the global tier to 0, so nothing is armed without this
SELECT ottoq_policy_set('run', '<run>', 'orchestrator_agent_enabled',     0, 'd3_demo');  -- keep the dial-writing agent out of the picture
-- READ EVERY RETURN. Each call answers {"ok": true, ...}; an {"ok": false, "error": "unknown_param"}
-- is a refusal, not a warning. The first demo run (af2def1b, 2026-09-13) issued the hold call,
-- got ok=false, and ran with the hold OFF -- 54 proposer rows submitted, zero heard (0262).
UPDATE ottoq_sim_runs SET payload = COALESCE(payload,'{}'::jsonb) || '{"speed_x": 0.05}'::jsonb
 WHERE sim_run_id = '<run>';  -- metronome: ~120 s per tick, decide every other tick
```

**Why the hold matters, measured (0262 / db/checks/0186 §1).** Without it the decide path assigns
every arriving vehicle in the tick it arrives, and a vehicle already waiting in staging carries a
booking the frame does not show and is never re-decided. An out-of-process proposer that runs
between ticks then sees only vehicles nobody will decide again, or free stalls the local heuristic
will take in the same tick it re-reads them: on run `af2def1b` fires 3 and 4 submitted 54 rows and
the shield saw none — 34 superseded, 20 left pending. With the hold, an unreserved arrival is held
out of the local cursor for one decide tick; target those (`--states arrived_at_gate`).

`run_by='proposer_demo'` is deliberately not `cert_harness`: Posture A (0241) refuses
uncertified proposers into certification arms, which is correct, and this run is not one.

## 2. The proposer loop (between ticks)

CP-SAT, from a machine with a DSN (`bridge/README.md`):

```bash
python3 -m bridge.proposer_bridge --dsn "$DATABASE_URL" --run <run> \
  --depot 11111111-1111-1111-1111-111111111111 --site bridge/sites/nashville-flagship.json \
  --via batch --max-assets 8 --loop --interval-s 30 --start-within 30 --default-ready-delta 240 \
  --states arrived_at_gate
```

`--start-within` is the tick window: rows the plan starts later than that are submitted as
`bridge:not_due` abstains and re-offered when due, so a stall planned twice over time is never
offered twice in one tick (a refusal that would be the bridge's, not the shield's). Every refusal
counted in §3 must therefore carry a rule code, not a stall-already-taken from a stale plan.

Or, without a DSN (this is how the first proof is run from the build session): per cycle,
`SELECT ottoq_build_decision_frame(depot, run)` → `frame.json`; the committed
`SELECT_VEHICLE_CLASSES` → `classes.json`; `python3 -m bridge.proposer_bridge --frame ... --classes
... --via batch --emit-sql out.sql`; execute `out.sql`. One cycle must fit inside one decide
interval (~240 s at `speed_x 0.05`).

The LLM advisor, same loop shape, with a key on the runner and a cap:

```bash
python3 -m bridge.llm_proposer --run <run> --depot <depot> --frame frame.json \
  --model claude-opus-5 --cap-usd 2.00 --spend-file .spend.json --via batch --emit-sql out.sql
```

## 3. What to show, and the query that proves each line

**a. The proposer was heard and followed** — a `forward_lex` (or `llm_advisor`) row enacted:

```sql
SELECT p.source, p.status, count(*)
  FROM ottoq_external_proposals p WHERE p.sim_run_id = '<run>' GROUP BY 1,2 ORDER BY 1,2;
SELECT d.tick_seq, d.entity_id, d.outcome_status, d.proposed_action->>'source' AS src,
       d.enacted_action->>'verb' AS verb
  FROM ottoq_decisions d WHERE d.sim_run_id = '<run>' AND d.action_context = 'stall_assignment'
   AND d.proposed_action->>'source' IN ('forward_lex','llm_advisor') ORDER BY d.tick_seq;
```

**b. The shield refused the unsafe part, with a reason code** — a blocked decision naming rules:

```sql
SELECT d.tick_seq, d.entity_id, d.outcome_status, d.proposed_action->>'source' AS src,
       d.enacted_action->'blocked_by' AS rule_codes, d.enacted_action->'rule_rows' AS rows
  FROM ottoq_decisions d WHERE d.sim_run_id = '<run>' AND d.outcome_status <> 'enacted'
   AND d.proposed_action->>'source' IN ('forward_lex','llm_advisor') ORDER BY d.tick_seq;
```

(Column names for the block detail are whatever `ottoq_decide_tick` writes — read one row
first with `SELECT enacted_action FROM ottoq_decisions ... LIMIT 1` and quote that shape; do not
paraphrase a JSON key.)

**c. Every fire is on the ledger** (0260):

```sql
SELECT fire_id, status, tick_seq, n_rows, n_planned, n_abstained, n_submitted,
       solver->>'pass1_status' AS p1, solver->>'pass2_status' AS p2, solver->>'reproducible' AS repro,
       fire->>'usd' AS usd
  FROM ottoq_proposer_fire_log WHERE sim_run_id = '<run>' ORDER BY fire_id;
```

**d. Then certify it — Posture B** (0237/0239): capture the stream and replay it into both arms.

```sql
SELECT ottoq_proposal_replay_capture('<run>', '<replay_uuid>');       -- forward_lex/llm_advisor rows only (not certified → captured by default)
SELECT ottoq_determinism_pair_replay(424242, 12, 'busy_day',
         '11111111-1111-1111-1111-111111111111', '2026-09-01 02:00:00+00', 240, '<replay_uuid>');
```

Show `h_prop` non-trivial and identical across the arms, all fourteen atoms identical. Note the
caveat from `db/checks/0184` §2: this replay is faithful to the live run only because 0259
resolves precedence on the first sort key; before 0259 the same replay would have chosen
differently from the live run and still passed.

## 4. Stop and clean up

```sql
SELECT ottoq_sim_stop_and_reset('<run>', 'd3_demo complete');
```

The run's proposals, decisions and fire-log rows remain (evidence class); quote them by run id.

## 5. Status 2026-09-13 — two live runs, zero rows heard, and exactly why

Both runs are in the ledger; every number below has a run id and re-derives from
`db/checks/0186`. **The claim on stage is not yet shown.** What is shown is the machinery
doing its job against a blind proposer, and a precise list of what the proposer was blind to.

| run | hold | fires | rows submitted | rows naming a stall | heard by the shield |
|---|---|---|---|---|---|
| `af2def1b` (00:26–01:00 UTC) | OFF — `proposer_hold_enabled` refused by `ottoq_policy_set` (0262) | 3, 4 | 54 | 10 | **0** — 34 superseded, 20 pending |
| `ccf48af1` (01:17–01:36 UTC, ticked by hand) | ON — 32 arrivals held for one tick | 5, 6 | 36 | 13 | **0** — 29 superseded, 7 pending |

Six defects, found in order, each with its fix or its file:

1. **L-58** — the proposer read neither `stalls[].status` nor `stalls[].vehicle_id`; every stall
   in the frame was a point at t=0. Fixed in `proposer/forward_proposer.py` (occupied or held
   stalls are never offered; `n_stalls_busy` on the fire record).
2. **L-59** — `planned` counted abstain rows the solver emitted for vehicles it gave no charge.
   Fixed; `planned + abstained == rows`.
3. **0262** — the one-tick hold's gate key was read by 0259 but never registered, so the
   runbook's `policy_set` returned `unknown_param` and nothing read the return. Registered;
   the runbook now sets both keys (gate + `cuopt_first_refusal_max_defers`, whose global tier
   0152 set to 0) and reads every return.
4. **L-60** — a staged vehicle usually already holds a booking the frame does not show and is
   never re-decided; 'pending' on the door never meant 'awaiting the shield'. Bridge gains
   `--states` (narrow only); fire record carries `serviceable_states`.
5. **L-61 — the frame hides what decides.** With the hold ON, run 2 held 19 arrivals at tick 1
   and 6 more at tick 3, and the proposer named stalls for them on time. Every stall it named
   was, at disposal time, one of: reserved for another vehicle by the reservation optimizer
   (`stalls.reserved_by`, live), occupied by a vehicle the previous tick assigned and the world
   tick then plugged in, or — the single "free" stall at tick 3, `f99a8657` — behind a charger
   whose OCPP `station_state` was **Faulted**. `ottoq_build_decision_frame` carries none of
   those three facts (stall `status` read `available` on all of them), so the selector's
   pre-filter — which checks all three — returned NULL every time and the local heuristic
   disposed. Measured at tick 3: 31 charge stalls occupied, 7 free-but-reserved, 2 faulted,
   0 offerable. **Kernel fix (next migration, 0263):** the frame carries `reserved_by`,
   `reservation_expires_at`, the charger `station_state` per stall, and `reserved_stall_id`
   per vehicle. A proposer that cannot see a reservation cannot be heard at a depot that
   reserves every stall, and busy_day reserves every stall.
6. **L-62** — thirteen vehicles, one stall: the kernel raised `INFEASIBLE` and took the bridge
   down. Fixed: an infeasible frame is an `empty` fire with the solver's words in `error`;
   `--allow-rejection` lets it plan what fits and abstain, with a reason, on the rest.

**The design question 0263 does not answer, recorded so nobody thinks it does.** The hold
protects the *vehicle* for one tick; nothing protects the *stall* the proposer named.
Between the fire and the next decide, the reservation optimizer and the greedy optimizer run
first and may claim that stall for someone else (0259's `greedy_yields` is per vehicle, not
per stall). At a saturated depot that is the common case. Either a pending `holds_tick`
proposal also holds its stall for one tick, or the proposer is heard only when the depot has
slack. That is a change to the tick path and forces recert; it is a decision, not a patch.

**What did work, and is worth saying:** the hold engaged exactly as 0259 describes (32 held,
released next tick, no vehicle starved); every fire is a ledger row with its frame hash; the
door superseded, never lost, a row; and the shield never once had to refuse a bad row because
its pre-filter saw what the frame did not. That last sentence is the whole finding.

## 6. Status 2026-09-13 05:20 UTC — the design question is answered, and the answer got wider

**Chase answered it** (2026-09-13): *"I think the proposer comes in most handy or useful when
there is 'tightness' or contention within the depot. So it should be in the loop always."* So
the stall hold is to be built, and the proposer stays in the loop at a saturated depot rather
than being used only when there is slack.

**And then the kernel made the same point twice.** `db/checks/0188` root-caused G47 — a
*certified* proposer, `ottoq_service_priority`, with 2,335 proposals over fifteen days and zero
enactments. It is not a dead seat: `ottoq_decide_tick` line 965 asks it, 446 decisions name it
as the enacted action's source, and **all 446 carry `outcome_status = 'noop_no_candidate'`**,
set at line 1029 under the comment *"NO BAY -> DO NOT ENTER ONE"*. The flagship depot has **two**
service bays and they are taken — 1,725 bookings in three days — booked by the bay loop §(4b),
which runs **earlier in the same tick** than §(5) where the proposer is asked.

That is L-60's defect on a different resource, and it settles a design question 0264 was about
to get wrong:

> **Under contention the proposer is exactly who loses, because it is asked last.** So the
> one-tick hold must be **resource-generic** — a pending proposal protects the resource it
> names, whether that resource is a charge stall or a service bay — not a stall-specific patch.

### What is in flight

| item | state |
|---|---|
| `0263` the frame carries `reserved_by` / `reservation_expires_at` / `station_state` / per-vehicle reservation | designed by workflow, under adversarial review; **not applied** |
| `0264` a pending `holds_tick` proposal holds the resource it names for one tick, behind a run-scoped key defaulting to 0 | designed by workflow, under adversarial review; **not applied** |
| G46 (`db/checks/0187`) the canon rebases when another run's leftover legs move | designed by a second workflow; **round 42 is blocked on it** |
| the runner | `.github/workflows/proposer-loop.yml` — manual dispatch, needs repository secrets `OTTOQ_DATABASE_URL` and (for the advisory fire) `ANTHROPIC_API_KEY`, neither of which exists yet |

One measurement discipline was added tonight and applies to every future demo: **run
`db/checks/0189` afterwards.** It separates the two kinds of zero — `NEVER HEARD` (the door took
the proposal and the selector refused it, which is what happened to all 90 `forward_lex` rows)
from `ASKED AND NEVER FOLLOWED` (the selector returned it and physical reality overruled it,
which is what happens to every `ottoq_service_priority` row). Conflating them is what made the
first two runs look like one problem when they were two.

### Two rules for the next live run

1. **Not on the grid depot.** `grid_smoke/239001/6t` and `grid_smoke/424242/6t` are the only two
   certification columns still green (streak 3). Until G46 is fixed, a demo run on that depot
   can rebase their canon exactly as last night's flagship runs rebased six flagship columns —
   without the engine changing at all. Flagship is the safe place to demo precisely because its
   canon is already due to be reset.
2. **The bridge now refuses to collide with a certification.** Before every fire it asks
   `pg_stat_activity` whether `ottoq_determinism_pair` or `ottoq_ab_pair` is in flight (a pair
   runs both arms in one transaction, so its rows are invisible until commit — the process list
   is the only authority), and `--run auto` refuses a run whose `run_by` is `cert_harness`. In
   loop mode an in-flight pair is a logged skip, capped at thirty in a row; fired once, it is a
   refusal. So the old "never start a demo run overlapping a round" rule is now enforced in code
   as well as written down here.
