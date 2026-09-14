# RUNBOOK.md — Run 2 (CORE) Operations Guide

**Run 2, Phase C6 deliverable** (2026-08-19), covering everything Run 2 added: the C3 service
objects, the C4 solver capture + prototype, the C5 policy spine, and the C6 KPI machinery.
The one-line contract this book serves: **every claim traces to a run ID, every completed
operation ends in a ServiceDetailRecord, and the kernel never learns what sector it is in.**

---

## 1. What landed where

| Artifact | Path | Phase |
|---|---|---|
| Schema V2 (service objects, SDR rule) | `SCHEMA_V2.md`, `db/migrations/0043_…`, `db/checks/0043_…` | C3 |
| Solver truth + decide-path capture | `SOLVER_STATE.md`, `db/fn_current/` (19 live fns, md5-stamped) | C4 |
| CP-SAT prototype | `solvers/cpsat/` (`model.py`, scenarios, tests, committed plan) | C4 |
| Policy spine + comparison | `policies/` (interface, harness, tests, committed comparison) | C5 |
| Five KPIs + reproducibility key | `db/migrations/0044_…`, `db/checks/0044_…` | C6 |
| CLI + regression gate + CI | `metrics/kpi_cli.py`, `metrics/kpi_gate.py`, `metrics/baseline_24h_…json`, `.github/workflows/verify.yml` | C6 |

## 2. The one command: run ID in → five KPIs out

```bash
export OTTOQ_DB_URL="postgres://…"        # or PG* env vars
python3 metrics/kpi_cli.py <sim_run_id>
```

Deterministic by construction: `public.ottoq_kpi_five(uuid)` (migration 0044) is pure SQL over
committed views — no clock reads, stable ordering, sorted-key JSON out. The same run ID always
produces the same bytes (proved on scratch: two calls, `diff` clean). The output embeds the
**reproducibility key** `(policy_name, pack_id, scenario_seed, config_hash)` from
`ottoq_run_archives` — stamp it at run end with
`SELECT ottoq_run_archive_stamp('<run>', '<pack>', '<config jsonb>');`.

KPI definitions (and their stated biases) live as COMMENTs on the five views:
`ottoq_kpi_asset_hours_available_per_day`, `ottoq_kpi_service_point_turns`,
`ottoq_kpi_peak_site_kw` (15-min rolling grid import — recomputed from raw snapshots, never
trusting a derived column), `ottoq_kpi_touch_events_per_turn`, `ottoq_kpi_p95_time_to_service`.

## 3. The batteries (run these before trusting anything)

```bash
python3 solvers/cpsat/test_cpsat_prototype.py   # T1–T8: determinism, cooldown, power, retention
python3 policies/test_policies.py               # P1–P5: validity, CRN, byte-for-byte, parked stub
python3 metrics/kpi_gate.py                     # 24h seeded comparison vs committed baseline
# DB batteries (read-only Part A safe anywhere; live-fire Part B scratch-only):
psql -f db/checks/0043_schema_v2_certification.sql
psql -f db/checks/0044_kpi_certification.sql
```

CI (`.github/workflows/verify.yml`) runs the three Python batteries on every push/PR — no
secrets, no database. **The gate fires:** proved 2026-08-19 —

```
$ python3 metrics/kpi_gate.py                   # exit 0
KPI GATE: PASS (byte-identical to baseline)
$ python3 metrics/kpi_gate.py --demo-regression # exit 1
FAIL  cpsat  total_tardy_min  baseline=239 candidate=304 delta=+65 allowed=+15
KPI GATE: FAILED — 1 regression(s) beyond threshold
```

Rebaselining (`--rebaseline`) is a deliberate act: do it only in a PR whose description says why
the numbers moved, never to make CI green.

## 4. The scratch instance (how Run 2 verified DB changes)

Supabase preview branches cannot replay this project's migration history (`MIGRATIONS_FAILED`),
so the scratch branch is a local PostgreSQL 16:

```bash
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/scratch/data -U postgres -A trust"
su postgres -c "…/pg_ctl -D /var/lib/postgresql/scratch/data -o '-p 5433 -c unix_socket_directories=/var/lib/postgresql/scratch' start"
# load: extensions (pgcrypto, uuid-ossp, btree_gist) → live enum DDL → the needed
# db/baseline/ table sections → the 0022-era engine FKs + live purge/check fns +
# signing fns → the v3 EXCLUDE constraint → seed → apply 0043, 0044 → batteries.
```

Full recipe and results: `SCHEMA_V2.md` §6 (0043: A1–A7 + live-fire B1–B6 all PASS) and
`db/checks/0044_kpi_certification.sql` (K1–K4 PASS). Live-fire arming:
`SELECT set_config('ottoq.cert_livefire','on',false);` — **never on production**.

## 5. Applying 0043 / 0044 to production (post-merge, per scripts/APPLYING.md)

1. Apply **0043 then 0044**, from the merged files, `--project-ref gxdrcyphqjzjsuhxuqtg`
   (both use `$fn$`-quoting; the MCP runner's `$$` bug does not bite). Pause the run first if
   the tick engine is busy (house rule for anything near 15 s; the 0043 capability seed is the
   only sizeable write).
2. Run the read-only batteries (0043 Part A; 0044 K1–K4) — expect all PASS.
3. Add the two `MIGRATION_LOG.md` rows in the same PR; run `scripts/gen-drift-sql.sh` (0043 and
   0044 carry proper `migration-version:` headers — note the pre-existing gap: 0026–0042 mostly
   do not; backfilling those headers is separate, flagged work).
4. Nothing consumes the new objects yet (no cockpit or edge function reads SDRs or KPI views
   today), so the apply is behaviorally invisible except for SDR emission on completions.

## 6. Standing facts Run 3 should know (found and recorded during Run 2)

- **`ottoq_ab_runs` is empty** and all 145 archives are `policy='otto_q'` — the first C8
  comparison run under the wrapped policies becomes the first citable baseline of the new era
  (`SOLVER_STATE.md` §4).
- **The cuOpt deferral pattern is live** (0032's removal was superseded by 0040); the honest
  ledger sentence is in `SOLVER_STATE.md` §1 — use it verbatim in decks.
- **Run policy is a first-class run attribute** (`ottoq_sim_runs.policy`, read by the
  metronome) — C5's `AssignmentPolicy` names map onto it; `waymo_staging` stays PARKED
  (US 12,545,288 B2).
- **cron job 17 `ottoq-run-governor`** exists live but is documented nowhere else — it is the
  stall_watchdog descendant (`db/fn_current/public.ottoq_run_governor_auto_stop.sql`).
- KPI-4's human-actor enumeration is temporary until C7's canonical `touch_event` type lands.
- The scratch cluster survives on this container at `/var/lib/postgresql/scratch` (port 5433)
  with the full 0043+0044 state loaded — reusable for C7 twin work until the container dies.

---

## 7. The agent layer: record a stream, replay it, certify against it

*Added 2026-09-08. This is Posture B (SOLVER_STATE.md §8.2) and it is the thing the
certification harness could not do before tonight. Proof: `db/checks/0157`.*

### What the three pieces are

| | |
|---|---|
| `ottoq_proposal_replay_capture(run, replay_id [, sources])` | records a run's external proposal stream, keyed `(replay_id, tick_seq)` |
| `ottoq_proposal_replay_inject(run, replay_id, tick)` | puts one tick's worth back |
| `ottoq_determinism_pair_replay(seed, ticks, scenario, depot, sim_start, budget, replay_id)` | `ottoq_determinism_pair` plus injection, tick for tick, into **both** arms |

### The recipe

```sql
-- 1. record. From 0242 onward the DEFAULT skips the proposers that regenerate
--    (ottoq_certified_proposers) -- replaying those would double them, because
--    they also regenerate themselves during the replayed arm. See db/checks/0159.
SELECT public.ottoq_proposal_replay_capture(
         '<source run>'::uuid, '<replay id>'::uuid);

-- 2. certify against it. Same key as any pair, plus the stream.
SELECT public.ottoq_determinism_pair_replay(
         p_seed       => 239001,
         p_ticks      => 6,
         p_scenario   => 'grid_smoke',
         p_depot      => 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid,
         p_sim_start  => '2026-09-01 02:00:00+00'::timestamptz,
         p_arm_budget_s => 120,
         p_replay_id  => '<replay id>'::uuid);
```

The verdict gains three things: `replay` (which stream it ran against — a verdict that
does not name its stream is not reproducible), and per arm `replay_injected` and
`foreign_proposals`. **Both of those are MEASURED, not ENFORCED** (CLAUDE.md §2.9a) —
they are not in the fourteen-atom equality list, and their promotion gates are written
in 0239 and 0241 respectively.

### How to read the result

* **`h_prop` equal across arms** is the claim. It hashes proposal *status*, and
  `ottoq_decide_tick` closes each proposal to enacted / superseded / expired at end of
  tick — so equality means *the disposer did the same thing with the stream*, not merely
  that the same rows went in.
* **`h_prop` sensitive, `h_dec` not** means the perturbed proposal was never read.
  That is not a bug in either atom: `h_prop` is what the agent *said*, `h_dec` is what
  the agent *changed*. 0157 P3 and P4 are exactly this contrast.
* **`h_prop = d41d8cd98f00b204e9800998ecf8427e`** is md5 of the empty string: the run saw
  no proposals at all. Expected for a plain certification, because 0152 and 0105 quiesce
  the producers. If you get it from a *replay* pair, the injection did not happen.

### Three ways to get a wrong answer that looks right

1. **Replaying a stream captured on another depot.** The entity ids match no vehicle, the
   selector finds nothing, and the pair passes over an empty experiment. `0239` refuses
   this before either arm is created — but only for the depot; a stream from a different
   *scenario* on the same depot is still your problem.
2. **A legacy stream.** Capture stores `COALESCE(tick_seq, -1)`, so anything recorded
   before migration 0236 lands entirely in the −1 bucket. The arm injects that bucket once
   at run start so it is presented rather than silently dropped, but it is not the original
   timing and should not be described as one.
3. **Capturing the internal proposers.** Fixed by 0242 and it is worth knowing why: they
   regenerate identically from the seed during the replayed arm, so replaying them too puts
   the same proposal in twice — the ghost at tick −1, visible from before tick 1 and
   selectable in preference to the real one. `db/checks/0159`.

### What a certification will refuse

From migration 0241, a live proposer that is not in `ottoq_certified_proposers` is refused
at the door with `OTTOQ_PROPOSAL_REFUSED_CERT` when the target run is `run_by='cert_harness'`.
A **replay is not affected** — `ottoq_proposal_replay_inject` writes the table directly and
never passes through that door. That asymmetry is the design: a recorded stream is the only
stream a certification is allowed to hear.

To let a genuinely new proposer into a certification, register it — deliberately, with a
note saying why:

```sql
INSERT INTO public.ottoq_certified_proposers (source, note)
VALUES ('<source>', '<why this proposer belongs in a certification>');
```

Be aware this has a second effect, by design: `ottoq_proposal_replay_capture` will then skip
it by default, on the grounds that a certified proposer is one that regenerates.

### A fourth way to get a wrong answer that looks right, found 2026-09-09

**A pair can fail for a reason that has nothing to do with the replay.** The first
flagship-scale replay pair came back `failed` with exactly one atom moved (`h_evt`)
on one arm, and the cause was not the replay: seven vehicles were carrying live
`robotic_tether_*` state when arm A booted, arm B inherited the world arm A left,
and the two arms therefore ran different worlds. See `db/checks/0160` (G43).

Neither `ottoq_tick_invariance_reset_fleet` nor `ottoq.ottoq_world_fingerprint`
knew those four columns existed, so `fp` — the enforced atom whose job is "both
arms started from the same world" — reported them identical. Migration `0243`
closes both halves.

**Practical rule while running any pair by hand, replay or not:** do not start one
within a minute or two of touching the depot from a client session. If a pair fails
on `h_evt` alone, check the fleet before blaming the change under test:

```sql
SELECT count(*) FILTER (WHERE robotic_tether_phase IS NOT NULL) AS mid_tether,
       max(updated_at) AS last_write
  FROM public.vehicles WHERE home_depot_id = '<depot>';
```

A `last_write` that predates your pair's transaction, on rows the reset does not
own, is the signature.
