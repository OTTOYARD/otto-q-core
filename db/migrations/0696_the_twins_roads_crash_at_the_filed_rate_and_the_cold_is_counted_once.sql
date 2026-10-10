-- migration-version: 20261010113746
-- migration-name:    the_twins_roads_crash_at_the_filed_rate_and_the_cold_is_counted_once
--
-- 0696  **The twin's cars crash on the road at the rate Waymo filed with the CPUC, towed as often as NHTSA's reports
--        say, and the air's temperature drains a battery once, through the driving physics.**
--        FINDINGS G408 and G410, Part A items 2 and 4 of the twin data contract review (Chase, 2026-10-09: ingest the
--        public data directly, with its URL and date).
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   G408 (db/checks/0433 §4, 0434 §1). Waymo's driverless deployment filing to the CPUC for 2026-04-01 to 2026-06-30
--   has 291 collision rows over 28,143,285 miles: 10.3 per million miles, 2 of them severe
--   (docs/research/direct/2026-10-10-cpuc-waymo-q2-2026-duty-cycle.md, the file's URL and sha256 there). NHTSA's crash
--   reports for automated driving systems hold 1,211 Waymo reports, the Waymo towed in 647, 53.4%
--   (docs/research/direct/2026-10-10-nhtsa-crash-reports-and-temperature-curves.md). twin.ottoq_sim_maybe_incident fires
--   5e-7 incidents a mile, 82% of them collisions: 0.41 per million miles, about a 25th of the filing, with 45% of all
--   incidents towed.
--
--   G410 (db/checks/0434 §3). The twin's driving physics (twin.ottoq_sim_compute_discharge_rate: a cabin load past 5 °C
--   either side of 22 °C, and a battery factor below 5 °C and above 35 °C) already tracks Geotab's published range curve
--   (4,200 EVs, https://www.geotab.com/blog/ev-range/, page of 2025-10-30, read 2026-10-10). ottoq_twin_arrival_soc_drain
--   adds 8 x heat_stress + 12 x cold_stress points an hour out on top: for a Waymo I-Pace at normal_day's mean duty, range
--   at -15 °C is 43.9% of its own best by the physics and 27.0% with the drain (Geotab: 47%), and at 31 °C 92.3% and
--   73.1% (Geotab: at least 87%).
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════
--
--   (a) twin.ottoq_sim_maybe_incident: collisions at 291 / 28,143,285 a mile; of them 647 / 1,211 towed and 2 / 291
--       severe (collision_major). Breakdowns, tire failures and strandings keep their earlier rate, 9e-8 a mile (0.18 of
--       5e-7) in the earlier 4:3:2 split: no public dataset gives them per mile. The same seeded draws ('inc_roll:',
--       'inc_pick:'), the same outcomes in the same order of severity, so a scenario's severity shift still moves a pick
--       toward the worse ones (A.10), and the same multipliers (a scenario's incident rate, busy_day's 0.4; the
--       breakdown rate). ASSUMPTION: Waymo's California rate stands in for every twin fleet; no public per-mile collision
--       rate exists for Tesla's or Zoox's driverless cars.
--   (b) ottoq_twin_arrival_soc_drain returns 0: the temperature is counted once, by the physics. Its one caller,
--       twin.ottoq_sim_advance_deployed_telemetry, adds GREATEST(0, COALESCE(drain, 0)) and is not touched (0690 and
--       0692 patch it; this file does not need to).
--   (c) No row in ottoq_evidence_regimes, and why. The table admits only the charge clock (its CHECK: model =
--       'charge_time_v2'), whose world does not change here: a charge's physics is as before, and G410 moves only the
--       charge a car arrives with, which the clock reads as an input. return_v1, which learns each car's drain and the
--       calls home beside the reserve, is the model whose world changes, and it neither records a regime nor cuts its
--       fit at one: until the runs before this file age out of its window, its fit reads both worlds. Recording that
--       needs the table's CHECK widened (a DROP, which waits on a person at the connector) and the fit taught to cut;
--       both are the follow-up in FINDINGS G408 and G410.
--
--   Leverage, said plainly: at the filing's rate the twin depot's week of about 440,000 miles holds about 4.5
--   collisions (0.15 before), and busy_day's 0.4 makes it about one tow-in in 31 runs (G408). Over the last 7 days'
--   runs (day means 10.1-28.9 °C) the drain averaged 0.03 points an hour, so (b) moves nothing measured this week and
--   everything in a winter or high-summer scenario.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ════════════════════════════════════════════════════════════
--
--   A change in what the twin's world draws: a canon cell that crosses a collision or a stress day digests
--   differently, and an experiment's looks must not mix the two worlds. Written to ride the recertification and the
--   restart 0657 forces the same morning.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the two definitions in ottoq_schema_snapshots WHERE label = '0696_pre'. A rollback is itself a change in
--   what the twin draws, so it forces a recertification of its own.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0696 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF to_regprocedure('twin.ottoq_sim_maybe_incident(bigint,text,numeric,numeric,numeric,numeric)') IS NULL
     OR to_regprocedure('public.ottoq_twin_arrival_soc_drain(uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0696 P1: a function this file replaces does not exist';
  END IF;
  IF md5(pg_get_functiondef(to_regprocedure('twin.ottoq_sim_maybe_incident(bigint,text,numeric,numeric,numeric,numeric)')))
       <> '4aef2f4cc0becdc1f5a8282f19b80fc9'
     OR md5(pg_get_functiondef(to_regprocedure('public.ottoq_twin_arrival_soc_drain(uuid,timestamptz)')))
       <> '4d8990f96cb758bb068e700ac4c8c533' THEN
    RAISE EXCEPTION '0696 P1: a function this file replaces is not the definition it was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0696 P1: a run is live; a world changes between runs';
  END IF;
END $premises$;

-- ── snapshots ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0696_pre', 'function', x.s, x.n, x.d, md5(x.d)
  FROM (SELECT split_part(f, '.', 1) AS s, split_part(f, '.', 2) AS n, pg_get_functiondef(f::regprocedure) AS d
          FROM unnest(ARRAY['twin.ottoq_sim_maybe_incident(bigint,text,numeric,numeric,numeric,numeric)',
                            'public.ottoq_twin_arrival_soc_drain(uuid,timestamptz)']) f) x;

-- ── what the old world drew, kept for V1 ──
CREATE TEMP TABLE p0696 (k text PRIMARY KEY, v jsonb) ON COMMIT DROP;

INSERT INTO p0696
SELECT 'old_fire_10k', to_jsonb(count(x.*)::numeric / 20000)
  FROM generate_series(1, 20000) g
  LEFT JOIN LATERAL twin.ottoq_sim_maybe_incident(171717, 'v1:' || g, 10000, 1, 0, 1) x ON true
 WHERE x.out_kind IS NOT NULL;

-- the old drain over the twin depot's last 40 runs, each on the sim days it covered
INSERT INTO p0696
SELECT 'old_drain', COALESCE(jsonb_agg(jsonb_build_object('run', d.run, 'at', d.at, 'drain', d.drain)), '[]'::jsonb)
  FROM (SELECT r.sim_run_id AS run, x.at, public.ottoq_twin_arrival_soc_drain(r.sim_run_id, x.at) AS drain
          FROM (SELECT sim_run_id, sim_clock_start, sim_clock_end FROM public.ottoq_sim_runs
                 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_start IS NOT NULL
                 ORDER BY started_at DESC NULLS LAST LIMIT 40) r
          CROSS JOIN LATERAL (SELECT generate_series(date_trunc('day', r.sim_clock_start) + interval '12 hours',
                                                     COALESCE(r.sim_clock_end, r.sim_clock_start) + interval '12 hours',
                                                     interval '1 day') AS at) x) d;

-- ── (a) collisions at the filed rate ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_maybe_incident(p_seed bigint, p_salt text, p_miles_this_tick numeric, p_rate_mult numeric DEFAULT 1, p_severity_shift numeric DEFAULT 0, p_breakdown_mult numeric DEFAULT 1)
 RETURNS TABLE(out_kind text, out_sev text, out_requires_tow boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  -- 0696 (G408): collisions at the rate Waymo filed with the CPUC for its California driverless deployment,
  -- 2026-04-01 to 2026-06-30: 291 collision rows over 28,143,285 miles, 10.3 per million
  -- (docs/research/direct/2026-10-10-cpuc-waymo-q2-2026-duty-cycle.md). ASSUMPTION: it stands in for every twin fleet.
  v_collision_per_mile CONSTANT numeric := 291.0 / 28143285;
  -- breakdowns, tire failures and strandings at their earlier rate (0.18 of the earlier 5e-7): no public per-mile data
  v_other_per_mile     CONSTANT numeric := 0.00000009;
  -- of the collisions: towed, NHTSA SGO 2021-01 ADS reports, 647 of Waymo's 1,211; severe, the CPUC file, 2 of 291
  -- (docs/research/direct/2026-10-10-nhtsa-crash-reports-and-temperature-curves.md)
  v_towed              CONSTANT numeric := 647.0 / 1211;
  v_severe             CONSTANT numeric := 2.0 / 291;
  v_per_mile numeric;
  v_c        numeric;
  v_roll     numeric;
  v_pick     numeric;
BEGIN
  IF p_miles_this_tick <= 0 THEN RETURN; END IF;
  v_per_mile := v_collision_per_mile + v_other_per_mile;
  v_roll := ottoq_sim_seeded_random(p_seed, 'inc_roll:' || p_salt);
  -- A.10: breakdown_rate also lifts the overall incident probability slightly
  IF v_roll >= (v_per_mile * p_miles_this_tick * COALESCE(p_rate_mult, 1) * COALESCE(p_breakdown_mult, 1)) THEN RETURN; END IF;

  -- A.10: incident_severity shifts the pick toward more severe outcomes, so the outcomes stay in order of severity
  v_pick := LEAST(1, GREATEST(0, ottoq_sim_seeded_random(p_seed, 'inc_pick:' || p_salt) + COALESCE(p_severity_shift, 0)));
  v_c := v_collision_per_mile / v_per_mile;   -- the collisions' share of what fires
  IF v_pick < v_c * (1 - v_towed) THEN
    out_kind := 'collision_minor'; out_sev := 'minor'; out_requires_tow := FALSE;
  ELSIF v_pick < v_c * (1 - v_severe) THEN
    out_kind := 'collision_moderate'; out_sev := 'moderate'; out_requires_tow := TRUE;
  ELSIF v_pick < v_c * (1 - v_severe) + (1 - v_c) * 4 / 9 THEN
    out_kind := 'breakdown_electrical'; out_sev := 'moderate'; out_requires_tow := TRUE;
  ELSIF v_pick < v_c * (1 - v_severe) + (1 - v_c) * 7 / 9 THEN
    out_kind := 'tire_failure'; out_sev := 'minor'; out_requires_tow := TRUE;
  ELSIF v_pick < v_c * (1 - v_severe) + (1 - v_c) THEN
    out_kind := 'stranded_low_soc'; out_sev := 'moderate'; out_requires_tow := TRUE;
  ELSE
    out_kind := 'collision_major'; out_sev := 'major'; out_requires_tow := TRUE;
  END IF;
  RETURN NEXT;
END;
$function$;
COMMENT ON FUNCTION twin.ottoq_sim_maybe_incident(bigint,text,numeric,numeric,numeric,numeric) IS
  '0696 (G408): an incident on the road this tick, at the CPUC-filed collision rate (291 over 28,143,285 miles), '
  'towed as NHTSA''s reports (647 of 1,211) and severe as the filing (2 of 291); other incidents at 9e-8 a mile.';

-- ── (b) the cold and the heat drain a battery once ──
CREATE OR REPLACE FUNCTION public.ottoq_twin_arrival_soc_drain(p_run uuid, p_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- 0696 (G410): no drain beyond the physics. twin.ottoq_sim_compute_discharge_rate already carries the air's
  -- temperature (a cabin load and a battery factor) and tracks Geotab's published range curve (4,200 EVs,
  -- https://www.geotab.com/blog/ev-range/, page of 2025-10-30, read 2026-10-10). The 8 x heat_stress + 12 x cold_stress
  -- points an hour out this added counted it a second time (db/checks/0434 section 3).
  RETURN 0;
END $function$;
COMMENT ON FUNCTION public.ottoq_twin_arrival_soc_drain(uuid,timestamptz) IS
  '0696 (G410): 0. The air''s temperature drains a battery once, through the twin''s driving physics.';

-- ── V1: the draws are the filed rates, and the drain is zero where it was not ──
DO $v1$
DECLARE
  v_n int := 20000;
  v_fire numeric; v_old_fire numeric; v_expect numeric;
  v_minor numeric; v_mod numeric; v_major numeric; v_other numeric; v_towed_share numeric;
  v_c numeric; v_drained int; v_scanned int; v_now_nonzero int;
BEGIN
  -- at 10,000 miles in a tick the probability is 10,000 x (291 / 28,143,285 + 9e-8): about 0.104 (0.005 before)
  SELECT count(x.*)::numeric / v_n INTO v_fire
    FROM generate_series(1, v_n) g
    LEFT JOIN LATERAL twin.ottoq_sim_maybe_incident(171717, 'v1:' || g, 10000, 1, 0, 1) x ON true
   WHERE x.out_kind IS NOT NULL;
  v_old_fire := (SELECT (v #>> '{}')::numeric FROM p0696 WHERE k = 'old_fire_10k');
  v_expect := 10000 * (291.0 / 28143285 + 0.00000009);
  IF abs(v_fire - v_expect) > 0.1 * v_expect OR v_old_fire > 0.01 THEN
    RAISE EXCEPTION '0696 V1 FAILED: at 10,000 miles % fired (expected %, % before)', v_fire, round(v_expect, 4), v_old_fire;
  END IF;
  -- at a million miles every draw fires, so the picks are the outcome shares
  SELECT avg((x.out_kind = 'collision_minor')::int), avg((x.out_kind = 'collision_moderate')::int),
         avg((x.out_kind = 'collision_major')::int),
         avg((x.out_kind IN ('breakdown_electrical', 'tire_failure', 'stranded_low_soc'))::int),
         sum((x.out_kind IN ('collision_moderate', 'collision_major'))::int)::numeric
           / NULLIF(sum((x.out_kind LIKE 'collision%')::int), 0)
    INTO v_minor, v_mod, v_major, v_other, v_towed_share
    FROM generate_series(1, v_n) g
    CROSS JOIN LATERAL twin.ottoq_sim_maybe_incident(171717, 'v1:' || g, 1000000, 1, 0, 1) x;
  v_c := (291.0 / 28143285) / (291.0 / 28143285 + 0.00000009);
  IF abs(v_minor - v_c * (564.0 / 1211)) > 0.012 OR abs(v_mod - v_c * (647.0 / 1211 - 2.0 / 291)) > 0.012
     OR abs(v_major - v_c * 2.0 / 291) > 0.004 OR abs(v_other - (1 - v_c)) > 0.004
     OR abs(v_towed_share - 647.0 / 1211) > 0.012 THEN
    RAISE EXCEPTION '0696 V1 FAILED: outcome shares minor %, moderate %, major %, other %, towed of collisions %',
      round(v_minor, 4), round(v_mod, 4), round(v_major, 4), round(v_other, 4), round(v_towed_share, 4);
  END IF;
  -- the drain: zero now on every run and day it was scanned on, including those where it was not
  SELECT count(*), count(*) FILTER (WHERE (e ->> 'drain')::numeric > 0),
         count(*) FILTER (WHERE public.ottoq_twin_arrival_soc_drain((e ->> 'run')::uuid, (e ->> 'at')::timestamptz) <> 0)
    INTO v_scanned, v_drained, v_now_nonzero
    FROM p0696, jsonb_array_elements(p0696.v) e
   WHERE p0696.k = 'old_drain';
  IF v_scanned = 0 OR v_now_nonzero > 0 THEN
    RAISE EXCEPTION '0696 V1 FAILED: the drain over % scanned run-days is non-zero on %', v_scanned, v_now_nonzero;
  END IF;
  RAISE NOTICE '0696 V1 PASSED: at 10,000 miles % of % draws fire (% before); of every incident % minor collisions, % moderate, % major, % other, % of collisions towed; the drain is 0 on all % run-days scanned (it drained on %)',
    round(v_fire, 4), v_n, round(v_old_fire, 4), round(v_minor, 4), round(v_mod, 4), round(v_major, 4), round(v_other, 4),
    round(v_towed_share, 4), v_scanned, v_drained;
END $v1$;

-- ── V2: the definitions as written, the grants unchanged ──
DO $v2$
BEGIN
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_maybe_incident(bigint,text,numeric,numeric,numeric,numeric)'::regprocedure))
       <> 'b9ad369159d990015b7bc36635d7a258'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_twin_arrival_soc_drain(uuid,timestamptz)'::regprocedure))
       <> '3b71e8afbd96b62657ee4f73524d17f1' THEN
    RAISE EXCEPTION '0696 V2 FAILED: a definition is not as written';
  END IF;
  IF NOT has_function_privilege('service_role', 'twin.ottoq_sim_maybe_incident(bigint,text,numeric,numeric,numeric,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION '0696 V2 FAILED: the incident draw lost its grants';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0696_the_twins_roads_crash_at_the_filed_rate_and_the_cold_is_counted_once', true, true,
  'G408, G410 (Part A items 2 and 4). twin.ottoq_sim_maybe_incident: collisions at the CPUC-filed 291 over 28,143,285 '
  'miles, 647 of 1,211 towed (NHTSA), 2 of 291 severe; other incidents at 9e-8 a mile, as before. '
  'ottoq_twin_arrival_soc_drain returns 0: the driving physics carries the temperature once. No regime row: '
  'ottoq_evidence_regimes admits only charge_time_v2, whose world this does not change; return_v1''s is recorded as a '
  'follow-up in FINDINGS. A change in what the twin draws: TRUE/TRUE, riding 0657''s recertification.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 11:37:46 UTC (6:37 AM CT), version 20261010113746 ═════════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 9eeaa49; the ledger's stored statement is that file byte for
--   byte (md5 c6a024ac4a36c2d666b99ff75816fe12, 16,968 characters, 17,742 bytes). P1, V1, V2 passed in the apply's
--   transaction. Read after: the incident draw's source md5 b9ad369159d990015b7bc36635d7a258 and the drain's
--   3b71e8afbd96b62657ee4f73524d17f1 as written; snapshot 0696_pre holds both old definitions; lineage TRUE/TRUE, the
--   recert floor now 11:37:46 UTC; the recert runner (cron job 746) still paused for 0698 (read 11:38:03 UTC).
