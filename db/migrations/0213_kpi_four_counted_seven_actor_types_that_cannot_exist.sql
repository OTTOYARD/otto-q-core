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
-- WHAT THIS DOES NOT CHANGE: any number. The seven impossible terms contribute
-- zero either way, and no depot_tech / depot_supervisor / ottow_driver /
-- otto_response_agent / oem_admin_console / fleet_operator_admin event exists
-- yet. KPI-4 is BLIND, not wrong, and the committed 24h KPI baseline must not
-- move — metrics/kpi_gate.py is the test of that, not this comment.
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

DO $pre$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_') THEN
    RAISE EXCEPTION '0213: a certification round is scheduled; migrations wait for the round';
  END IF;
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0213: a sim run is in flight';
  END IF;
  IF to_regclass('public.ottoq_kpi_touch_events_per_turn') IS NULL THEN
    RAISE EXCEPTION '0213: KPI-4 view is missing';
  END IF;
  RAISE NOTICE '0213 pre: nothing in flight, KPI-4 present';
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
DECLARE v_allowed text[]; v_def text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_def
    FROM pg_constraint c
   WHERE c.conrelid = 'public.ottoq_events'::regclass
     AND pg_get_constraintdef(c.oid) ILIKE '%actor_type%'
   LIMIT 1;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'ottoq_assert_kpi_touch_vocabulary: no actor_type CHECK on ottoq_events; '
                    'the pin has nothing to pin against and must not report success';
  END IF;

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

-- A3. THE VIEW READS THE TABLE ----------------------------------------------
CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn
  WITH (security_invoker = true) AS
WITH touches AS (
  SELECT e.sim_run_id, count(*) AS n
    FROM public.ottoq_events e
   WHERE e.actor_type IN (SELECT t.actor_type FROM public.ottoq_kpi_touch_actor_types t
                           WHERE t.human_actor)
   GROUP BY e.sim_run_id
), overrides AS (
  SELECT d.sim_run_id, count(*) AS n
    FROM public.ottoq_decisions d
   WHERE d.overridden OR d.override_id IS NOT NULL
   GROUP BY d.sim_run_id
), confirms AS (
  SELECT NULL::uuid AS sim_run_id, count(*) AS n
    FROM public.schedule_tasks t
   WHERE t.confirmed_by_user_id IS NOT NULL OR t.tech_override_at IS NOT NULL
), turns AS (
  SELECT b.sim_run_id,
         count(*) FILTER (WHERE b.state IN ('done','released','interrupted')) AS n
    FROM public.ottoq_stall_bookings b
   GROUP BY b.sim_run_id
)
SELECT t.sim_run_id,
       COALESCE(tc.n,0) + COALESCE(o.n,0)
         + CASE WHEN t.sim_run_id IS NULL THEN COALESCE(c.n,0) ELSE 0 END AS touch_events,
       t.n AS turns,
       round((COALESCE(tc.n,0) + COALESCE(o.n,0))::numeric / GREATEST(1, t.n), 3)
         AS touch_events_per_turn
  FROM turns t
  LEFT JOIN touches tc ON tc.sim_run_id IS NOT DISTINCT FROM t.sim_run_id
  LEFT JOIN overrides o ON o.sim_run_id IS NOT DISTINCT FROM t.sim_run_id
  LEFT JOIN confirms c ON true;

COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  'KPI 4 (CLAUDE.md 2.9): human interventions per asset-turn. Touch = signed events '
  'from actor types classified human in ottoq_kpi_touch_actor_types + overridden '
  'decisions (+ production task confirmations for the NULL-run production row). '
  'Turns = KPI-2 completed bookings. 0213: the actor list is a table pinned against '
  'the ottoq_events CHECK, because the hardcoded list it replaced named seven types '
  'the table forbids and omitted every permitted human type but one.';

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

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0213_kpi_four_counted_seven_actor_types_that_cannot_exist', FALSE,
        'G17. KPI-4 counted eight human actor types, seven of which the ottoq_events actor_type '
        'CHECK forbids (charging_tech, cleaning_tech, depot_staff, maintenance_tech, ops_manager, '
        'technician, yard_supervisor), while omitting every permitted human type except '
        'command_center_operator — depot_tech among them. No shipped number moves: the impossible '
        'terms contributed zero and no event of the newly counted types exists yet. The list is now '
        'a table pinned against the live constraint by ottoq_assert_kpi_touch_vocabulary(), which '
        'raises rather than passing when the constraint is absent.',
        now());

COMMIT;
