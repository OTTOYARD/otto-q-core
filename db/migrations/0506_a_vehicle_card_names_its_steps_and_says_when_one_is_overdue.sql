-- migration-version: 20260927004648
-- migration-name:    a_vehicle_card_names_its_steps_and_says_when_one_is_overdue
--
-- 0506  **The vehicle cards showed "Next: Inspect at 8:20 AM" at 9:23 AM, and could not say which inspection
--       (G232, the display half).** `db/checks/0374` §7.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-27 on validation run 5344fc12, live) ═══════════════════════════════════
--
--   0504 fixed the record: an interior inspection now closes its own leg. What the cockpits show is a second thing.
--   `public.ottoq_depot_cards` builds each car's steps from its itinerary legs, and PULSE and OrchestrAV print the
--   first upcoming one as "Next: <leg type> at <planned start>". Two things made that line mislead:
--
--     * both the interior inspection and the readiness check are `inspect` legs, told apart only by
--       `duration_basis->>'atom'`, which the cards did not carry, so every one read "Inspect";
--     * a planned start that has passed stays on the card as if it were still ahead. The flow contract re-times a
--       car's plan only when a leg is 20 minutes late, the car is not charging or in a bay, and no leg is active, so
--       a charging car keeps its later steps at their old times. At sim 9:23 AM PULSE showed 37 "Next" lines, 11 of
--       them already past (9 "Inspect", the oldest 8:20 AM); at 9:32, 5 charging cars had a readiness check next
--       that was up to 67 minutes past.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Every step on a card carries `atom` (the task a leg was planned for, or null), and an upcoming step whose planned
--   start is before the run's clock carries `overdue_min`, the whole minutes since. The cockpits can then say
--   "Readiness check, planned 8:20 AM, 63 min ago" instead of a time that reads as the future. The contract version
--   goes 1.1 -> 1.2 (two optional fields added; nothing removed or renamed). Nothing else in the payload changes. Whether the plan itself should slide with a charge that starts late or runs long is left open
--   (G232): measured on the same run it is 2 of 18 active charges at a time, and a plan change forces a
--   re-certification the label does not.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   A read function for the cockpits: nothing certified reads it.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0506 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure))
     <> 'cd1202042d79d9b13e5230d51882fe56' THEN
    RAISE EXCEPTION '0506 P2: public.ottoq_depot_cards is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0506_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
  v_old1 text := $o1$'seq', l.seq, 'leg_type', l.leg_type,$o1$;
  v_new1 text := $n1$'seq', l.seq, 'leg_type', l.leg_type, 'atom', l.duration_basis->>'atom',$n1$;
  v_old2 text := $o2$'status', 'upcoming',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim)$o2$;
  v_new2 text := $n2$'status', 'upcoming',
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        /* 0506 (G232): a planned start already behind the run's clock is overdue, not ahead */
        'overdue_min', CASE WHEN l.planned_start_sim < (SELECT sim_clock_current FROM run)
                            THEN floor(EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.planned_start_sim)) / 60)::int
                       END)$n2$;
  v_old3 text := $o3$'contract_version', '1.1',$o3$;
  v_new3 text := $n3$'contract_version', '1.2',$n3$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  IF n <> 3 THEN RAISE EXCEPTION '0506: the step builders matched % times, not 3', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN RAISE EXCEPTION '0506: the upcoming step matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old3, ''))) / length(v_old3);
  IF n <> 1 THEN RAISE EXCEPTION '0506: the contract version matched % times, not once', n; END IF;
  EXECUTE replace(replace(replace(v_def, v_old1, v_new1), v_old2, v_new2), v_old3, v_new3);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
BEGIN
  -- V1: three step builders carry the atom; the upcoming one carries overdue_min, once; the contract reads 1.2.
  IF (length(v_def) - length(replace(v_def, '''atom'', l.duration_basis->>''atom''', ''))) / length('''atom'', l.duration_basis->>''atom''') <> 3
     OR (length(v_def) - length(replace(v_def, '''overdue_min''', ''))) / length('''overdue_min''') <> 1
     OR position('''contract_version'', ''1.2''' IN v_def) = 0 THEN
    RAISE EXCEPTION '0506 V1: public.ottoq_depot_cards is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer, volatility and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
          <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0506 V2: public.ottoq_depot_cards''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: the twin depot's cards on the live run, if one is live (the cards read only a running or paused run): every
-- step carries the atom key, every upcoming step whose planned start is behind the clock carries a positive
-- overdue_min, and none ahead of it does. With no live run there is nothing to read and V3 is skipped, loudly.
DO $v3$
DECLARE
  v_msg text; v_cards jsonb; v_steps int; v_with_atom int; v_late int; v_late_marked int; v_ahead_marked int; v_clock timestamptz;
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  v_cards := public.ottoq_depot_cards(v_depot, NULL);
  -- the clock the payload itself was built at: a tick can commit between two statements of this block
  v_clock := (v_cards->>'sim_clock')::timestamptz;
  IF v_cards->>'sim_run_id' IS NULL OR v_clock IS NULL THEN
    RAISE NOTICE '0506 V3 SKIPPED: no live run at the twin depot to read cards from';
    RETURN;
  END IF;
  SELECT count(*), count(*) FILTER (WHERE st ? 'atom'),
         count(*) FILTER (WHERE st->>'status' = 'upcoming' AND (st->>'planned_start')::timestamptz < v_clock),
         count(*) FILTER (WHERE st->>'status' = 'upcoming' AND (st->>'planned_start')::timestamptz < v_clock
                            AND (st->>'overdue_min')::int >= 0),
         count(*) FILTER (WHERE st->>'status' = 'upcoming' AND (st->>'planned_start')::timestamptz >= v_clock
                            AND st->>'overdue_min' IS NOT NULL)
    INTO v_steps, v_with_atom, v_late, v_late_marked, v_ahead_marked
    FROM jsonb_array_elements(v_cards->'vehicles') veh, jsonb_array_elements(COALESCE(veh->'card'->'steps', '[]'::jsonb)) st;
  IF v_steps = 0 OR v_with_atom <> v_steps OR v_late_marked <> v_late OR v_ahead_marked <> 0 THEN
    RAISE EXCEPTION '0506 V3 FAILED: % steps, % with atom, % overdue of which % marked, % ahead wrongly marked',
      v_steps, v_with_atom, v_late, v_late_marked, v_ahead_marked;
  END IF;
  RAISE NOTICE '0506 V3 PASSED: % steps all carry atom; % overdue, all marked', v_steps, v_late;
END $v3$;

-- Rollback: restore public.ottoq_depot_cards from ottoq_schema_snapshots label '0506_pre' (CREATE OR REPLACE, ACL
-- kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0506_a_vehicle_card_names_its_steps_and_says_when_one_is_overdue', false,
  'ottoq_depot_cards: each step carries the atom its leg was planned for, and an upcoming step whose planned start is '
  'behind the run clock carries overdue_min. A cockpit read function; nothing certified reads it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
