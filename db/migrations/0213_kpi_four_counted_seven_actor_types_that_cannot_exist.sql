-- migration-version: PENDING
-- migration-name:    kpi_four_counted_seven_actor_types_that_cannot_exist
-- ---------------------------------------------------------------------------
-- *** DRAFT — NOT APPLIED. No APPLIED footer, no lineage row in the database. ***
-- Written 2026-09-08 while round 24 was mid-flight; the preconditions below
-- refuse while r24_* cron jobs exist, which is why it is committed unapplied
-- rather than held back. Do not read any reading in this file as taken: the
-- only measurements here are the BEFORE state (the seven forbidden types), and
-- those were taken. Everything the A4 block asserts is a prediction until it
-- runs. Apply after the round, then append the APPLIED footer with what the
-- catalog actually said, exactly as 0209..0212 do.
-- ---------------------------------------------------------------------------
-- 0213 — KPI-4 counted seven human actor types the events table forbids.
--
-- WHY (G17; found 2026-09-08 while checking whether the never-emitted
-- `touch_event` type had broken KPI-4 — it had not, and this is what turned up
-- instead).
--
-- public.ottoq_kpi_touch_events_per_turn is KPI 4 of CLAUDE.md 2.9, "human
-- interventions per asset-turn". Migration 0044 defined its touch set as eight
-- actor types:
--
--   command_center_operator, depot_staff, technician, charging_tech,
--   cleaning_tech, maintenance_tech, yard_supervisor, ops_manager
--
-- ottoq_events CHECKs actor_type against a twenty-value vocabulary. SEVEN OF
-- THOSE EIGHT ARE NOT IN IT and therefore cannot ever appear in the table:
-- charging_tech, cleaning_tech, depot_staff, maintenance_tech, ops_manager,
-- technician, yard_supervisor. Only command_center_operator is legal.
--
-- And the constraint's real human actors are all MISSING from the KPI:
-- depot_supervisor, depot_tech, fleet_operator_admin, oem_admin_console,
-- otto_response_agent, ottow_driver.
--
-- So a depot technician's intervention, recorded under `depot_tech` — the legal
-- name, the obvious name — is not a touch, while the view lists seven names
-- that the database will reject on insert. A filter that reads as thorough at
-- eight entries is seven-eighths unsatisfiable.
--
-- WHAT THIS CHANGES, CORRECTED 2026-09-08 10:10 BEFORE APPLYING. The draft said
-- "this does not change any number" and listed the newly-counted types as
-- having no events. It missed one. `ottow_dispatcher` has **6 events** —
-- `recall_refused`, data_source production, 2026-09-08 07:03, three each in
-- sim runs 1e696479 and aa6a27dd, which are the G7 work-side-refusal exercise
-- from earlier the same day. Counting them is CORRECT: a recall refused by a
-- human dispatcher is a human intervention, which is what KPI-4 measures. But
-- it is a change, and A4 below now names it instead of the header denying it.
--
-- The seven impossible terms do contribute zero either way, and the other six
-- newly-counted types have no events. The committed 24h KPI baseline cannot
-- move at all: metrics/kpi_gate.py runs in CI over committed artefacts with no
-- database, so nothing here can reach it. What moves is the LIVE view, for two
-- test runs, by three touches each.
--
-- THE FIX IS THE PIN, NOT THE LIST. Rewriting the enumeration would leave the
-- next author free to drift it again, which is how it got here. 0213 derives
-- the touch set from a named constant table and adds
-- ottoq_kpi_touch_actor_types, then a check that every actor type the KPI
-- counts is one the events table permits. A list that cannot be inserted is a
-- claim that cannot be tested.
--
-- WHY human_actor IS A COLUMN AND NOT A COMMENT: the twenty permitted actor
-- types split into humans, machines and system identities, and only the first
-- group is a "touch". That judgement is data now, so a new actor type added to
-- the CHECK must be classified rather than silently omitted.
--
-- forces_recert: FALSE. A view definition and a lookup table. No decide-path
-- function changes, and KPI views are not in the pair verdict.
--
-- APPLY AFTER ROUND 24. While r24_* cron jobs exist the preconditions refuse,
-- by design.
-- ---------------------------------------------------------------------------

BEGIN;

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- The standing constraint: never apply while a certification pair is running or
-- scheduled. Until 2026-09-08 that was enforced by the operator remembering it,
-- for three of the four migrations queued behind round 25. It is a file now.
--
-- All three checks are needed and the middle one is the load-bearing one.
-- ottoq_sim_runs cannot see an in-flight pair AT ALL: both arms run inside one
-- transaction, so their rows are uncommitted and invisible until it ends. And
-- cron.job_run_details reports an in-flight pair of this shape as
-- status='succeeded', return_message='SET', duration ~1 s, because the job
-- command is two statements and the row reflects the first (db/canons/round25.md).
-- pg_stat_activity is the only authority.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0213 P-: certification jobs are still scheduled (%) — migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0213 P-: a determinism pair is running right now';
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0213 P-: % sim run(s) are in flight', v_runs;
  END IF;

  RAISE NOTICE '0213 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

DO $pre$
BEGIN
  IF to_regclass('public.ottoq_kpi_touch_events_per_turn') IS NULL THEN
    RAISE EXCEPTION '0213: KPI-4 view is missing';
  END IF;
  RAISE NOTICE '0213 pre: KPI-4 present';
END $pre$;

-- A1. THE VOCABULARY, AS DATA -----------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_kpi_touch_actor_types (
  actor_type   text PRIMARY KEY,
  human_actor  boolean NOT NULL,
  note         text NOT NULL,
  classified_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_kpi_touch_actor_types IS
  '0213 (G17): which ottoq_events.actor_type values count as a human touch for '
  'KPI-4. Every row must be a value the ottoq_events actor_type CHECK permits — '
  'ottoq_assert_kpi_touch_vocabulary() enforces that. Before 0213 the KPI '
  'enumerated seven types the CHECK forbids and omitted every one it allows '
  'except command_center_operator.';

INSERT INTO public.ottoq_kpi_touch_actor_types (actor_type, human_actor, note) VALUES
  ('command_center_operator', true,  'a person in the command centre; the only human type KPI-4 counted before 0213'),
  ('depot_tech',              true,  'a technician at the depot — the obvious name for a physical touch, and omitted until 0213'),
  ('depot_supervisor',        true,  'a supervisor at the depot'),
  ('fleet_operator_admin',    true,  'the operator''s admin acting on an asset'),
  ('oem_admin_console',       true,  'a person acting through the OEM console'),
  ('otto_response_agent',     true,  'a dispatched response agent — a physical intervention by definition'),
  ('ottow_driver',            true,  'a human driver on the work side'),
  ('ottow_dispatcher',        true,  'a human dispatcher on the work side'),
  ('fleet_operator_viewer',   false, 'read-only; looking is not touching'),
  ('oem_dispatch_webhook',    false, 'a machine callback'),
  ('ottoq_engine',            false, 'this engine'),
  ('system_scheduler',        false, 'a scheduler'),
  ('external_sensor',         false, 'a sensor'),
  ('ocpp_charger',            false, 'a charger'),
  ('av_vehicle',              false, 'the asset itself'),
  ('bess_controller',         false, 'a controller'),
  ('solar_controller',        false, 'a controller'),
  ('migration_script',        false, 'a migration'),
  ('system',                  false, 'the system'),
  ('unknown',                 false, 'unattributed — deliberately NOT a touch: counting unknown as human would inflate KPI-4 with every unattributed row')
ON CONFLICT (actor_type) DO NOTHING;

-- A2. THE PIN: A COUNTED TYPE MUST BE AN INSERTABLE TYPE ---------------------
CREATE OR REPLACE FUNCTION public.ottoq_assert_kpi_touch_vocabulary()
RETURNS TABLE(classified int, human int, not_insertable text[], unclassified text[])
LANGUAGE plpgsql STABLE
SET search_path TO 'public', 'extensions'
AS $v$
DECLARE v_allowed text[]; v_def text; v_n int;
BEGIN
  --: an unordered LIMIT 1 over the catalog is the same defect this repo spent
  --: 0216 and 0221 on. If more than one constraint mentions actor_type, the pin
  --: would silently pin against whichever the heap returned; refuse instead.
  SELECT count(*) INTO v_n FROM pg_constraint c
   WHERE c.conrelid = 'public.ottoq_events'::regclass
     AND pg_get_constraintdef(c.oid) ILIKE '%actor_type%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ottoq_assert_kpi_touch_vocabulary: % constraints on ottoq_events mention '
                    'actor_type, expected exactly 1 — the pin has no unambiguous thing to pin '
                    'against and must not report success', v_n;
  END IF;
  SELECT pg_get_constraintdef(c.oid) INTO v_def
    FROM pg_constraint c
   WHERE c.conrelid = 'public.ottoq_events'::regclass
     AND pg_get_constraintdef(c.oid) ILIKE '%actor_type%'
   ORDER BY c.conname
   LIMIT 1;

  --: the permitted set, read out of the live constraint rather than restated
  SELECT array_agg(m[1]) INTO v_allowed
    FROM regexp_matches(v_def, '''([a-z_]+)''::text', 'g') AS m;

  RETURN QUERY
  SELECT (SELECT count(*)::int FROM public.ottoq_kpi_touch_actor_types),
         (SELECT count(*)::int FROM public.ottoq_kpi_touch_actor_types WHERE human_actor),
         COALESCE((SELECT array_agg(t.actor_type ORDER BY t.actor_type)
                     FROM public.ottoq_kpi_touch_actor_types t
                    WHERE NOT (t.actor_type = ANY(v_allowed))), '{}'::text[]),
         COALESCE((SELECT array_agg(a ORDER BY a) FROM unnest(v_allowed) a
                    WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_kpi_touch_actor_types t
                                       WHERE t.actor_type = a)), '{}'::text[]);
END $v$;

COMMENT ON FUNCTION public.ottoq_assert_kpi_touch_vocabulary() IS
  '0213 (G17): reads the live ottoq_events actor_type CHECK and reports any KPI-4 '
  'touch type the table would reject (not_insertable) and any permitted type nobody '
  'has classified (unclassified). Both must be empty. It RAISES rather than returns '
  'when the constraint itself is missing, because a pin with nothing to pin against '
  'that reports success is the defect it exists to prevent.';

-- A3. THE VIEW READS THE TABLE -- AND CHANGES NOTHING ELSE ------------------
-- Deliberately a MINIMAL rewrite of the live definition. The first draft of
-- this migration also (a) dropped three output columns, which CREATE OR REPLACE
-- VIEW cannot do and would have aborted the migration, (b) widened `turns` from
-- state='done' to done/released/interrupted, which contradicts
-- ottoq_kpi_service_point_turns (KPI-2 counts state='done' and nothing else)
-- and would have moved the denominator, (c) turned the zero-turn case from NULL
-- into 0 via GREATEST(1, n), and (d) added security_invoker, which this view
-- does not have. None of those is the vocabulary defect. A migration titled
-- "the touch vocabulary is wrong" changes the touch vocabulary.
--
-- The ONLY difference from the live definition below: the hardcoded actor array
-- becomes a read of ottoq_kpi_touch_actor_types.
CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn AS
WITH turns AS (
  SELECT b.sim_run_id,
         count(*) FILTER (WHERE b.state = 'done'::text)  AS n,
         count(*) FILTER (WHERE b.state <> 'done'::text) AS not_a_turn
    FROM public.ottoq_stall_bookings b
   GROUP BY b.sim_run_id
), counted AS (
  SELECT t.sim_run_id, t.n, t.not_a_turn,
         CASE WHEN t.sim_run_id IS NOT NULL
              THEN (SELECT count(*) FROM public.ottoq_events e
                     WHERE e.sim_run_id = t.sim_run_id
                       AND e.actor_type IN (SELECT k.actor_type
                                              FROM public.ottoq_kpi_touch_actor_types k
                                             WHERE k.human_actor))
              ELSE (SELECT count(*) FROM public.ottoq_events e
                     WHERE e.sim_run_id IS NULL
                       AND e.actor_type IN (SELECT k.actor_type
                                              FROM public.ottoq_kpi_touch_actor_types k
                                             WHERE k.human_actor))
         END AS n_op,
         CASE WHEN t.sim_run_id IS NOT NULL
              THEN (SELECT count(*) FROM public.ottoq_decisions d
                     WHERE d.sim_run_id = t.sim_run_id
                       AND (d.overridden OR d.override_id IS NOT NULL))
              ELSE (SELECT count(*) FROM public.ottoq_decisions d
                     WHERE d.sim_run_id IS NULL
                       AND (d.overridden OR d.override_id IS NOT NULL))
         END AS n_ov
    FROM turns t
)
SELECT sim_run_id,
       n_op + n_ov AS touch_events,
       n AS turns,
       CASE WHEN n > 0 THEN round((n_op + n_ov)::numeric / n::numeric, 3) END AS touch_events_per_turn,
       not_a_turn AS bookings_not_a_turn,
       n_op AS touch_events_operator,
       n_ov AS touch_events_override
  FROM counted;

COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  'KPI 4 (CLAUDE.md 2.9): human interventions per asset-turn. Touch = signed events from actor '
  'types classified human in ottoq_kpi_touch_actor_types, plus overridden decisions. Turns = '
  'bookings in state done, the same definition ottoq_kpi_service_point_turns uses for KPI-2. '
  '0213 (G17): the actor list is a table pinned against the live ottoq_events CHECK, because the '
  'hardcoded list it replaced named seven types the table forbids and omitted every permitted '
  'human type but one. Nothing else about this view changed.';

-- A4. THE PIN MUST BE CLEAN AT APPLY TIME ------------------------------------
DO $chk$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.ottoq_assert_kpi_touch_vocabulary();
  IF array_length(r.not_insertable, 1) IS NOT NULL THEN
    RAISE EXCEPTION '0213 A4: these KPI-4 touch types are rejected by the events CHECK: %',
                    r.not_insertable;
  END IF;
  IF array_length(r.unclassified, 1) IS NOT NULL THEN
    RAISE EXCEPTION '0213 A4: these permitted actor types are unclassified: %', r.unclassified;
  END IF;
  RAISE NOTICE '0213 A4: % actor types classified, % human, none unclassified, none uninsertable',
               r.classified, r.human;
END $chk$;

-- A5. THE ONLY NUMBERS THAT MOVE ARE THE ONES WE CAN NAME --------------------
-- The view is already replaced by the time this runs, so this recomputes the
-- OLD operator-touch count and diffs it against the new view. Any run whose
-- count changes must be explained by an event carrying an actor type the old
-- hardcoded list did not name; a run that moves for any other reason means the
-- rewrite was not minimal, and the migration aborts.
--
-- Done as ONE grouped pass over ottoq_events rather than a correlated count per
-- run. A per-run correlated subquery keyed with IS NOT DISTINCT FROM is not
-- indexable, which is precisely the defect db/checks/0127 convicted; an
-- assertion is not exempt from the rule it is written alongside.
DO $a5$
DECLARE r record; v_rows int := 0; v_bad text := ''; v_named text := '';
BEGIN
  FOR r IN
    WITH ev AS (
      SELECT e.sim_run_id,
             count(*) FILTER (WHERE e.actor_type = ANY (ARRAY[
               'command_center_operator','depot_staff','technician','charging_tech',
               'cleaning_tech','maintenance_tech','yard_supervisor','ops_manager'])) AS n_old,
             string_agg(DISTINCT e.actor_type, ',') FILTER (
               WHERE e.actor_type IN (SELECT k.actor_type
                                        FROM public.ottoq_kpi_touch_actor_types k
                                       WHERE k.human_actor)
                 AND e.actor_type <> 'command_center_operator') AS newly_counted
        FROM public.ottoq_events e
       GROUP BY e.sim_run_id
    )
    SELECT v.sim_run_id, v.touch_events_operator AS n_new,
           COALESCE(ev.n_old, 0) AS n_old, ev.newly_counted
      FROM public.ottoq_kpi_touch_events_per_turn v
      LEFT JOIN ev ON ev.sim_run_id IS NOT DISTINCT FROM v.sim_run_id
     WHERE v.touch_events_operator IS DISTINCT FROM COALESCE(ev.n_old, 0)
  LOOP
    v_rows := v_rows + 1;
    IF r.newly_counted IS NULL THEN
      v_bad := v_bad || format(' %s(%s->%s, unexplained);',
                               left(r.sim_run_id::text,8), r.n_old, r.n_new);
    ELSE
      v_named := v_named || format(' %s(%s->%s via %s);',
                                   left(r.sim_run_id::text,8), r.n_old, r.n_new, r.newly_counted);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '0213 A5: run(s) changed with no newly-counted actor type to explain it:%  '
                    '-- the rewrite was not minimal', v_bad;
  END IF;
  IF v_rows = 0 THEN
    RAISE NOTICE '0213 A5: no run changed at all';
  ELSE
    RAISE NOTICE '0213 A5: % run(s) moved, every one explained by a newly-counted human actor:%',
                 v_rows, v_named;
  END IF;
END $a5$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0213_kpi_four_counted_seven_actor_types_that_cannot_exist', FALSE,
        'G17. KPI-4 counted eight human actor types, seven of which the ottoq_events actor_type '
        'CHECK forbids (charging_tech, cleaning_tech, depot_staff, maintenance_tech, ops_manager, '
        'technician, yard_supervisor), while omitting every permitted human type except '
        'command_center_operator — depot_tech among them. The list is now a table pinned against the '
        'live constraint by ottoq_assert_kpi_touch_vocabulary(), which raises rather than passing '
        'when the constraint is absent or ambiguous. The committed KPI baseline cannot move '
        '(metrics/kpi_gate.py runs over committed artefacts with no database), and in the live '
        'view exactly one newly-counted type has any events: ottow_dispatcher, 6 recall_refused '
        'rows across two 2026-09-08 test runs. A5 asserts that every run whose number moves is '
        'explained by a newly-counted actor type and aborts on any that is not. The first draft '
        'of this migration also dropped three view columns (which CREATE OR REPLACE VIEW cannot '
        'do), widened the turn denominator away from KPI-2''s state=done, and changed the '
        'zero-turn result from NULL to 0; none of that was the vocabulary defect and all of it '
        'was removed.',
        now());

COMMIT;
