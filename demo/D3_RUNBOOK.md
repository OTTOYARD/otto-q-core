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
SELECT ottoq_policy_set('run', '<run>', 'cuopt_propose_enabled',     0, 'd3_demo');  -- no NVIDIA; ledgered as policy_disabled
SELECT ottoq_policy_set('run', '<run>', 'proposer_hold_enabled',     1, 'd3_demo');  -- the one-tick hold, for any holds_tick source (0259)
SELECT ottoq_policy_set('run', '<run>', 'orchestrator_agent_enabled',0, 'd3_demo');  -- keep the dial-writing agent out of the picture
UPDATE ottoq_sim_runs SET payload = COALESCE(payload,'{}'::jsonb) || '{"speed_x": 0.05}'::jsonb
 WHERE sim_run_id = '<run>';  -- metronome: ~120 s per tick, decide every other tick
```

`run_by='proposer_demo'` is deliberately not `cert_harness`: Posture A (0241) refuses
uncertified proposers into certification arms, which is correct, and this run is not one.

## 2. The proposer loop (between ticks)

CP-SAT, from a machine with a DSN (`bridge/README.md`):

```bash
python3 -m bridge.proposer_bridge --dsn "$DATABASE_URL" --run <run> \
  --depot 11111111-1111-1111-1111-111111111111 --site bridge/sites/nashville-flagship.json \
  --via batch --max-assets 8 --loop --interval-s 30 --start-within 30 --default-ready-delta 240
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
