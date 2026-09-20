-- migration-version: 20260920141533
-- migration-name:    the_published_reliability_field_names_an_action_that_never_happened_and_undercounts_the_one_that_did
--
-- 0381  `reliability.stranded_recharges` IS WRONG TWICE, IN OPPOSITE DIRECTIONS, IN A
--       FIELD WE PUBLISH. ADD THE TWO HONEST NUMBERS; DO NOT TOUCH THE KEY.
--
-- Fixes the measurable half of G87. Reporting function only -- `ottoq_twin_events_window`
-- has **no caller inside the database** (checked against `pg_proc`, not assumed) and is
-- read by the front end, so nothing on the tick path changes. `forces_recert` **FALSE**.
--
-- ══ 1. THE DEFECT, RE-MEASURED RATHER THAN QUOTED ═══════════════════════════
--
-- `twin.ottoq_sim_advance_service_flow` emits `twin.recharge_stranded` with a payload of
-- `{"recharged": N, "floor": 80}`, and `ottoq_twin_events_window` publishes
-- `reliability.stranded_recharges` as `count(*)` of those events.
--
-- **WHAT THE WRITER ACTUALLY DOES: nothing is recharged.** It sets `current_state =
-- 'staged_awaiting_service'` and `svc_step = 'need_charge'`, then temp-stages the vehicle
-- via `ottoq_replan_stranded_undercharge`. No SoC is written. Its own comment says why --
-- *"DOCTRINE (Chase 2026-07-28): never bounce a vehicle to the gate"* -- and the split is
-- correct: OTTO-Q chooses, the twin executes. **It is a re-queue, not a rescue.**
--
-- So the published field is wrong twice, in opposite directions:
--   (a) it says **"recharges"** for an action that grants no charge, so a reader takes the
--       number as vehicles topped up by the simulator -- which would make the twin look
--       like it was covering for the orchestrator. It is not.
--   (b) it counts **EVENTS**, while each event carries `recharged: N` for the N vehicles
--       of that tick.
--
-- **Re-measured today, and it is worse than `db/checks/0263` §3 recorded:**
--
--   requeue events                       **830**   (was 239)
--   vehicles actually requeued         **6,851**   (was 1,333)
--   under-count factor                  **8.25x**  (was 5.6x)
--   most in a single tick                   24
--   runs spanned                            10
--
-- ══ 2. WHY THE KEY IS NOT RENAMED, ANSWERED WITH EVIDENCE ═══════════════════
--
-- `0263` §3 deferred this as *"a compatibility question for whatever reads
-- `ottoq_twin_events_window`"*. That question now has an answer, in three steps:
--
--   1. **One producer.** `ottoq_twin_events_window` is the only database object
--      mentioning the field, and it has no database caller.
--   2. **Live consumers exist.** `ottoyarddepot-sim` reads `stranded_recharges` in
--      `src/lib/ottoq/contracts.ts` (`interface DepotReliability`), `channels.ts`,
--      `ottoTwin.ts`, `worldBoot.test.ts`, `auditRegressions.test.ts` and its built
--      bundle. **That repo is Lovable-synced two-way**, so renaming the key from this
--      side breaks a typed contract in a repo that syncs back.
--   3. **But ADDING keys cannot break it.** `DepotReliability` is a plain TypeScript
--      `interface` -- no zod, no `.strict()`, no runtime validation anywhere -- used only
--      as a compile-time annotation at `channels.ts:676`. Extra properties are ignored.
--
-- **So the additive fix is provably safe and the rename is provably not.** Step 3 is the
-- one that mattered: had `DepotReliability` been a zod schema with `.strict()`, adding
-- fields would have broken the sim at runtime, and I would have shipped it on the
-- assumption that adding is always safe.
--
-- ══ 3. WHAT SHIPS ═══════════════════════════════════════════════════════════
--
--   `stranded_recharges`   unchanged, byte for byte, for the sim's contract
--   `requeue_events`       the same count under a name that says what it counts
--   `vehicles_requeued`    `sum(payload->>'recharged')` -- the quantity a reader wants
--
-- The misnamed key keeps its VALUE rather than being quietly corrected in place, because a
-- consumer reading `stranded_recharges` today would otherwise see it jump 8.25x with no
-- announcement -- a worse failure than the wrong name. **The interim instruction stands:
-- do not quote `stranded_recharges`. Quote `vehicles_requeued`.**
--
-- Part B is derived verbatim from `pg_get_functiondef`, with the reliability block's one
-- line replaced by three plus commentary.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_ev bigint; v_veh numeric;
BEGIN
  --: Assert the defect is real and get its size, so the file cannot ship on a story.
  SELECT count(*), COALESCE(sum((e.payload->>'recharged')::numeric),0)
    INTO v_ev, v_veh
    FROM public.ottoq_events e
   WHERE e.event_type = 'twin.recharge_stranded';
  IF v_ev = 0 THEN
    RAISE WARNING '0381 P1: no twin.recharge_stranded events survive -- the fields still install and will read 0 rather than mislead';
  ELSIF v_veh <= v_ev THEN
    RAISE EXCEPTION '0381 P1: % events carry only % vehicles -- the under-count this file corrects is not present; re-read db/checks/0263 section 3 before applying', v_ev, v_veh;
  ELSE
    RAISE NOTICE '0381 P1: % events carry % vehicle-requeues', v_ev, v_veh;
  END IF;
END $p1$;

DO $p2$
BEGIN
  --: Reporting function: no database caller, so no tick path is touched and
  --: forces_recert FALSE is honest. If that ever changes, this file's classification is
  --: wrong and the preflight says so rather than letting it pass.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public','ottoq','twin')
                AND p.prosrc LIKE '%ottoq\_twin\_events\_window(%'
                AND p.proname <> 'ottoq_twin_events_window') THEN
    RAISE EXCEPTION '0381 P2: ottoq_twin_events_window now HAS a database caller -- reclassify forces_recert before applying';
  END IF;
  RAISE NOTICE '0381 P2: no database caller; reporting-only, forces_recert FALSE holds';
END $p2$;

-- ══ 4. THE FUNCTION ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_twin_events_window(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_min   numeric;
  v_out   jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'sim_run not found'); END IF;
  v_min := NULLIF(EXTRACT(EPOCH FROM (v_run.sim_clock_current - v_run.sim_clock_start)) / 60.0, 0);

  WITH sig AS (
    SELECT event_type, severity, occurred_at, payload FROM ottoq_events
     WHERE sim_run_id = p_sim_run_id
       AND event_type NOT IN (
         'twin.bess_dispatch','twin.weather_tick','twin.solar_tick','twin.grid_tick',
         'twin.sim_tick_advanced','twin.telemetry_emitted','twin.bess_soh_degradation')),
  started AS (SELECT payload p FROM sig WHERE event_type = 'charge.session_started'),
  ended   AS (SELECT payload p FROM sig WHERE event_type = 'charge.session_completed'),
  faulted AS (SELECT payload p FROM sig WHERE event_type = 'charge.session_faulted'),
  delayed AS (SELECT payload p FROM sig WHERE event_type = 'fleet.arrival_delayed'),
  excepted AS (SELECT payload p FROM sig WHERE event_type LIKE 'vehicle.exception%'),
  valve   AS (SELECT payload p, occurred_at FROM sig WHERE event_type = 'twin.rush_valve_hold'),
  fcast   AS (SELECT payload p, occurred_at FROM sig WHERE event_type = 'ottoq.arrival_forecast'
               ORDER BY occurred_at DESC LIMIT 1)
  SELECT jsonb_build_object(
    'window', jsonb_build_object(
      'basis','run_to_date',
      'signal_events',(SELECT count(*) FROM sig),
      'first_at',(SELECT min(occurred_at) FROM sig),
      'last_at',(SELECT max(occurred_at) FROM sig),
      'sim_minutes_elapsed', v_min),
    'by_type', COALESCE((SELECT jsonb_object_agg(event_type,n) FROM (SELECT event_type,count(*) n FROM sig GROUP BY 1) t),'{}'::jsonb),
    'by_severity', COALESCE((SELECT jsonb_object_agg(severity,n) FROM (SELECT severity,count(*) n FROM sig GROUP BY 1) s),'{}'::jsonb),
    'reliability', jsonb_build_object(
      'charge_sessions',(SELECT count(*) FROM started),
      'charge_faults',(SELECT count(*) FROM faulted),
      'charge_fault_rate',(SELECT CASE WHEN count(*)=0 THEN NULL ELSE round((SELECT count(*) FROM faulted)::numeric/count(*),4) END FROM started),
      'fault_reasons', COALESCE((SELECT jsonb_object_agg(reason,n) FROM (SELECT COALESCE(p->>'reason','unspecified') reason,count(*) n FROM faulted GROUP BY 1) fr),'{}'::jsonb),
      'repair_minutes_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'repair_minutes' IS NOT NULL)=0 THEN NULL ELSE sum((p->>'repair_minutes')::numeric) END FROM faulted),
      'arrival_delays',(SELECT count(*) FROM delayed),
      'delay_min_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'delay_min')::numeric)::numeric,1) FROM delayed WHERE p->>'delay_min' IS NOT NULL),
      'delay_causes', COALESCE((SELECT jsonb_object_agg(cause,n) FROM (SELECT COALESCE(p->>'cause','unspecified') cause,count(*) n FROM delayed GROUP BY 1) dc),'{}'::jsonb),
      --: G87. RETAINED EXACTLY AS IT WAS, and it must be: ottoyarddepot-sim reads this
      --: key in src/lib/ottoq/contracts.ts (interface DepotReliability), channels.ts,
      --: ottoTwin.ts, two tests and its built bundle -- and that repo is Lovable-synced
      --: two-way, so renaming the key would break a live typed contract from this side.
      --: It is WRONG TWICE and must not be quoted: it says "recharges" for an action
      --: that grants no charge (the writer sets svc_step='need_charge' and temp-stages
      --: the vehicle -- a RE-QUEUE, per the never-bounce-to-the-gate doctrine), and it
      --: counts EVENTS where each event carries N vehicles. Measured 2026-09-20: 830
      --: events against 6,851 vehicle-requeues, an 8.25x under-count.
      'stranded_recharges',(SELECT count(*) FROM sig WHERE event_type='twin.recharge_stranded'),
      --: 0381. The two honest fields, ADDED rather than substituted. Safe because
      --: DepotReliability is a plain TypeScript interface with no zod schema and no
      --: runtime strict validation, so extra keys are ignored by the consumer -- checked
      --: before writing this, because assuming it would have broken a partner repo.
      'requeue_events',(SELECT count(*) FROM sig WHERE event_type='twin.recharge_stranded'),
      'vehicles_requeued',(SELECT COALESCE(sum((payload->>'recharged')::numeric),0) FROM sig WHERE event_type='twin.recharge_stranded'),
      'tow_events',(SELECT count(*) FROM sig WHERE event_type LIKE 'vehicle.tow%'),
      'exceptions_by_severity', COALESCE((SELECT jsonb_object_agg(sev,n) FROM (SELECT COALESCE(p->>'severity','unspecified') sev,count(*) n FROM excepted GROUP BY 1) es),'{}'::jsonb),
      'faults_per_sim_hour',(SELECT CASE WHEN v_min IS NULL THEN NULL ELSE round(count(*)*60.0/v_min,3) END FROM faulted),
      'delays_per_sim_hour',(SELECT CASE WHEN v_min IS NULL THEN NULL ELSE round(count(*)*60.0/v_min,3) END FROM delayed)),
    'charging', jsonb_build_object(
      'target_soc_p50',(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'soc_target')::numeric) FROM started WHERE p->>'soc_target' IS NOT NULL),
      'soc_start_p50',(SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'soc_start')::numeric) FROM started WHERE p->>'soc_start' IS NOT NULL),
      'charge_curve_ratio_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'initial_rate_kw')::numeric/NULLIF((p->>'max_rate_kw')::numeric,0))::numeric,3) FROM started WHERE p->>'initial_rate_kw' IS NOT NULL AND p->>'max_rate_kw' IS NOT NULL),
      'battery_temp_c_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'battery_temp_c')::numeric)::numeric,1) FROM started WHERE p->>'battery_temp_c' IS NOT NULL),
      'battery_soh_pct_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'battery_soh_pct')::numeric)::numeric,2) FROM started WHERE p->>'battery_soh_pct' IS NOT NULL),
      'sessions_completed',(SELECT count(*) FROM ended),
      'energy_kwh_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'energy_kwh' IS NOT NULL)=0 THEN NULL ELSE round(sum((p->>'energy_kwh')::numeric),2) END FROM ended),
      'avg_power_kw_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'avg_power_kw')::numeric)::numeric,2) FROM ended WHERE p->>'avg_power_kw' IS NOT NULL),
      'session_duration_s_p50',(SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (p->>'duration_s')::numeric)::numeric,1) FROM ended WHERE p->>'duration_s' IS NOT NULL),
      'auto_rerouted',(SELECT count(*) FILTER (WHERE (p->>'auto_rerouted')::boolean) FROM ended)),
    'demand_forecast',(SELECT jsonb_build_object(
        'at',f.occurred_at,'horizon_min',(f.p->>'horizon_min')::numeric,
        'incoming_count',(f.p->>'incoming_count')::numeric,
        'charge_needed_count',(f.p->>'charge_needed_count')::numeric,
        'predicted_charge_kw',(f.p->>'predicted_charge_kw')::numeric,
        'predicted_charge_kwh',(f.p->>'predicted_charge_kwh')::numeric) FROM fcast f),
    'throughput', jsonb_build_object(
      'valve_holds',(SELECT count(*) FROM valve),
      'held_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'held' IS NOT NULL)=0 THEN NULL ELSE sum((p->>'held')::numeric) END FROM valve),
      'released_total',(SELECT CASE WHEN count(*) FILTER (WHERE p->>'released' IS NOT NULL)=0 THEN NULL ELSE sum((p->>'released')::numeric) END FROM valve),
      'cap_last',(SELECT (p->>'cap')::numeric FROM valve ORDER BY occurred_at DESC LIMIT 1))
  ) INTO v_out;
  RETURN v_out;
END;
$function$
;

COMMENT ON FUNCTION public.ottoq_twin_events_window(uuid) IS
'Twin event-window report. 0381 (G87): reliability.stranded_recharges is WRONG TWICE and is retained only for compatibility -- DO NOT QUOTE IT. It says "recharges" for an action that grants no charge (twin.ottoq_sim_advance_service_flow sets svc_step=need_charge and temp-stages the vehicle per the never-bounce-to-the-gate doctrine -- a RE-QUEUE, not a rescue), and it counts EVENTS while each event carries recharged:N vehicles. Measured 2026-09-20: 830 events against 6,851 vehicle-requeues, an 8.25x under-count, worse than the 239/1,333 db/checks/0263 section 3 recorded. The key is NOT renamed because ottoyarddepot-sim reads it in src/lib/ottoq/contracts.ts (interface DepotReliability), channels.ts, ottoTwin.ts, two tests and its built bundle, and that repo is Lovable-synced two-way. Adding keys IS safe -- DepotReliability is a plain TypeScript interface with no zod and no runtime strict validation, checked before writing rather than assumed. So 0381 adds requeue_events (the honest count) and vehicles_requeued (sum of payload->>recharged, the quantity a reader actually wants) and leaves the old key at its old value, because a consumer seeing stranded_recharges jump 8.25x with no announcement is a worse failure than the wrong name.';

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_twin_events_window';

  IF position('requeue_events' in v_src) = 0 THEN
    RAISE EXCEPTION '0381 P3: requeue_events is absent from the rebuilt function';
  END IF;
  IF position('vehicles_requeued' in v_src) = 0 THEN
    RAISE EXCEPTION '0381 P3: vehicles_requeued is absent from the rebuilt function';
  END IF;
  --: THE COMPATIBILITY ASSERTION. The sim's contract key must survive verbatim.
  IF position('stranded_recharges' in v_src) = 0 THEN
    RAISE EXCEPTION '0381 P3: stranded_recharges was REMOVED -- that breaks ottoyarddepot-sim DepotReliability contract';
  END IF;
  --: AND THEN CALL IT, because everything above is a STRING MATCH on prosrc and a
  --: string match passed on a body that raised. The first version of this file used
  --: `p->>'recharged'` where the `sig` CTE exposes `payload` -- `p` is aliased only in
  --: the derived CTEs -- and plpgsql resolves column references at EXECUTION, not at
  --: CREATE. So the migration applied, P3's greps passed, and the function raised
  --: 42703 for every caller until it was called. THE SAME CLASS AS 0379's ON CONFLICT
  --: inference and 0377's path test, which this file's own author had just written up.
  --: A postflight that reads source instead of invoking the thing is not a postflight.
  DECLARE
    v_run uuid;
    v_rel jsonb;
  BEGIN
    SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
     ORDER BY started_at DESC LIMIT 1;
    IF v_run IS NULL THEN
      RAISE WARNING '0381 P3: no sim run exists, so the function could not be INVOKED -- '
                    'the field names are present but unproven';
    ELSE
      v_rel := public.ottoq_twin_events_window(v_run) -> 'reliability';
      IF v_rel IS NULL THEN
        RAISE EXCEPTION '0381 P3: the function returned no reliability block';
      END IF;
      IF NOT (v_rel ? 'requeue_events' AND v_rel ? 'vehicles_requeued'
              AND v_rel ? 'stranded_recharges') THEN
        RAISE EXCEPTION '0381 P3: invoked, but the reliability block is missing a key: %',
                        v_rel;
      END IF;
      RAISE NOTICE '0381 P3: INVOKED clean -- stranded_recharges=%, requeue_events=%, '
                   'vehicles_requeued=%',
                   v_rel->>'stranded_recharges', v_rel->>'requeue_events',
                   v_rel->>'vehicles_requeued';
    END IF;
  END;
  RAISE NOTICE '0381 P3: both honest fields present, the compatibility key intact';
END $p3$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0381_the_published_reliability_field_names_an_action_that_never_happened_and_undercounts_the_one_that_did', false,
  'Reporting function only -- ottoq_twin_events_window has no database caller (asserted in P2, '
  'which fails the migration if one ever appears), so no tick path changes and no canon is '
  'invalidated. Fixes the measurable half of G87: reliability.stranded_recharges says "recharges" '
  'for an action that grants no charge (the writer sets svc_step=need_charge and temp-stages the '
  'vehicle per the never-bounce-to-the-gate doctrine) and counts EVENTS while each carries '
  'recharged:N vehicles. Re-measured 2026-09-20: 830 events against 6,851 requeues, an 8.25x '
  'under-count, worse than 0263 section 3 239/1,333. The key is NOT renamed: ottoyarddepot-sim '
  'reads it in contracts.ts (interface DepotReliability), channels.ts, ottoTwin.ts, two tests and '
  'its built bundle, and that repo is Lovable-synced two-way. Adding keys is safe because '
  'DepotReliability is a plain TS interface with no zod and no runtime strict validation -- '
  'checked before writing, since a strict() schema would have broken the sim at runtime. Adds '
  'requeue_events and vehicles_requeued and leaves the old key at its old value, because a '
  'consumer seeing it jump 8.25x unannounced is a worse failure than the wrong name.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
