-- 0285  SM.006 FORBIDS EXACTLY ONE THING — REVERSING BETWEEN CHARGE AND DISCHARGE WITHOUT
--       DWELLING — AND THE TWIN DEPOT'S BATTERY DOES IT 3,426 TIMES, 14.4% OF EVERY
--       TRANSITION IT HAS EVER MADE. THE RULE IS `critical`, `enforcement='block'`, AND HAS
--       NEVER BEEN WIRED. MEASURED, NOT FIXED.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8). **This is the
-- one finding in this series that CANNOT carry a run id, and the reason is structural:**
-- `public.bess_snapshots` has **no `sim_run_id` column at all**, so it is not run-scoped, is
-- not purged, and accumulates across every run. The 23,730 transitions below span
-- 2026-05-12 to 2026-09-20 at this depot — the engine's whole life, not one run. CLAUDE.md's
-- "cite the run, never the table" cannot be honoured here; saying so is the honest move, and
-- the missing column is itself worth a look.
--
-- ══ 1. WHY I WAS ABOUT TO WIRE THIS AND STOPPED ════════════════════════════
--
-- SM.006 was next on the list after `0387` wired SM.001 and SM.003, and it looked identical:
-- `ottoq_eval_sm_006_bess_transition` is one line delegating to
-- `ottoq_eval_sm_transition_validity('bess', ...)`, the same helper the other two use, and it
-- wants the same context — `from_state`, `to_state`, `actor_type`.
--
-- **It is not identical, in two ways, and both would have made the probe measure something
-- other than the rule.**
--
-- **(a) There is no trigger to hang it on.** `0387` was one call added to
-- `trg_ottoq_vehicles_state_change`, which already existed, already fired per row, and
-- already recorded an event. **No trigger of any kind exists on `ottoq_bess_units`** — the
-- hook has to be built, and a new AFTER trigger on a table the tick writes every beat is a
-- different risk class from adding a line to one that was already there.
--
-- **(b) The unit-level column speaks a different dialect.** `twin.ottoq_sim_bess_step` is
-- the writer, and its own words are:
--
--     current_state = CASE WHEN v_actual_kw > 0 THEN 'charging'
--                          WHEN v_actual_kw < 0 THEN 'discharging'
--                          ELSE 'idle' END,    -- 'idle' is the unit-level vocabulary
--
-- So the column's vocabulary is {`charging`, `discharging`, `idle`}, while the declared
-- matrix is {`charging`, `discharging`, `fault`, `offline`, `online`, `standby`}. **`idle` is
-- an undeclared synonym for `standby`** — and the comment shows the divergence was known and
-- chosen, not accidental. Since zero power is the battery's commonest condition, a probe on
-- `current_state` would fail the MAJORITY of transitions on the role-and-legality lookup for
-- a state the matrix has never heard of, and report a vocabulary mismatch as a state-machine
-- violation. **That is `0387`'s preflight lesson exactly** — there, `actor_type` defaulted to
-- `'unknown'` and nothing supplied it, so a naive wiring would have failed every transition
-- on the role gate. The input has to exist before the rule can be measured.
--
-- **CORRECTION TO MY OWN FIRST READING, recorded because it is the third unit error tonight
-- (see `0284` §3).** I first measured "declared vs live vocabulary, overlap **zero**" — from
-- `SELECT DISTINCT current_state FROM ottoq_bess_units`, which returned exactly one row,
-- `idle`, across 3 units. **That is a census of three pointers at one instant, not a
-- vocabulary.** The column takes `charging` and `discharging` too; they simply were not in
-- force when I looked, because all three units happened to be at zero power. The vocabulary
-- is a property of the WRITER and had to be read from its source. Two of the three values
-- are declared; one is not.

SELECT 'declared (ottoq_state_transitions, entity_kind=bess)' AS lens,
       string_agg(DISTINCT s, ', ' ORDER BY s) AS vocabulary
  FROM (SELECT from_state s FROM public.ottoq_state_transitions
         WHERE entity_kind='bess' AND status='active'
        UNION SELECT to_state FROM public.ottoq_state_transitions
         WHERE entity_kind='bess' AND status='active') x
UNION ALL
SELECT 'written by twin.ottoq_sim_bess_step into ottoq_bess_units.current_state',
       'charging, discharging, idle  <- ''idle'' is undeclared; the matrix says ''standby'''
UNION ALL
SELECT 'realised in bess_snapshots.status (the moving series)',
       (SELECT string_agg(DISTINCT status::text, ', ' ORDER BY status::text)
          FROM public.bess_snapshots
         WHERE depot_id = '11111111-1111-1111-1111-111111111111');

-- ══ 2. SO I EVALUATED SM.006 BY HAND INSTEAD, AND IT FAILS ═════════════════
--
-- `bess_snapshots.status` is the series that actually moves, and it speaks the DECLARED
-- language — `standby`, `charging`, `discharging`. So the rule can be evaluated without
-- wiring anything: take consecutive statuses per `system_id` and ask the declared matrix.
--
--   standby   -> charging       6,901   declared
--   charging  -> standby        6,890   declared
--   discharging -> standby      3,262   declared
--   standby   -> discharging    3,251   declared
--   ------------------------------------------- 20,304 legal
--   **charging -> discharging   1,719   UNDECLARED**
--   **discharging -> charging   1,707   UNDECLARED**
--   ------------------------------------------- **3,426 of 23,730 = 14.4%**
--
-- **The 3,426 are precisely the transition the rule exists to forbid.** SM.006's own
-- description: *"A BESS unit may only change power state along the admissible transition
-- matrix (**dwell-through-standby between charge and discharge**)."* The battery reverses
-- directly, without dwelling, on one transition in seven — and because the rule has no
-- caller, nothing has ever counted it.
--
-- Note what this is NOT: it is not a claim that the other four states are exercised. Of the
-- six declared states only three ever appear in the series; `fault`, `offline` and `online`
-- are declared and unobserved at this depot. A matrix three-quarters of whose states never
-- occur is its own question.

WITH s AS (
  SELECT system_id, "timestamp" AS ts, status,
         lag(status) OVER (PARTITION BY system_id ORDER BY "timestamp") AS prev
    FROM public.bess_snapshots
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'),
t AS (SELECT prev AS from_state, status AS to_state, count(*) AS n
        FROM s WHERE prev IS NOT NULL AND prev <> status GROUP BY 1,2)
SELECT t.from_state, t.to_state, t.n,
       EXISTS (SELECT 1 FROM public.ottoq_state_transitions x
                WHERE x.entity_kind='bess' AND x.status='active'
                  AND x.from_state = t.from_state::text
                  AND x.to_state   = t.to_state::text) AS declared
  FROM t ORDER BY declared, n DESC;

WITH s AS (
  SELECT system_id, status,
         lag(status) OVER (PARTITION BY system_id ORDER BY "timestamp") AS prev
    FROM public.bess_snapshots
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'),
t AS (SELECT prev, status FROM s WHERE prev IS NOT NULL AND prev <> status)
SELECT count(*) AS transitions_all_time,
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.ottoq_state_transitions x
          WHERE x.entity_kind='bess' AND x.status='active'
            AND x.from_state = t.prev::text AND x.to_state = t.status::text)) AS undeclared,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.ottoq_state_transitions x
          WHERE x.entity_kind='bess' AND x.status='active'
            AND x.from_state = t.prev::text AND x.to_state = t.status::text))
         / NULLIF(count(*),0), 1) AS pct_undeclared
  FROM t;

-- ══ 3. WHY THIS IS NOT FIXED HERE ══════════════════════════════════════════
--
-- Three separate decisions sit underneath it and only the first is mechanical.
--
--   (a) **`idle` versus `standby`.** Mechanical-looking, and still not free: renaming the
--       written value touches the tick path, and `ottoq_bess_units.current_state` is read by
--       eight functions including `ottoq_twin_snapshot`, `ottoq_nl_status_brief` and
--       `ottoq_trigger_emergency_cascade`. Declaring `idle` in the matrix as a synonym is the
--       smaller change; renaming the value is the cleaner one. Not the same decision.
--
--   (b) **Is a direct reversal actually illegal?** This is the real question and it is
--       Chase's. A modern grid inverter can cross zero without a dwell; the dwell in the
--       declared matrix may encode a vendor limit, a cell-protection policy, or an
--       assumption nobody has checked against the hardware. If reversal is fine, the matrix
--       is wrong and 3,426 findings evaporate. If the dwell is real, the twin has been
--       modelling a duty cycle the hardware would refuse, and the BESS numbers downstream —
--       every `bess_setpoint_kw` command, the whole MPC follow path — inherit that.
--       **Exactly the G94 shape: two readings, opposite remedies, and the measurement cannot
--       choose between them.**
--
--   (c) **Where the probe goes.** SM.006 is about a TRANSITION in an append-only series, not
--       an UPDATE on a pointer, so `0387`'s AFTER-UPDATE pattern does not transfer. The
--       probe belongs on the `bess_snapshots` insert, comparing against the previous row per
--       `system_id` — a hot path with 91k rows at this depot, so it needs the cost measured
--       before it is added, not after.
--
-- **Tracked as G96, open.** And promoting SM.006 to `block` today would refuse 14.4% of the
-- battery's transitions, which is why 2.9a measures before enforcing — the same sentence
-- `0280` had to write about SM.001.
--
-- ══ 4. AND THE MISSING COLUMN, WHICH IS A SMALLER FINDING WORTH ITS LINE ════
--
-- `bess_snapshots` carries `depot_id` and `system_id` and **no `sim_run_id`**, so it cannot be
-- registered run-scoped, is never purged, and mixes every run's battery history into one
-- series. That is why this file's headline number is an all-time figure at one depot rather
-- than a per-run one, and why it cannot be cited the way CLAUDE.md requires. Whether that is
-- deliberate — a battery's state of health genuinely IS cross-run — or an omission is not
-- established here. It is noted because the next person to measure the BESS will hit it too.

SELECT 'bess_snapshots' AS tbl,
       count(*) FILTER (WHERE column_name = 'sim_run_id')  AS has_sim_run_id,
       count(*) FILTER (WHERE column_name = 'data_source') AS has_data_source,
       (SELECT count(*) FROM public.bess_snapshots
         WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS rows_at_twin_depot,
       (SELECT min("timestamp")::date FROM public.bess_snapshots
         WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS earliest,
       (SELECT max("timestamp")::date FROM public.bess_snapshots
         WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS latest
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'bess_snapshots';
