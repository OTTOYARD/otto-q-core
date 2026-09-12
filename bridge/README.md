# bridge/ — the CP-SAT proposer's database client

**What it closes.** BUILD_QUEUE #4: the objective function exists (`intent/`, `policies/regime.py`,
`solvers/cpsat/model.py`, `proposer/forward_proposer.py`) and was wired to nothing. `proposer/`
is a kernel package and may not hold a database client (`tests/test_separation.py`), so the one
line its README called "founder-gated" — *insert the rows* — had no home. This is the home, and
it is deliberately **not** a kernel package: the guard bans `import bridge` from the kernel
exactly as it bans `psycopg`, so the proposer can never learn it has a channel.

```
ottoq_build_decision_frame(depot, run) ──▶ proposer.propose() ──▶ rows ──▶ ottoq_submit_external_proposal
        (read, verbatim)                    (pure, CP-SAT,               (THE door: server-derived identity,
                                             det-time bounded)            Posture A, supersede, tick stamp)
                                                                                    │
                                                                        ottoq_decide_tick DISPOSES
```

**Three laws, enforced by tests, not prose.**

1. It never `INSERT`s. `emit_sql()` produces `SELECT public.ottoq_submit_external_proposal(...)`
   statements and nothing else (`test_emit_sql_calls_the_door_once_per_row_and_never_inserts`).
2. Every fire is accounted for. `fire()` returns the fire record — frame hash, solver statuses,
   optima, `reproducible`, counts — whether it proposed, abstained, or had nothing to say.
   Migration 0260 gives that record a ledger (`ottoq_proposer_fire_log`) via
   `ottoq_proposer_submit_batch`, so "never invoked" / "invoked, empty" / "invoked, refused" /
   "invoked, submitted N" are four different ledger facts (CLAUDE.md rule 6, applied *before*
   the first claim rather than after).
3. It runs in CI with no database and no driver. The live half imports `psycopg` lazily and a
   missing driver is a named error, not an import crash.

## Use

Offline (auditable artifact; what CI exercises):

```bash
python3 -m bridge.proposer_bridge \
  --run <sim_run_id> --depot 11111111-1111-1111-1111-111111111111 \
  --site bridge/sites/nashville-flagship.json \
  --frame frame.json --classes classes.json \
  --emit-sql out.sql --json-out out.json [--max-assets 8] [--ttl 60] [--via door|batch]
```

`frame.json` is `SELECT ottoq_build_decision_frame(depot, run)`; `classes.json` is the rows of
`proposer.class_table.SELECT_VEHICLE_CLASSES`. `out.sql` is one door call per row (or one
`ottoq_proposer_submit_batch` call with `--via batch`, once 0260 is applied); the fire record is
on stderr and in `out.json`.

Live (a machine that holds a DSN; never this repository):

```bash
python3 -m bridge.proposer_bridge --dsn "$DATABASE_URL" \
  --run <sim_run_id> --depot <depot_id> --site bridge/sites/nashville-flagship.json \
  --via batch --max-assets 8 --loop --interval-s 10
```

Each fire is its own transaction, so the door's tick stamp (0236) names the tick the batch
landed in. The loop stops when the run is no longer `running`.

## Sizing (from proposer/README.md, measured)

| frame | `--max-assets` | wall |
|---|---|---|
| 44 vehicles / 16 stalls | unset | 97.9 s |
| 44 vehicles / 16 stalls | 12 | 14.0 s |
| 44 vehicles / 16 stalls | 8 | 7.6 s |

The metronome ticks a demo run every `6 s / speed_x` and decides on every second tick. A
proposer that must answer inside the one-tick right-of-first-refusal window passes
`--max-assets` and, for a demo, slows the run (`payload.speed_x`). The budget is deterministic
work (`det_budget_s`), never wall clock, so the plan is a function of the instance and not of
the box. Cost: none — CP-SAT is local, no endpoint, no tokens.

## Why the bridge alone changes nothing (read this before demoing)

`db/checks/0184`: today the decide path picks a pending proposal by
`ORDER BY (source='cuopt') DESC, (source='cuopt_fallback') DESC, created_at DESC`, and the
local greedy proposer regenerates its row *inside* the tick. A `forward_lex` row submitted
between ticks is therefore always older and always loses — heard, never followed. And the
one-tick hold binds only while `cuopt_propose_enabled >= 1` and releases only for cuOpt rows.
**Migration 0259** moves those literals into `ottoq_proposer_precedence` (seeded so nothing
historical moves — A2 recomputes 14,779 groups, 0 differ) and adds the `proposer_hold_enabled`
gate key. Apply 0259, then run the demo with:

```sql
SELECT ottoq_policy_set('run', <run>, 'cuopt_propose_enabled', 0, 'demo');   -- no NVIDIA
SELECT ottoq_policy_set('run', <run>, 'proposer_hold_enabled', 1, 'demo');   -- hold for us
```

Certification of this proposer is Posture B (0237/0239): capture a live run's `forward_lex`
stream, replay it into both arms of a pair, `h_prop` non-trivial, arms byte-identical. 0184 §2
explains why that replay is faithful only *after* 0259.

## Site file

`bridge/sites/nashville-flagship.json` declares the site parameters the kernel needs, each with
its provenance in `_provenance`: the two power figures come from the `depots` row (2500 kW
service, 1620 kW soft target derived from the DCFC concurrent cap and safety margin), the DCFC
cooldown is CLAUDE.md 2.5's 18 minutes (the SQL engine holds none, BUILD_QUEUE #5), and the
four movement/cold-start values are marked `ASSUMPTION` because no measured value exists for
this depot. The NES GSA-3 tariff has no time-of-use window, so `onpeak_window_min` is empty.
