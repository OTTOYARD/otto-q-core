-- migration-version: 20260927150822
-- migration-name:    kpi_four_counts_the_technicians_and_divides_by_the_cars_that_came_in
--
-- 0528  **G253: KPI 4, "human interventions per asset-turn", never counted a technician, and divided by bookings.
--       On the day's full run it read 0.000 while technicians started or finished 130 tasks on 219 cars that came in.
--       Its numerator now counts the technicians' work, by the lane each service declares, and its denominator the
--       cars that came in; the booking count stays beside it as the audit.** `db/checks/0396`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The numerator was the run's events whose actor is a person (`ottoq_kpi_touch_actor_types`, 0213) plus decisions a
--   person overrode (0391). The twin records a technician's work on the visit's atoms and never as an event, so the one
--   human actor that has ever appeared in `ottoq_events` is `command_center_operator` -- 26,126 events on 588 runs, all
--   deferred-service and technician approvals -- and `depot_tech`, which 0213 added as "the obvious name for a physical
--   touch", has never been written once (0396 §1). On `6ddd827e` the KPI read 0 touches while technicians did 90 cabin
--   tasks, 18 exterior tasks, 17 deep cleans and 5 service-bay jobs.
--   The denominator was 0184's: bookings in state `done`, the count 0527 (G252) retired from KPI 2 because it moves with
--   booking length. 498 on `6ddd827e`, against 219 cars that came in.
--   And a zero numerator hides from the learner: the dial verdict divides each guardrail's change by the control's value
--   (`NULLIF(abs(a), 0)`), so a KPI reading 0 in the control drops out of the guardrails altogether. On every G240 pair
--   KPI 4 guarded nothing (0396 §2).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   A touch is still a person acting on the asset. The numerator adds the technicians' work: an atom of a service
--   whose lane (`service_cadence_policy.lane`, one per service) a person works, started or finished and not cancelled,
--   unless the atom names a performer `ottoq_kpi_touch_actor_types` classifies as not a person. Which lanes a person
--   works is DATA, in the new `ottoq_kpi_touch_lanes`, read off the engine's own labour model
--   (`ottoq_start_concurrent_atoms`: a general technician for cabin and exterior work unless the charger's sensors do
--   it; a wash supervisor watches the automatic wash and does not work on the car) -- so a pack with other lanes
--   classifies its own, and the view never names a lane. `charger_sensors` (0511) is classified as not a person.
--   Bay work records no start: its atoms go straight to `done` with a `done_at` (0396 §3), which is why "started or
--   finished" and not "started".
--   The denominator is the cars that came in: `vehicle.state_changed` events to `arrived_at_gate`, from the signed event
--   stream. An asset-turn begins when a car comes in, and every touch counted belongs to one. On the A/B-harness arms
--   the count equals both the dispatch returns and the visits (116, 115, 215); on operator runs it is the fuller count,
--   since cars that start the day on the road have no dispatch row in the run (219 arrivals against 208 returns on
--   `6ddd827e`).
--   The eight columns keep their names, types and order; `turns` is now the arrivals and `touch_events` includes the
--   technicians. Appended: `touch_events_technician` and `bookings_done` (0184's denominator, exactly), so the
--   pre-0528 headline is (touch_events_operator + touch_events_override) / bookings_done: V1 proves it on eleven
--   reference runs, and 0396 §4 on every finished operator, production and A/B-harness run held before the apply.
--   `ottoq_kpi_five_raw`'s audit carries both new columns, and its
--   reversibility note is corrected -- including the KPI 2 sentence, stale since 0527.
--   Runs only (`sim_run_id IS NOT NULL`), as 0527: the one command, the dial metrics and the run-dial capture read one
--   run; the unrun rows the old view grouped under NULL had no reader.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart left NULL (restarts) ═════════════════════════════════════════════
--
--   No certification atom reads a KPI. It changes what every dial experiment's KPI 4 guardrail measures, so it restarts
--   them -- at no cost today: no pair has run since 0527 restarted them at 14:07 UTC, and the next window opens at
--   06:00 UTC (1:00 AM CT).

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0528 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_cols text; v_raw text;
BEGIN
  IF position('0528' IN COALESCE(obj_description('public.ottoq_kpi_touch_events_per_turn'::regclass), '')) > 0
     OR to_regclass('public.ottoq_kpi_touch_lanes') IS NOT NULL THEN
    RAISE EXCEPTION '0528 P2: already applied';
  END IF;
  -- the view is 0391's, column for column, so CREATE OR REPLACE can keep every column and append
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_kpi_touch_events_per_turn'::regclass AND a.attnum > 0;
  IF v_cols IS DISTINCT FROM 'sim_run_id:uuid,touch_events:bigint,turns:bigint,touch_events_per_turn:numeric,'
       'bookings_not_a_turn:bigint,touch_events_operator:bigint,touch_events_override:bigint,'
       'touch_events_override_flag_only:bigint' THEN
    RAISE EXCEPTION '0528 P2: the view''s columns are not 0391''s: %', v_cols;
  END IF;
  -- its one reader is the one command; the dial metrics and the run-dial capture read that
  IF (SELECT array_agg(p.oid::regprocedure::text ORDER BY 1) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc LIKE '%ottoq_kpi_touch_events_per_turn%')
     IS DISTINCT FROM ARRAY['ottoq_kpi_five_raw(uuid)']
     OR EXISTS (SELECT 1 FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid
                 WHERE d.refobjid = 'public.ottoq_kpi_touch_events_per_turn'::regclass
                   AND r.ev_class <> 'public.ottoq_kpi_touch_events_per_turn'::regclass) THEN
    RAISE EXCEPTION '0528 P2: something besides ottoq_kpi_five_raw reads the view';
  END IF;
  -- no certification atom reads a KPI
  IF pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure) ~* 'kpi' THEN
    RAISE EXCEPTION '0528 P2: the determinism pair reads a KPI; this is not forces_recert FALSE';
  END IF;
  -- the performer this file classifies is not classified yet
  IF EXISTS (SELECT 1 FROM public.ottoq_kpi_touch_actor_types WHERE actor_type = 'charger_sensors') THEN
    RAISE EXCEPTION '0528 P2: charger_sensors is already classified';
  END IF;
  -- every service an atom names on the runs the KPI is read on is declared, with a lane, so no atom falls out of the join
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
               JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
              WHERE r.run_by IN ('operator_demo', 'production_live', 'ab_harness')
                AND NOT EXISTS (SELECT 1 FROM public.service_cadence_policy c WHERE c.svc = a->>'svc' AND c.lane IS NOT NULL)) THEN
    RAISE EXCEPTION '0528 P2: an atom names a service with no declared lane';
  END IF;
  -- the audit block and the note are the ones this file patches, each once
  v_raw := pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure);
  IF (length(v_raw) - length(replace(v_raw, '''touch_events_override_flag_only'', touch_events_override_flag_only)', '')))
       / length('''touch_events_override_flag_only'', touch_events_override_flag_only)') <> 1
     OR (length(v_raw) - length(replace(v_raw, 'KPI 2 audit.turns_completed + audit.bookings_not_a_turn is the pre-0183 numerator; KPI 4 audit.turns + audit.bookings_not_a_turn is the pre-0184 denominator.', '')))
       / length('KPI 2 audit.turns_completed + audit.bookings_not_a_turn is the pre-0183 numerator; KPI 4 audit.turns + audit.bookings_not_a_turn is the pre-0184 denominator.') <> 1
     OR (length(v_raw) - length(replace(v_raw, 'audit.touch_events_operator + audit.touch_events_override must equal audit.touch_events, or', '')))
       / length('audit.touch_events_operator + audit.touch_events_override must equal audit.touch_events, or') <> 1 THEN
    RAISE EXCEPTION '0528 P2: ottoq_kpi_five_raw''s KPI 4 audit or its note is not as this file expects';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0528_pre', 'view', 'public', 'ottoq_kpi_touch_events_per_turn',
       pg_get_viewdef('public.ottoq_kpi_touch_events_per_turn'::regclass, true),
       md5(pg_get_viewdef('public.ottoq_kpi_touch_events_per_turn'::regclass, true))
UNION ALL
SELECT '0528_pre', 'function', 'public', 'ottoq_kpi_five_raw',
       pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure));

-- what the view read before, on the eleven reference runs -- the day's three full operator runs and both arms of G240's
-- pairs 76, 78 and 80 and the energy experiment's pair 81 -- to prove below that the booking audit and the untouched
-- terms reproduce it. Eleven and not every run held: each run's read scans all its events two or three times (no index
-- has the event type beside the run), and 55 runs of it did not fit in one statement; the comparison over every
-- finished operator, production and A/B-harness run was run in chunks before the apply (0396 §4). Finished runs only,
-- since a live run's rows move between this read and the proof -- the dry run's first attempt failed on the validation
-- run then ticking. One run per statement with the run as a literal: joined to a run list, the old view reads them all.
CREATE TEMP TABLE v0528_before (
  sim_run_id uuid, touch_events bigint, turns bigint, touch_events_per_turn numeric, bookings_not_a_turn bigint,
  touch_events_operator bigint, touch_events_override bigint, touch_events_override_flag_only bigint) ON COMMIT DROP;
DO $before$
DECLARE v_run uuid;
BEGIN
  FOR v_run IN SELECT r.sim_run_id FROM public.ottoq_sim_runs r
                WHERE r.status NOT IN ('running', 'paused')
                  AND (r.sim_run_id IN ('6ddd827e-b549-43cf-8154-4d1bfb20cabf', '4bc19d29-790c-4cb0-9e2e-ae090a7da57b')
                       OR left(r.sim_run_id::text, 8) = 'c4afb873'
                       OR r.sim_run_id IN (SELECT p.run_a FROM public.ottoq_dial_pair_ledger p WHERE p.pair_id IN (76, 78, 80, 81))
                       OR r.sim_run_id IN (SELECT p.run_b FROM public.ottoq_dial_pair_ledger p WHERE p.pair_id IN (76, 78, 80, 81))) LOOP
    EXECUTE format('INSERT INTO v0528_before SELECT sim_run_id, touch_events, turns, touch_events_per_turn, bookings_not_a_turn, '
                   'touch_events_operator, touch_events_override, touch_events_override_flag_only '
                   'FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = %L', v_run);
  END LOOP;
END $before$;

-- ── which lanes a person works: data, not a list in the view ──
CREATE TABLE public.ottoq_kpi_touch_lanes (
  lane          text PRIMARY KEY,
  human_touch   boolean NOT NULL,
  note          text NOT NULL,
  classified_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.ottoq_kpi_touch_lanes IS
  '0528 (G253). KPI 4''s numerator counts the work of a person on the asset. A service''s lane is declared in '
  'service_cadence_policy.lane; this table says which lanes a person works, read off the engine''s own labour model '
  '(ottoq_start_concurrent_atoms). An atom in a human lane is a touch unless it names a performer that '
  'ottoq_kpi_touch_actor_types classifies as not a person. A pack with other lanes classifies its own here.';
INSERT INTO public.ottoq_kpi_touch_lanes (lane, human_touch, note) VALUES
  ('cabin',       true,  'the general technician pool: one technician, one car at a time (ottoq_start_concurrent_atoms). '
                         'An interior inspection or cabin triage the charger''s sensors perform names them (performed_by) '
                         'and is not a touch.'),
  ('exterior',    true,  'the general technician pool, as cabin: sensor clean, perimeter walkaround (0383)'),
  ('detail',      true,  'detail staff: an interior deep clean is a person''s work'),
  ('service_bay', true,  'service technicians: sensor calibration, mechanical PM, fault and cosmetic repair'),
  ('anchor',      false, 'the charge: plugged by the charging robot (0511, G236, decided 2026-09-27). The founder-spec '
                         'comment in ottoq_start_concurrent_atoms that has a technician plug the car in predates it.'),
  ('gate',        false, 'the readiness check at departure: the twin''s gate step (twin.ottoq_sim_advance_visit_atoms), '
                         'metered against no staff pool'),
  ('wash_bay',    false, 'the automatic wash: a wash supervisor watches the bay and does not work on the car '
                         '(ottoq_start_concurrent_atoms'' own comment)'),
  ('digital',     false, 'over the air: no person and no stall');

INSERT INTO public.ottoq_kpi_touch_actor_types (actor_type, human_actor, note, classified_at)
VALUES ('charger_sensors', false,
        'the charger''s own cabin sensors (0511, G236): an atom whose performed_by names them took no person (0528)', now());

-- ── the view ──
CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn AS
WITH per_run AS (
  SELECT u.sim_run_id,
         count(*) FILTER (WHERE u.src = 'arrived')              AS arrivals,
         count(*) FILTER (WHERE u.src = 'booked' AND u.done)    AS bookings_done,
         count(*) FILTER (WHERE u.src = 'booked' AND NOT u.done) AS bookings_not_done,
         count(*) FILTER (WHERE u.src = 'worked')               AS technician
    FROM (
          -- a car coming in, from the signed event stream; `|| ''` keeps the planner on the per-run index (0527)
          SELECT 'arrived'::text AS src, e.sim_run_id, NULL::boolean AS done
            FROM public.ottoq_events e
           WHERE (e.event_type || '') = 'vehicle.state_changed' AND e.sim_run_id IS NOT NULL
             AND e.payload->'diff'->'current_state'->>'to' = 'arrived_at_gate'
          UNION ALL
          -- 0184's denominator, kept as the audit
          SELECT 'booked', b.sim_run_id, b.state = 'done'
            FROM public.ottoq_stall_bookings b
           WHERE b.sim_run_id IS NOT NULL
          UNION ALL
          -- a person's work: a started or finished atom in a lane a person works, unless a non-person performed it
          SELECT 'worked', vn.sim_run_id, NULL
            FROM public.ottoq_visit_needs vn
            CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
            JOIN public.service_cadence_policy c ON c.svc = a->>'svc'
            JOIN public.ottoq_kpi_touch_lanes l ON l.lane = c.lane AND l.human_touch
           WHERE vn.sim_run_id IS NOT NULL
             AND COALESCE(a->>'status', 'pending') <> 'cancelled'
             AND (a->>'started_at' IS NOT NULL OR a->>'done_at' IS NOT NULL)
             AND NOT EXISTS (SELECT 1 FROM public.ottoq_kpi_touch_actor_types k
                              WHERE k.actor_type = a->>'performed_by' AND NOT k.human_actor)
         ) u
   GROUP BY u.sim_run_id
), counted AS (
  SELECT p.sim_run_id, p.arrivals, p.bookings_done, p.bookings_not_done, p.technician,
         (SELECT count(*) FROM public.ottoq_events e
           WHERE e.sim_run_id = p.sim_run_id
             AND e.actor_type IN (SELECT k.actor_type FROM public.ottoq_kpi_touch_actor_types k WHERE k.human_actor)) AS n_op,
         (SELECT count(*) FROM public.ottoq_decisions d
           WHERE d.sim_run_id = p.sim_run_id AND d.override_id IS NOT NULL) AS n_ov,
         (SELECT count(*) FROM public.ottoq_decisions d
           WHERE d.sim_run_id = p.sim_run_id AND d.overridden AND d.override_id IS NULL) AS n_ov_flag_only
    FROM per_run p
)
SELECT sim_run_id,
       n_op + n_ov + technician                                                                   AS touch_events,
       arrivals                                                                                   AS turns,
       CASE WHEN arrivals > 0 THEN round((n_op + n_ov + technician)::numeric / arrivals::numeric, 3) END
                                                                                                  AS touch_events_per_turn,
       bookings_not_done                                                                          AS bookings_not_a_turn,
       n_op                                                                                       AS touch_events_operator,
       n_ov                                                                                       AS touch_events_override,
       n_ov_flag_only                                                                             AS touch_events_override_flag_only,
       -- 0528 (G253)
       technician                                                                                 AS touch_events_technician,
       bookings_done
  FROM counted;

COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  'Canonical KPI 4 (CLAUDE.md 2.9), "human interventions per asset-turn". 0528 (G253): the numerator is a person '
  'acting on the asset -- events whose actor is a person (ottoq_kpi_touch_actor_types, 0213), decisions a person '
  'overrode (override_id, 0391), and, new, the technicians'' work (touch_events_technician): each atom of a service '
  'whose lane (service_cadence_policy.lane) ottoq_kpi_touch_lanes says a person works, started or finished and not '
  'cancelled, unless it names a performer classified as not a person (charger_sensors). Before 0528 the twin''s '
  'technicians were invisible: they write atoms, never events, and the KPI read 0 on 6ddd827e while they did 130 '
  'tasks (db/checks/0396). The denominator is the cars that came in -- vehicle.state_changed to arrived_at_gate, from '
  'the signed event stream -- where 0184 counted bookings in state done, which moves with booking length (G252). '
  'bookings_done is that count, kept as the audit: (touch_events_operator + touch_events_override) / bookings_done is '
  'the pre-0528 headline exactly. touch_events_override_flag_only is the shield''s own safe default (0391), excluded. '
  'Runs only.';

-- ── the one command's audit carries both counts, and its reversibility note says what is true ──
DO $patch_raw$
DECLARE
  v_def text;
  v_old1 text := $o$'touch_events_override_flag_only', touch_events_override_flag_only)$o$;
  v_new1 text := $n$'touch_events_override_flag_only', touch_events_override_flag_only,
            -- 0528 (G253): the technicians' work in the numerator, and the booking count 0184-0527 divided by
            'touch_events_technician', touch_events_technician, 'bookings_done', bookings_done)$n$;
  v_old2 text := 'KPI 2 audit.turns_completed + audit.bookings_not_a_turn is the pre-0183 numerator; KPI 4 audit.turns + audit.bookings_not_a_turn is the pre-0184 denominator.';
  v_new2 text := 'KPI 2 audit.bookings_done + audit.bookings_not_a_turn is the pre-0183 numerator, and audit.bookings_done alone the 0183-0527 one (0527 counts a car leaving a point); KPI 4 audit.bookings_done + audit.bookings_not_a_turn is the pre-0184 denominator, and audit.bookings_done alone the 0184-0527 one (0528 divides by the cars that came in).';
  v_old3 text := 'audit.touch_events_operator + audit.touch_events_override must equal audit.touch_events, or';
  v_new3 text := 'audit.touch_events_operator + audit.touch_events_override + audit.touch_events_technician must equal audit.touch_events (0528 added the technicians), or';
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  IF n <> 1 THEN RAISE EXCEPTION '0528: audit patch matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN RAISE EXCEPTION '0528: note patch 1 matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old3, ''))) / length(v_old3);
  IF n <> 1 THEN RAISE EXCEPTION '0528: note patch 2 matched % times, not once', n; END IF;
  EXECUTE replace(replace(replace(v_def, v_old1, v_new1), v_old2, v_new2), v_old3, v_new3);
END $patch_raw$;

DO $verify$
DECLARE v_view text; v_raw text; v_run uuid; v_n int := 0;
BEGIN
  v_view := pg_get_viewdef('public.ottoq_kpi_touch_events_per_turn'::regclass, true);
  v_raw  := pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure);
  -- V1 (a): on each reference run read a moment ago, the untouched terms are unchanged, bookings_done is the old
  --     denominator, (operator + override) / bookings_done is the old headline, and the numerator adds the technicians
  FOR v_run IN SELECT sim_run_id FROM v0528_before LOOP
    IF EXISTS (SELECT 1 FROM v0528_before b
                 LEFT JOIN (SELECT * FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = v_run) t ON true
                WHERE b.sim_run_id = v_run
                  AND (t.bookings_done IS DISTINCT FROM b.turns
                       OR t.bookings_not_a_turn IS DISTINCT FROM b.bookings_not_a_turn
                       OR t.touch_events_operator IS DISTINCT FROM b.touch_events_operator
                       OR t.touch_events_override IS DISTINCT FROM b.touch_events_override
                       OR t.touch_events_override_flag_only IS DISTINCT FROM b.touch_events_override_flag_only
                       OR (CASE WHEN t.bookings_done > 0
                                THEN round((t.touch_events_operator + t.touch_events_override)::numeric / t.bookings_done, 3) END)
                          IS DISTINCT FROM b.touch_events_per_turn
                       OR t.touch_events IS DISTINCT FROM t.touch_events_operator + t.touch_events_override + t.touch_events_technician)) THEN
      RAISE EXCEPTION '0528 V1: run %: the audit does not reproduce the pre-0528 view', v_run;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 11 THEN RAISE EXCEPTION '0528 V1: % reference runs compared, not 11', v_n; END IF;
  -- V1 (b): the old eight columns keep their names, types and order, and two are appended
  IF (SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
        FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_kpi_touch_events_per_turn'::regclass AND a.attnum > 0)
     IS DISTINCT FROM 'sim_run_id:uuid,touch_events:bigint,turns:bigint,touch_events_per_turn:numeric,'
       'bookings_not_a_turn:bigint,touch_events_operator:bigint,touch_events_override:bigint,'
       'touch_events_override_flag_only:bigint,touch_events_technician:bigint,bookings_done:bigint' THEN
    RAISE EXCEPTION '0528 V1: the view''s columns are not as intended';
  END IF;
  -- V1 (c): every declared lane is classified, so no service silently falls out of the numerator
  IF EXISTS (SELECT DISTINCT c.lane FROM public.service_cadence_policy c WHERE c.lane IS NOT NULL
             EXCEPT SELECT l.lane FROM public.ottoq_kpi_touch_lanes l) THEN
    RAISE EXCEPTION '0528 V1: a declared lane is not classified';
  END IF;
  -- V1 (d): the view reads arrivals and lanes; the one command's audit carries both counts; its note is corrected
  IF position('arrived_at_gate' IN v_view) = 0 OR position('ottoq_kpi_touch_lanes' IN v_view) = 0
     OR position('''touch_events_technician'', touch_events_technician, ''bookings_done'', bookings_done)' IN v_raw) = 0
     OR position('audit.bookings_done alone the 0184-0527 one' IN v_raw) = 0
     OR position('audit.touch_events_technician must equal audit.touch_events' IN v_raw) = 0
     OR position('KPI 2 audit.turns_completed + audit.bookings_not_a_turn' IN v_raw) > 0 THEN
    RAISE EXCEPTION '0528 V1: the view or the one command is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule): forces_recert FALSE, forces_dial_restart left NULL.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0528_kpi_four_counts_the_technicians_and_divides_by_the_cars_that_came_in', false,
  'KPI 4 only, read by the one command, the dial arm metrics and the run-dial capture; no certification atom reads a '
  'KPI. The numerator counts the technicians'' work by declared lane, the denominator the cars that came in (G253). It '
  'changes what every dial experiment''s KPI 4 guardrail measures, so forces_dial_restart is left NULL.', now())
ON CONFLICT (name) DO NOTHING;

-- V3: read-only. (a) 6ddd827e: 219 cars in, 130 technician tasks, 0 other touches, 0.594 per turn, 498 bookings
--     done. (b) G240's pair 76, both arms: 116 in, 123 tasks, 1.060. (c) The energy experiment's pair 81, both arms: 215
--     in, 291 tasks, 77 command-centre approvals, 1.712. (d) The one command reads 6ddd827e in under 2 seconds, with the
--     technicians in its audit.
DO $v3$
DECLARE
  v_msg text; v_t0 timestamptz; v_ms numeric; v_raw jsonb; v_arms text; t record; a record;
BEGIN
  BEGIN
    SELECT * INTO t FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = '6ddd827e-b549-43cf-8154-4d1bfb20cabf';
    IF t.turns <> 219 OR t.touch_events_technician <> 130 OR t.touch_events <> 130 OR t.touch_events_per_turn <> 0.594
       OR t.bookings_done <> 498 THEN
      RAISE EXCEPTION '0528 V3 FAILED (a): 6ddd827e read %', to_jsonb(t);
    END IF;
    -- one arm per statement: read through a lateral join, the planner aggregates the view over every run held and
    -- scans all 1.8M events (0396 §4); with the run as a parameter it stays on the run's index
    FOR a IN SELECT p.pair_id, arm.a, arm.run FROM public.ottoq_dial_pair_ledger p
               CROSS JOIN LATERAL (VALUES ('A', p.run_a), ('B', p.run_b)) AS arm(a, run)
              WHERE p.pair_id IN (76, 81) ORDER BY p.pair_id, arm.a LOOP
      SELECT * INTO t FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = a.run;
      v_arms := concat_ws(' ', v_arms, format('%s%s:%s/%s/%s/%s', a.pair_id, a.a, t.turns, t.touch_events_technician,
                                              t.touch_events_operator, t.touch_events_per_turn));
    END LOOP;
    IF v_arms IS DISTINCT FROM '76A:116/123/0/1.060 76B:116/123/0/1.060 81A:215/291/77/1.712 81B:215/291/77/1.712' THEN
      RAISE EXCEPTION '0528 V3 FAILED (b, c): %', v_arms;
    END IF;
    v_t0 := clock_timestamp();
    v_raw := public.ottoq_kpi_five_raw('6ddd827e-b549-43cf-8154-4d1bfb20cabf');
    v_ms := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
    IF v_ms > 2000 OR (v_raw->'audit'->'touch_events_per_turn'->>'touch_events_technician')::int <> 130
       OR (v_raw->'audit'->'touch_events_per_turn'->>'bookings_done')::int <> 498
       OR (v_raw->>'touch_events_per_turn')::numeric <> 0.594 THEN
      RAISE EXCEPTION '0528 V3 FAILED (d): the one command took % ms and read %', round(v_ms), v_raw->'audit'->'touch_events_per_turn';
    END IF;
    RAISE EXCEPTION '0528 V3 PASSED: 6ddd827e 130 tasks on 219 cars in, 0.594 (was 0.000 over 498 bookings); %; the one command in % ms',
      v_arms, round(v_ms);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0528 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0528 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0528_pre' -- the view's through DROP VIEW
--   public.ottoq_kpi_touch_events_per_turn then CREATE VIEW ... AS <definition> (CREATE OR REPLACE cannot remove the two
--   appended columns), the function's as is; then DELETE FROM ottoq_kpi_touch_actor_types WHERE actor_type =
--   'charger_sensors' and DROP TABLE public.ottoq_kpi_touch_lanes.
COMMIT;
