# The research lab, E1 — acceptance, 2026-11-04

**Chase, 2026-11-04: "Begin frontier build step 1".** Step 1 is Phase 0, item 1 of `docs/FRONTIER_PLAN_2026-11-03.md`:
the lab (E1). The session had the Supabase access token D2(a) asked for (environment name `Supabase_Key`), so the lab
is now loaded from what production ran, not from the repository's files (G509). Times are US Central (CST, UTC−6, on
this date), with UTC beside them where the ledgers keep UTC. Nothing was written to production's engine; the results
were published to the twin's Research tab (`public.ottoq_research_findings`, which nothing in the engine reads) at
5:48 PM CT, as Phase 0's were (`lab/research/findings/P0.sql`).

## The answer

- **The lab is production's engine.** Production's catalog was exported through the Management API's read-only
  endpoint and loaded into PostgreSQL 17: 14,388 of 14,388 statements. Object by object, every routine (1,037), table
  (453), trigger (236), index (889), policy (210), RLS switch, type, sequence, comment, ACL (1,693), default ACL, cron
  job (24) and the migration ledger's 1,337 versions are identical to production's. Six objects differ only as
  semantically identical deparse round-trips.
- **The lab holds production's world at the twin depot.** 90 tables, 9,278 rows. The engine's own world fingerprint
  for the depot is `3f2aa2ac…` in the lab, in production at export time, and in production read again at 5:13 PM CT.
- **A pair in the lab: 13 of 14 atoms, and the 14th is an engine defect, not a lab defect (G510).** Over 12 ticks and
  over a full depot-day (48), two identical arms differ in one place only: an itinerary-leg id that 0764 mints for the
  post's cleaning arm, which the end-state hash includes. With that id set aside (`0794`, PENDING, applied in lab
  replicas only), both pairs pass 14 of 14.
- **Forks work.** An unchanged branch reproduces its trunk on every per-tick digest and on 13 of 14 atoms (14 of 14
  with `0794`). A branch that changes one decision rule at tick 6 first differs at tick 7, with the same arrivals.
- **Throughput: one depot-day in 173 seconds on one stream, 20.8 depot-days an hour; 54.6 an hour on four replicas**
  (4 vCPUs). A pair is slower than its two arms: both arms share one transaction, and the second arm pays for it.
- **Not measured:** whether a lab arm reproduces a production run's digests. No pair has run in production on this
  engine (the newest is 2026-10-14; rule 12 turned certification off on 2026-10-20), and the one production run on
  this engine is a live demo run, which an unpaced arm cannot reproduce without replaying its clock and its agent.

## When each thing was read

| what | UTC | US Central |
|---|---|---|
| production's catalog (schema export, 20 reads) | 21:43:40–21:43:47 | 3:43 PM |
| production's reference data and world fingerprint (before, after) | 22:00:45, 22:01:11 | 4:00–4:01 PM |
| the lab built for every run below (`lab.build_info.built_at`) | 22:57:37 | 4:57 PM |
| throughput | 22:58:01–23:05:22 | 4:58–5:05 PM |
| the 12-tick pairs (two replicas) | 23:05:27–23:13:47 | 5:05–5:13 PM |
| production's world fingerprint read again | 23:13:47 | 5:13 PM |
| the 48-tick pairs (two replicas, alongside the 12-tick pairs) | 23:05:27–23:33:00 | 5:05–5:33 PM |
| the fork tests (the `0794` replica, then the lab) | 23:33:01–23:40:37 | 5:33–5:40 PM |
| the second-arm experiment | 23:40:44–23:44:51 | 5:40–5:44 PM |
| object-by-object census, lab and production | 23:45:09, 23:45:10 | 5:45 PM |

## 1. Fidelity

### 1a. Objects

`lib/fidelity_full.py` runs the 2026-11-03 census (`sql/fidelity_objects.sql`, so the numbers are comparable with
`fidelity_2026-11-03.md`) and `sql/fidelity_extra.sql` on both sides and compares them here (`fidelity_2026-11-04_prod/`):

| kind | production | identical | differ |
|---|---:|---:|---:|
| routines | 1,037 | 1,037 | 0 |
| tables | 453 | 453 | 0 |
| views | 90 | 87 | 3 |
| constraints | 1,157 | 1,154 | 3 |
| indexes | 889 | 889 | 0 |
| triggers | 236 | 236 | 0 |
| policies | 210 | 210 | 0 |
| RLS switches | 453 | 453 | 0 |
| types | 30 | 30 | 0 |
| sequences | 80 | 80 | 0 |
| comments | 646 | 646 | 0 |
| ACLs (tables, columns, functions, schemas, types) | 1,693 | 1,693 | 0 |
| default ACLs | 18 | 18 | 0 |
| cron jobs (schedule, command, name, user, database) | 24 | 24 | 0 |
| the ledger's versions (= `ottoq_engine_hash()`, `aae920a7…`) | 1 | 1 | 0 |

On 2026-11-03 the repository build matched 300 routines and 177 tables. Production's catalog read the same at 5:45 PM
as at 3:43 PM: nothing changed it in between.

The six that differ re-parse to a different tree than production stores, with the same meaning, as `pg_dump` output
does: three CHECKs (`ottoq_agent_principals_display_name_check`, `ottoq_oauth_clients_name_check`,
`ottoq_owner_settings_charge_limit_check`) whose nested AND, born of `BETWEEN`, flattens; three views
(`ottoq_kpi_service_point_turns`, `ottoq_kpi_touch_events_per_turn`, `ottoq_margin_ledger`) whose second `UNION`
branch's column name, which nothing reads, re-derives as `text`.

### 1b. The world

The twin depot's world fingerprint (`ottoq.ottoq_world_fingerprint_sections`: vehicles, stalls, chargers, need
profiles, BESS), the engine's own hash:

| where | combined | read |
|---|---|---|
| production, before and after the data was read | `3f2aa2ac0bcc532e35f36c8bc257ff0e` | 4:00 PM, 4:01 PM |
| the lab | `3f2aa2ac0bcc532e35f36c8bc257ff0e` | after each build |
| production, again | `3f2aa2ac0bcc532e35f36c8bc257ff0e` | 5:13 PM |

All five sections agree as well. Production's body of the function was run through the read-only endpoint (that role
cannot execute it); the lab called its copy, which is byte-identical.

### 1c. The pair

`public.ottoq_determinism_pair(171717, ticks, 'busy_day', twin depot, '2026-09-01 02:00+00')`, the engine's own
instrument, unmodified, both arms in one transaction as in production, each in its own replica of the lab:

| ticks | engine | outcome | atoms agreeing | end state | robot_leg_ids per arm | pair wall time |
|---:|---|---|---:|---|---:|---:|
| 12 | production's | **failed** | 13 of 14 | differs in `visit_needs` only | 90 | 498 s |
| 12 | production's + `0794` | **passed** | 14 of 14 | equal | 90 | 498 s |
| 48 | production's | **failed** | 13 of 14 | differs in `visit_needs` only | 154 | 1,653 s |
| 48 | production's + `0794` | **passed** | 14 of 14 | equal | 154 | 1,651 s |

(The four ran at once on 4 vCPUs.) In each failed pair `visit_needs` differs in one column, `atoms`, and in one key of
it, `robot_leg_id`, one per visit whose cabin the post's arm cleaned, none shared between the arms. Remove that key and
no visit need differs (12 ticks: 0 of 116). Every other atom agrees, and on both engines alike.

**And it reproduces across everything the lab varied.** Sixteen runs of the 12-tick cell carry the same 13 digests
(events `86543fcc`, decisions `fcf0630f`, commands `7f477766`, …): pairs and fork trunks and replays, before and
after this evening's fixes to the lab, on production's engine and with `0794`, in three builds and eight databases.
Eight more arms (§3b) carry the same events digest, in separate and in shared transactions.

Why production would read the same, and why nobody has seen it (`db/checks/0477` §4):

- 0764 writes `robot_leg_id` at `stall_cabin_robot` 2; the twin depot has run at 2 since 2026-10-23 14:19:53 UTC
  (Chase).
- 0764 was classified `forces_recert` FALSE because "at 0 and 1 the starter and the completion step decide exactly as
  before". True, and the depot that holds the canon went to 2 the same day.
- Production's newest pair verdict is 2026-10-14 15:09 UTC, under engine hash `9b561d56…`; today's is `aae920a7…`.

The fix, `db/migrations/0794` (PENDING): `ottoq_boot_state_fingerprint` sets an atom's `robot_leg_id` aside before
hashing a visit need, as it already sets aside the row's own ids and the minted ids of bookings, legs and dispatches.
Rows without the key hash exactly as before. It changes what a pair measures, not what the depot does; it
`forces_recert`, and under rule 12 nothing acts on that until testing resumes. A person ships it (rule 10).

### 1d. A production run's digests

Not measurable today. The plan's criterion compares a lab arm with a surviving production run "for the same scenario,
seed and ticks". The newest production pair is on another engine, and the newest production run on this engine
(`edf611ad`, a 74-tick `busy_day` demo started 9:14 AM CT today) is live: each tick's sim length is real elapsed time
(`ottoq_sim_advance_tick_world`'s `playback_mode = 'live'`), and the agent's orders arrive asynchronously. To
reproduce it the lab would set each tick's length from production's tick clock log and inject the agent's recorded
orders at the ticks they landed. That is the next fidelity step; it is not built.

## 2. Forks

`acceptance/forks.py`: one arm of 12 ticks, a savepoint at tick 6, three branches run from it in turn and rolled back
(the transaction is rolled back at the end, so the lab keeps nothing):

| branch | what changes at the fork | against the trunk, production's engine | with `0794` |
|---|---|---|---|
| replay | nothing | every per-tick digest (events, decisions, commands) equal for all 12 ticks; 13 of 14 atoms; the end state differs only in `robot_leg_id` (G510) | **14 of 14**, every per-tick digest equal |
| changed | `charge_order_minutes = 0` at run scope (0642's charge-line key switched back to the order before it) | first differs at **tick 7**; by tick 12 commands, decisions, events, bookings, energy, proposals, rules, recalls and SDRs differ; **arrivals equal** | the same |

So the difference between two branches is the decision's own effect, under the twin's world: the world's draws are
keyed on seed, entity and time, not on sequence (C5 correction), and the arrival stream did not move.

Two things do not roll back: sequences (a later branch's ids are higher) and `gen_random_uuid()`. Thirteen atoms are
blind to both. The end state is not, which is G510.

## 3. Throughput

### 3a. Arms

`acceptance/throughput.py`. A depot-day is one certification arm of 48 ticks at 30 sim-minutes each, unpaced, on
4 vCPUs:

| | wall time | sim-hours per wall-hour | depot-days per wall-hour |
|---|---:|---:|---:|
| one stream (the lab database) | 172.7 s | 500 | **20.8** |
| four replicas at once | 263.6 s for all four | 1,311 | **54.6** |

A replica is made in 0.4–0.8 s (`CREATE DATABASE … TEMPLATE` plus its settings). In parallel each arm's median tick
was 4.1–4.8 s against 3.6 s alone, so four replicas give 2.6 times one stream. Ticks are not uniform: in the single
stream the day's first ticks took 4–7 s and its last 2–4 s.

For scale: G141 measured a paired test blocking every production cron job for its whole duration (a 13.6% cron outage
over seven days in September). In the lab a pair blocks nothing, and a depot-day costs about three minutes of one
core.

### 3b. Why a pair costs more than its two arms

A 48-tick pair took 1,651 s; two 48-tick arms take about 2 × 173 s. Inside a pair the second arm is the slow one (the
engine's tick log, 12-tick pair: arm A 101 s, arm B 365 s, with other pairs running). Two arms of 12 ticks, run back
to back on an idle machine (`e1_acceptance_2026-11-04/second_arm.py`):

| | arm 1 | arm 2 |
|---|---:|---:|
| each arm in its own transaction (arm 2 after arm 1 committed, its rows still there) | 51.0 s | 49.6 s |
| both arms in one transaction, as `ottoq_determinism_pair` runs them | 57.1 s | **87.3 s** |

So the cost is the shared transaction, not the first arm's rows. The likely mechanism is that row versions a still-open
transaction wrote cannot be pruned, so every later read walks them; that is inferred, not measured. Production runs
its pairs the same way, so it should pay the same. What it means for the lab: E6's search runs each arm in its own
transaction or replica, and a pair is reserved for certifying a result.

## 4. What the lab had to change about itself on the way

- **No job scheduler.** The first throughput run failed: `CREATE DATABASE … TEMPLATE ottoq_lab` refused because
  pg_cron's scheduler holds a session open in the lab database, even with `cron.launch_active_jobs = off`. Replicas
  and long forks need that statement, so the server no longer loads pg_cron; `sql/12_cron_standin.sql` holds
  pg_cron 1.6's tables (production's 24 jobs, inactive) and the functions the engine and the migrations call, with
  nothing behind them to run a job. The repository build's outcome is unchanged on every file it shared with
  2026-11-03's.
- **Production's settings, server-wide.** The first replicas ran with `jit` on, `extra_float_digits` 1 and no
  `extensions` on the search path: `CREATE DATABASE … TEMPLATE` does not copy database-level settings. Their digests
  happened to agree, but their timing did not (four replicas: 36.6 depot-days an hour, against 54.6 with the settings
  right). Production sets these in its configuration file; the lab now does the same, and `clone_database()` copies
  database-level settings too. Every number in this report is from runs after the fix.
- **The calibration atom.** `ottoq_ab_arm_atoms` leaves out the pair's calibration atom (`h_cal`, taken from the boot
  image); the driver's first comparison treated that as `None = None`. The driver now adds it as the pair does and
  refuses a digest with a missing atom.

## 5. What was not verified

- That production's own pair fails as the lab's does: inferred from identical code and dial; not run (rule 12, and
  the lab never writes production).
- A production run reproduced by a lab arm (§1d).
- Forks longer than one transaction (a replica per branch): the mechanism is the replica of §3; no fork test used it.
- The agent and the solvers: off in the lab (no outbound HTTP; cuOpt quiesced at run scope as in every certification
  arm). Replaying their recorded calls is not built.
- Two inactive fleet build-outs (`fleet150`, `fleet200`) borrow 34 and 84 cars from the Benchmark depot, whose cars
  are not copied; they cannot be switched on in the lab as it stands.
- How much the lab ran: about 24 simulated depot-days, all inside the lab, none in production. That is more than the
  "few simulated days" Chase's go-ahead for building the lab named (Phase 0, 2026-11-03), mostly because the throughput
  test runs five depot-days each time and ran three times while the lab's settings were being fixed. Unattended runs
  at research scale still wait for D3.

## Evidence (`e1_acceptance_2026-11-04/`)

| file | what |
|---|---|
| `fidelity_f12.json`, `fidelity_p12.json` | the 12-tick pairs: verdict, atoms, end-state diagnosis, world fingerprints (lab, export, production at 5:13 PM) |
| `fidelity_f48.json`, `fidelity_p48.json` | the 48-tick pairs |
| `forks.json`, `forks_0794.json` | the fork test on production's engine and on the `0794` replica, with every branch's digests per tick |
| `throughput.json` | per-tick wall times of every arm |
| `second_arm.py`, `second_arm.json` | §3b's experiment and its result |
