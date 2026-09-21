-- 0298  TWO RESULTS. **(1) `0396` VERIFIED**: the clock keeps its exact value and the world now
--       agrees with it — dispatches born in the sim future go **45 -> 0**, and the world's own
--       start hour goes **8 -> 0** to match a clock that always said 00:35 Central. **(2) G96 IS
--       BLOCKED ON SOMETHING THAT IS NOT THE DWELL**: `ottoq_bess_units.current_state` writes
--       **`idle`** where `bess_snapshots.status` writes **`standby`**, from the same condition in the
--       same function, and the transition matrix knows only `standby`. **SM.006 cannot be wired
--       until the BESS has one word for rest.**
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
--
-- ══ 1. `0396` VERIFIED ON A ROLLED-BACK PROBE OF THE REAL PATH ═════════════
--
-- Method: `BEGIN; SELECT ottoq_sim_run_scenario('busy_day', 100020, 'operator_demo', <the clock
-- ottoq_start_demo_run now computes>); <inspect>; ROLLBACK;`. This exercises the function the fix
-- changed, against the clock the fix makes it receive, **without spending a run and without letting
-- `ottoq_purge_prior_runs` touch `c9b0a87e`** — whose figures `0296` §6 and `0297` still depend on.
-- (A first attempt ran the whole of `ottoq_start_demo_run` and hit the 120-second transport ceiling
-- on the purge; it rolled back cleanly, verified — no run created, `c9b0a87e`'s 87 dispatches intact.)
--
--   quantity                                  before (`c9b0a87e`)   after (`0396`)
--   `sim_clock_start`                         2026-09-20 05:35 UTC  **2026-09-20 05:35 UTC**
--   the same, in Central                      00:35                 00:35
--   `boot_prime.start_hour_cst`               **8**                 **0**
--   `boot_draw.need_profiles.sim_clock`       **13:00**             **05:35**
--   dispatch rows born AFTER the clock start  **45**                **0**
--   dispatch rows at or before the clock      **0**                 **all of them**
--   oldest primed trip, relative to the clock **-7h25m (future)**   **+13.9 min (past)**
--
-- **The clock did not move and the world moved to meet it — which is exactly the claim the
-- migration's `forces_recert` note makes, now measured rather than argued.** `+13.9 min` is what
-- "already mid-trip at t=0" is supposed to look like: the vehicle left fourteen minutes before the
-- run begins. `-7h25m` never could be.
--
-- **AND A CONSEQUENCE THAT IS A PRODUCT DECISION, NOT A DEFECT — FLAGGING IT RATHER THAN BURYING IT.**
-- `prime_fraction` falls **0.3960 -> 0.0135** and primed vehicles **45 -> 2**, because
-- `ottoq_deploy_target_fraction` is now asked about hour **0** instead of hour 8, and at half past
-- midnight almost no robotaxi should be out. That is physically right and it changes what a demo
-- looks like:
--   - **Before, every demo run looked like 8 a.m. regardless of the clock it displayed.** The
--     randomised start minute moved the clock and nothing else.
--   - **Now the seed sets the LOAD as well as the clock.** A seed drawing 03:00 gives a quiet run; one
--     drawing 08:00 gives a busy one. Between-seed variance in every KPI rises accordingly, and two
--     seeds are no longer comparable on volume — only within a seed, which is what CRN pairing was
--     always for.
--   - **It is not a wasted run.** The 540-minute governor carries 00:35 -> 09:35 Central, so the run
--     starts quiet and ramps through the morning peak rather than starting at it.
--   - **The open question for Chase, stated and not decided here:** for the one thing rule 8 says
--     this depot exists to answer — how many vehicles it can stage and orchestrate at once — a
--     randomised start hour is a strange instrument. Pinning the demo start to a chosen hour and
--     randomising something else would give a sharper measurement. That is a product call.

-- re-runnable: no primed dispatch may be born after the clock its run starts from
SELECT r.sim_clock_start,
       r.payload->'boot_prime'->>'start_hour_cst'                     AS world_built_for_hour_ct,
       r.payload->'boot_draw'->'need_profiles'->>'sim_clock'          AS need_profiles_drawn_at,
       count(d.*)                                                    AS dispatch_rows,
       count(d.*) FILTER (WHERE d.dispatched_at > r.sim_clock_start)  AS dispatched_in_the_future
  FROM public.ottoq_sim_runs r
  LEFT JOIN public.ottoq_vehicle_dispatches d ON d.sim_run_id = r.sim_run_id
 WHERE r.run_by = 'operator_demo'
 GROUP BY 1, 2, 3
 ORDER BY r.sim_clock_start DESC;

-- ══ 1b. AND THE RECERT FLOOR RESPONDED CORRECTLY, WHICH IS ITS OWN RESULT ═══
--
-- `0396` declared `forces_recert TRUE`. Measured immediately after: **all 9 enabled canon columns
-- read `NOT satisfies_floor`, and 0 are at floor** — so the classification was honoured rather than
-- merely written down, and `ottoq-recert-runner` (cron 746, minutely) is sweeping them one pair per
-- firing. Three pairs had already passed at seeds 424242 and 171717 in the same window.
--
-- **AND IT LOOKS LIKE A FREE SCHEDULING WINDOW. IT IS NARROWER THAN THAT, AND I GOT IT WRONG BY FIVE
-- COLUMNS — corrected here rather than left standing, because I will reuse this reasoning.** The
-- argument I wrote was: while all 9 columns are already below floor, a further `forces_recert TRUE`
-- costs nothing extra, so batch them here. **The sweep DRAINS CONCURRENTLY.** By the time `0397`
-- applied, the runner had cleared 5 of the 9, and `0397` put `awaiting_recert` straight back to 9 —
-- so it cost five re-certifications rather than zero. **The correct rule: batching is free only if the
-- changes land TOGETHER, before the sweep begins clearing — not merely "while the floor is broken."
-- A window that is draining is not a window.** Landing such changes one at a time later still means a
-- full 9-column sweep each, so batching remains right; it just has to be prompt.
-- This also explains a wait: the recert runner holds one of this instance's **6** worker processes
-- with `statement_timeout = 0` for a whole round, and it refuses to start while any run is
-- `running`/`paused`, so a demo run and a recert sweep are mutually exclusive by design. The
-- post-fix five-KPI run is therefore deferred until the sweep drains, and its cron job was
-- unscheduled rather than left armed.

SELECT count(*)                                            AS canon_columns,
       count(*) FILTER (WHERE enabled)                     AS enabled,
       count(*) FILTER (WHERE enabled AND NOT satisfies_floor) AS awaiting_recert,
       count(*) FILTER (WHERE enabled AND satisfies_floor)     AS at_floor
  FROM public.ottoq_determinism_canon;

-- ══ 2. G96 — SM.006 IS NOT BLOCKED BY THE DWELL. IT IS BLOCKED BY A WORD. ══
--
-- `0295` decided G96 as: keep the transition-matrix half, drop the dwell clause, wire the matrix at
-- `bess_state_change`. Going to wire it, three things turned up in order, each changing the plan.
--
-- **(a) The evaluator contains no dwell logic whatsoever.** `ottoq_eval_sm_006_bess_transition` is a
-- one-line delegate to `ottoq_eval_sm_transition_validity('bess', ...)`, which looks up
-- `(entity_kind, from_state, to_state)` in `ottoq_state_transitions`, then checks
-- `allowed_actor_types`. No timing, no minimum interval, no clock. **So the rule's description and
-- its code disagree**: the text promises "dwell-through-standby between charge and discharge" and the
-- code cannot measure dwell at all.
--
-- **(b) But the dwell IS enforced — as a MATRIX OMISSION, which is why (a) is not the whole story
-- and I am not leaving my first reading of it standing.** Of **17 active `bess` transitions**,
-- `charging -> discharging` and `discharging -> charging` number **ZERO**. The dwell is not a timer,
-- it is two rows that were never inserted. So wiring the rule as it stands *would* refuse the direct
-- flips `0285` measured — 3,426 of 23,730, 14.4% — exactly as `0295` feared, by a mechanism `0295`
-- did not name.
--
-- **(c) AND THE BLOCKER IS NEITHER OF THOSE. `twin.ottoq_sim_bess_step` WRITES TWO WORDS FOR THE
-- SAME STATE, IN ONE STATEMENT PAIR, FROM ONE CONDITION:**
--
--     UPDATE ottoq_bess_units SET current_state = CASE
--         WHEN v_actual_kw > 0 THEN 'charging'
--         WHEN v_actual_kw < 0 THEN 'discharging'
--         ELSE 'idle' END,        -- 'idle' is the unit-level vocabulary   <-- the code's own comment
--     ...
--     INSERT INTO bess_snapshots (... status) VALUES (... (CASE
--         WHEN v_actual_kw > 0 THEN 'charging'
--         WHEN v_actual_kw < 0 THEN 'discharging'
--         ELSE 'standby' END)::bess_status);
--
-- **`idle` on the unit, `standby` in the snapshot, same `v_actual_kw`.** The transition matrix and
-- the `bess_status` enum both know `standby` and **neither knows `idle`** — the enum's six labels are
-- `online, offline, charging, discharging, standby, fault`, and they are precisely the six states the
-- matrix uses. Measured: all **3** `ottoq_bess_units` rows read `current_state = 'idle'` right now,
-- and `bess_snapshots.status` holds `standby` 53,197 / `charging` 28,669 / `discharging` 22,318.
--
-- **WHY IT WAS WRITABLE AT ALL — AND THIS PARAGRAPH IS A CORRECTION OF ITSELF, made when `0397`
-- refused to apply.** I first wrote that the column is "plain `text`, not the `bess_status` enum, no
-- CHECK" and that a free-text column beside a typed one is how a vocabulary drifts. **The first half
-- is right and the second is wrong: there IS a CHECK, and it is the third disagreeing declaration.**
-- `ottoq_bess_units_current_state_check` permits `idle, charging, discharging, maintenance, fault,
-- offline` — it **carries `idle` and FORBIDS `standby`**, which is how `0397`'s first attempt failed:
-- `new row ... violates check constraint`. So there are **three** declarations of this vocabulary and
-- no two agree; their intersection is `charging, discharging, fault, offline`. The commanded column
-- could not hold the resting state the matrix requires, and the matrix could not represent the
-- resting state the column held. **That is worse than drift — it is two schemas written from two
-- vocabularies and never reconciled, mutually exclusive on rest by construction since 2026-07-10.**
--
-- **AND THE CENSUS ABOVE WAS SHORT BY TWO SITES, for a reason worth keeping.** I censused
-- `pg_proc.prosrc`, so I found only what a function body contains. It could not see **the column
-- DEFAULT, `'idle'::text`** — a writer, and the one a `prosrc` census is structurally blind to — nor
-- the CHECK. Same shape as G99: a `prosrc` match is evidence about a function body and nothing else.
-- **It produced a false positive too:** `'maintenance'` appears in `ottoq_tick_invariance_reset_fleet`,
-- but that line reads `WHERE depot_id = ... AND status <> 'maintenance'` and is about
-- **`stalls.status`**, a different column — so nothing writes `maintenance` to the BESS state and
-- dropping it costs nothing. Verify the context, never the presence.
--
-- **THE TRAP THIS SETS FOR WHOEVER WIRES THE PROBE, which is the operative point.** The probe takes
-- `from_state` / `to_state` from `p_context`, i.e. from whatever the caller passes. The natural
-- source for a gate on a commanded BESS state change is `ottoq_bess_units.current_state` — **and
-- passing that column's values refuses every transition into or out of rest**, because no matrix row
-- mentions `idle`. That is not 14.4%; on the resting state it is nearly all of them. A `critical` /
-- `block` rule wired that way takes the BESS offline on the first tick.
--
-- **AND A FOURTH INSTANCE OF THE FILE-FAMILY'S RECURRING SHAPE.** `0285` measured the 14.4% on
-- `bess_snapshots.status` — an OBSERVATION stream — and the question "would wiring SM.006 refuse
-- things?" is about COMMANDED transitions. Those happen to agree here, because both columns are
-- written from one `v_actual_kw` in one function, so the snapshot stream is a faithful proxy —
-- **modulo the one word.** The agreement is a property of this implementation, not of the two
-- columns' meanings, and it is the kind of coincidence that stops being true silently.

-- the split, in one query: what the unit says, what the snapshots say, what the matrix accepts
SELECT 'ottoq_bess_units.current_state (text)' AS source,
       string_agg(DISTINCT current_state, ', ' ORDER BY current_state) AS vocabulary
  FROM public.ottoq_bess_units
UNION ALL
SELECT 'bess_snapshots.status (bess_status enum)',
       string_agg(DISTINCT status::text, ', ' ORDER BY status::text)
  FROM public.bess_snapshots
UNION ALL
SELECT 'ottoq_state_transitions, entity_kind=bess',
       string_agg(DISTINCT s, ', ' ORDER BY s)
  FROM (SELECT from_state AS s FROM public.ottoq_state_transitions
         WHERE entity_kind = 'bess' AND status = 'active'
        UNION SELECT to_state FROM public.ottoq_state_transitions
         WHERE entity_kind = 'bess' AND status = 'active') q
UNION ALL
SELECT 'bess_status enum labels',
       string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'bess_status';

-- the two transitions the matrix omits, which is where the dwell actually lives
SELECT count(*) FILTER (WHERE from_state = 'charging'    AND to_state = 'discharging') AS charge_to_discharge,
       count(*) FILTER (WHERE from_state = 'discharging' AND to_state = 'charging')    AS discharge_to_charge,
       count(*)                                                                        AS active_bess_transitions
  FROM public.ottoq_state_transitions WHERE entity_kind = 'bess' AND status = 'active';

-- ══ 3. THE ORDER OF WORK, REVISED ══════════════════════════════════════════
--
-- `0295` had two steps. There are three, and the new one is first:
--
--   **STEP 0 (new, prerequisite). Give the BESS one word for rest. DONE — `db/migrations/0397`,
--   applied `20260921031935`.** Unify on `standby`, the word the enum, the matrix and the snapshot
--   stream already use. **Six sites, not the four I first counted:** the three writers
--   (`twin.ottoq_sim_bess_step`, `public.ottoq_tick_invariance_reset_fleet`,
--   `twin.ottoq_grid_fixture_create`), the one reader (`public.ottoq_trigger_emergency_cascade`,
--   made **tolerant of both** because rows written before today say `idle`), **the column DEFAULT**
--   and **the CHECK**. `0397` replaces the CHECK with the enum's six labels, moves the DEFAULT, and
--   rewrites the three live rows. Verified: `ottoq_assert_bess_state_vocabulary()` returns
--   `check_states`, `enum_states` and `matrix_states` all reading
--   `charging, discharging, fault, offline, online, standby` — **identical for the first time.**
--   *Not* done: typing the column to `bess_status`, which is the right end state (one declaration
--   instead of two hand-maintained lists) but **breaks `ottoq_world_fingerprint`'s
--   `COALESCE(b.current_state,'-')`** — `COALESCE(bess_status, text)` has no common type — so it
--   touches the certification spine and needs its own file. In its place `0397` asserts that the
--   CHECK's list and the enum's labels still agree, so a future divergence is loud.
--
--   **STEP 1. Drop the dwell, which now means ADDING TWO ROWS, not editing prose. DONE — `0397`.**
--   Verified: 19 active `bess` transitions, of which **2** are the direct flips, and SM.006 now has
--   v1 `archived` / v2 `active`. Insert
--   `charging -> discharging` and `discharging -> charging` for `entity_kind='bess'` with the sibling
--   rows' `allowed_actor_types`, and supersede SM.006 to version 2 with the parenthetical removed
--   **and its rationale replaced** — the current one asserts a direct flip is *"physically impossible
--   for the inverter/contactor and would damage the unit"*, and `0295`'s sourced finding is that
--   IEEE 1547-2018 sets a 30-second CEILING on completing a mode transition with no minimum dwell
--   anywhere, while grid-support literature describes sub-second standby-to-full-power and
--   charge/discharge reversal within seconds. **"Physically impossible" is the strongest claim in the
--   declaration and it is the one with no source.**
--
--   **STEP 2. Wire the probe at `bess_state_change`**, passing the reconciled vocabulary, keeping
--   `critical`/`block` for the genuine invariant (no `offline -> charging`, plus the actor-type gate).
--   `forces_recert TRUE` — a new gate on the tick path — and therefore work for the window §1b
--   describes, while the floor is already broken.
--
-- **THE HONEST SENTENCE ABOUT SM.006 TODAY:** *"Its state-machine half is enforceable and unwired.
-- Its dwell half is implemented as two missing rows in the transition matrix, asserts a physical
-- impossibility no source supports, and could not be observed at our 30-second tick in any case. And
-- it cannot be wired at all until `ottoq_bess_units.current_state` stops calling rest `idle` while
-- everything else calls it `standby`."*

-- OPEN-ITEM: ottoq_bess_units.current_state is plain text and writes 'idle' for rest, while bess_snapshots.status, the bess_status enum and ottoq_state_transitions all use 'standby'; both words are written from one v_actual_kw in one statement pair in twin.ottoq_sim_bess_step. Unify on 'standby' across the four sites ('idle' occurs in exactly four functions: three writers and one reader, ottoq_trigger_emergency_cascade) before any bess_state_change probe is wired, or a critical/block rule takes the BESS offline on the first tick. Tracked as G96.
-- OPEN-ITEM: SM.006's dwell is implemented as the ABSENCE of charging->discharging and discharging->charging from the 17 active bess rows of ottoq_state_transitions, not as timing logic -- the evaluator has none. Dropping the dwell therefore means inserting two transition rows, and superseding the rule to version 2 with the parenthetical removed and the rationale's unsourced "physically impossible for the inverter/contactor" claim replaced by 0295's IEEE 1547-2018 finding. Tracked as G96.
-- OPEN-ITEM: typing ottoq_bess_units.current_state to the bess_status enum, or adding a CHECK, is the right end state but is the 0396 hot-path question again -- twin.ottoq_sim_bess_step is on the tick path and is unwrapped, so a constraint there converts a data defect into a dead run. Needs its own decision and its own file. Tracked as G96.
-- OPEN-ITEM: 0396 changes what a demo run looks like -- prime_fraction 0.3960 -> 0.0135 and primed vehicles 45 -> 2 at seed 100020 -- because the deploy target is now asked about the hour the clock actually says (0) rather than 8. Correct, but it makes the seed set the LOAD as well as the clock, so between-seed KPI variance rises and two seeds are no longer comparable on volume. Whether to pin the demo start hour instead of randomising it is a product call for Chase. Tracked as G107.
-- OPEN-ITEM: the post-fix five-KPI run is still owed and is deferred until the 9-column recert sweep drains, because ottoq-recert-runner refuses to run while any sim run is running/paused and holds one of this instance's six worker processes per round; its cron job was unscheduled rather than left armed. Tracked as G107.
