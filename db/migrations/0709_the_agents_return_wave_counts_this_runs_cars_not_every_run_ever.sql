-- migration-version: PENDING
-- migration-name:    the_agents_return_wave_counts_this_runs_cars_not_every_run_ever
--
-- 0709  **The agent's return wave counts this run's cars, not every run's.** ottoq_agent_board's `inbound_60m` joined
--        every open dispatch ever written for a car now driving home, with no run filter, so the agent's LENS 2 (the
--        return wave) read 315-501 cars "arriving within the hour" at a 116-car depot where 8 were on the road.
--        (Found 2026-10-13 by the first evidence row 0703 ever kept: pass 5 of run 176b2912 quoted "Inbound 60m is 501
--        vehicles"; db/checks/0440 §3.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The board (pg_get_functiondef, md5 0cc9d7ae after 0704) builds inbound_60m as
--
--     SELECT count(*) FROM vehicles v JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
--      WHERE v.home_depot_id = v_depot AND v.current_state = 'en_route_to_depot'
--        AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval '60 minutes'
--
--   A dispatch is closed by its own run. When a run stops with cars out, their dispatches stay open forever, and the
--   next run's board counts them again for the same car. Measured 2026-10-13 15:19 UTC on run 176b2912 (busy_day, twin
--   depot, read-only): the formula gave 315; the same formula with `d.sim_run_id = p_sim_run_id` gave 8, which equals
--   the 8 cars en_route_to_depot; open dispatches from 119 distinct runs contributed. At the agent's first pass the
--   board said 501. Every dispatch carries a sim_run_id (0 rows with NULL; production sessions included, 343 rows), so
--   the run predicate loses nothing in production.
--
--   It is the unscoped-count class of 0145 / 0146 / 0250 (CLAUDE.md rule 8): a count without the predicate that defines
--   its population is a number about a different question. The agent was told the depot faced a return wave about 40
--   times its real size. It is the first defect the new evidence record found, on the first pass it recorded, because
--   the record keeps the board the model read.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   One predicate in ottoq_agent_board's inbound_60m: `AND d.sim_run_id = p_sim_run_id`, by SUBSTITUTION on the live
--   definition (the anchor is asserted to occur exactly once; every other byte is the live board's). Nothing else: the
--   board's other depot-scoped counts were measured on the same run and are already right (open visits 30 = 30 run-
--   scoped, carryovers 0 = 0, pending approvals 1 = 1).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   The board is read by one caller, the agent's edge function (a comment-stripped census finds no database function
--   calling it), which is quiesced in certification arms. No atom hashes the board.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the ottoq_agent_board definition snapshotted under label '0709_pre' in ottoq_schema_snapshots.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0709 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE v_md5 text := md5(pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0704_every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find') THEN
    RAISE EXCEPTION '0709 P1: 0704 is not classified; apply in order';
  END IF;
  IF v_md5 IS DISTINCT FROM '0cc9d7aee7cc0f44fb72cb298647aba9' THEN
    RAISE EXCEPTION '0709 P1: ottoq_agent_board is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches WHERE sim_run_id IS NULL) THEN
    RAISE EXCEPTION '0709 P1: a dispatch without a run exists; the run predicate would drop it';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0709_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board';

DO $board$
DECLARE
  v_def    text := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
  v_anchor constant text := E'AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval ''60 minutes''),';
  v_new    constant text := E'AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval ''60 minutes''\n'
                         || E'          AND d.sim_run_id = p_sim_run_id),  --: 0709: this run''s cars, not every run''s';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0709: the inbound_60m anchor occurs % times in ottoq_agent_board, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, v_anchor, v_new);
END $board$;

DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
        v_old text := (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0709_pre' AND s.object_name = 'ottoq_agent_board' LIMIT 1);
BEGIN
  IF strpos(v_def, 'AND d.sim_run_id = p_sim_run_id),  --: 0709') = 0 THEN
    RAISE EXCEPTION '0709 V1 FAILED: the board does not carry the run predicate';
  END IF;
  --: V2 nothing else moved: removing the inserted text gives the old definition back
  IF replace(v_def, E'\n          AND d.sim_run_id = p_sim_run_id),  --: 0709: this run''s cars, not every run''s',
             '),') <> v_old THEN
    RAISE EXCEPTION '0709 V2 FAILED: the board changed by more than the predicate';
  END IF;
  RAISE NOTICE '0709 V1-V2 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0709_the_agents_return_wave_counts_this_runs_cars_not_every_run_ever', false, false,
  'Found 2026-10-13 by 0703''s first evidence row (db/checks/0440): ottoq_agent_board''s inbound_60m counted open '
  'dispatches from every run (315-501 against 8 cars on the road); adds d.sim_run_id = p_sim_run_id. The board''s one '
  'reader is the agent edge function, quiesced in certification arms; no atom hashes it: FALSE/FALSE.',
  now());

COMMIT;
