-- migration-version: 20261024044503
-- migration-name:    the_agents_board_reads_the_arrival_forecast_without_writing_it
--
-- 0766  **The agent's board reads the arrival forecast without writing it, so the agent's read takes no lock on the
--       run's row and the tick stops waiting for it.** (G485)
--
-- ══ §1 WHY (measured 2026-10-24 between 03:33 and 04:00 UTC, 10:33-11:00 PM CT on 10-23, on run 78c0624c, busy_day,
--       the twin depot, read-only) ══════════════════════════════════════════════════════════════════════════════════════
--
--   The world step's first statement takes the run's row FOR UPDATE (public.ottoq_sim_advance_tick_world; G490: that
--   lock is load-bearing and is not touched here). public.ottoq_agent_board, the agent's read, which the agent's edge
--   function calls through PostgREST on every third decide beat, builds its 'forecast_charge_kw_60m' by calling
--   public.ottoq_predict_arrivals, and that function records an 'ottoq.arrival_forecast' event whenever a car is due home:
--   an INSERT into ottoq_events carrying the run's id, whose key check (fk_ottoq_events_sim_run) takes the run's row FOR
--   KEY SHARE, which conflicts with FOR UPDATE, until the board's transaction ends. The board then spends most of its
--   time on the charge line (public.ottoq_agent_charge_queue_board: 6,567 ms of the board's about 6.8 s, timed on live
--   at 03:41 UTC), and a world step that starts meanwhile waits for it.
--   Sampled on live every 50 ms, with pg_stat_clear_snapshot() before each sample (pg_stat_activity is otherwise read
--   once per transaction, and the first sampler, which did not clear it, showed every holder's query as 'COMMIT'):
--   from 03:38:27.46 to 03:38:32.05 UTC the metronome waited on a transactionid, holding a tuple lock on ottoq_sim_runs,
--   blocked by PostgREST running ottoq_agent_board, whose transaction was 1.4 s old when the wait began and 6.0 s old
--   when it ended; the same at 03:36:49.38-54.04. The board's transaction held RowExclusiveLock on ottoq_events and its
--   sequence from 0.1 s into it, and nothing else of a writer's: a census of every function the board reaches, five
--   calls deep, comment-stripped, finds one writer, ottoq_predict_arrivals -> ottoq_record_event.
--   The cost: of the run's 231 world steps to 03:40 UTC, the 32 that began within 9 s of an agent pass's start took a
--   mean 5,693 ms (p50 5,989) against 1,504 ms (p50 1,281) for the other 199, and 29 of the 34 steps over 4 s were among
--   them: about 134 s of world steps in 21 real minutes waited behind the agent's read. In live playback the clock
--   catches up (each tick advances by the real time since the last), so the world loses no time, but every sixth beat
--   is a 5-7 s freeze and a sim step three times longer. CLAUDE.md's "the agent is fired asynchronously every third
--   tick and never blocks it" (0332) holds for the call and fails for the read.
--   The board's event is one of about 317 'ottoq.arrival_forecast' events the run wrote by 03:45 UTC: the engine's own
--   callers (the energy plan, the MPC replan, the opportunistic charge plan) write the rest inside the tick, and the twin
--   app's events window, the one reader of these events, keeps reading those.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_arrival_forecast(p_depot_id, p_sim_clock, p_sim_run_id, p_horizon_min), new: STABLE, SQL, no write.
--       The four numbers ottoq_predict_arrivals returns, by its formula, rounded as it returns them. EXECUTE for the
--       engine (its owner) and service_role only.
--   (b) public.ottoq_predict_arrivals computes the four through (a) and records its event exactly as before: one formula,
--       the same outputs, the same payload (V3, V4).
--   (c) public.ottoq_agent_board reads (a) in place of ottoq_predict_arrivals: one substitution on the live definition,
--       every other byte the board's (V2). The board's value is the same (V4). The board then writes nothing (V5).
--   No dial: nothing decides differently. The agent's read stops writing, and with it stops holding the run's row.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the board and ottoq_predict_arrivals are the definitions read on live (pg_get_functiondef
--   md5 d130f89a and b9e95253) and 0709 is classified. P2 once. Pre-images to ottoq_schema_snapshots as '0766_pre'. Each
--   anchor matches once, read with bare newlines whatever line endings the paste carried. V1 the board reads (a) once and
--   calls ottoq_predict_arrivals nowhere (comment-stripped). V2 the board less its change is its pre-image. V3 the
--   forecast less its change is its pre-image. V4 on every running run and the latest five runs, at each run's clock and
--   at 30 and 60 minutes, (a) equals the old formula (written out here). V5 no function the board reaches, five calls
--   deep, writes or records an event. V6 (a) is executable by no browser role; the two patched functions keep their
--   ACLs, security, volatility and settings. V7 the patched bodies are byte for byte the ones the tests ran (md5).
--   tests/test_board_reads_without_writing_sql.py runs this file on the scratch PostgreSQL over the live board and the
--   live forecast (md5 asserted): before it, a board read held open with a car due home makes a world step's FOR UPDATE
--   on the run's row wait out its lock timeout; after it, the same read takes the row at once and writes no event; the
--   board's value is byte for byte as before; ottoq_predict_arrivals returns and records exactly what it did; (a) equals
--   ottoq_predict_arrivals on a fleet that spans every SoC band; and it refuses a second apply and a body it did not read.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: ottoq_predict_arrivals returns and records exactly what it did (V3, V4), and the board's one
--   reader is the agent's edge function, quiesced in certification arms; no atom hashes the board. forces_dial_restart
--   FALSE: no dial is added or read.
--
-- ══ §5 ON AT THE TWIN DEPOT (CLAUDE.md rule 12) ═════════════════════════════════════════════════════════════════════════
--
--   On at the apply, at every depot: nothing is gated. The demo-run check: the world steps that begin within 9 s of an
--   agent pass take what the others take (db/checks/0461 (3) is the query).
--
-- ROLLBACK: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0766_pre'; then DROP FUNCTION
--   public.ottoq_arrival_forecast(uuid, timestamp with time zone, uuid, integer); DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0766_the_agents_board_reads_the_arrival_forecast_without_writing_it'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0766 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the definitions this file was written against, and 0709 ──
DO $p1$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure))
       IS DISTINCT FROM 'd130f89abfff0e93aac5416b3f4d98aa'
     OR md5(pg_get_functiondef('public.ottoq_predict_arrivals(uuid,timestamp with time zone,uuid,integer)'::regprocedure))
       IS DISTINCT FROM 'b9e952538e34007310156ccf7f6979f4' THEN
    RAISE EXCEPTION '0766 P1: a function this file patches is not the definition it was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0709_the_agents_return_wave_counts_this_runs_cars_not_every_run_ever') THEN
    RAISE EXCEPTION '0766 P1: 0709 is not classified; apply in order';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0766_the_agents_board_reads_the_arrival_forecast_without_writing_it')
     OR to_regprocedure('public.ottoq_arrival_forecast(uuid,timestamp with time zone,uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION '0766 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images, and the attributes V6 holds the patched functions to ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0766_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_board(uuid)'::regprocedure,
                 'public.ottoq_predict_arrivals(uuid,timestamp with time zone,uuid,integer)'::regprocedure);

CREATE TEMP TABLE _0766_attrs ON COMMIT DROP AS
SELECT p.oid::regprocedure::text AS fn, p.proacl::text AS acl, p.prosecdef, p.provolatile, p.proconfig::text AS config,
       p.proowner
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_agent_board(uuid)'::regprocedure,
                 'public.ottoq_predict_arrivals(uuid,timestamp with time zone,uuid,integer)'::regprocedure);

-- ── (a) the forecast, read. Created from a string with every carriage return removed, so a paste with Windows line
-- endings stores the same body the tests ran (V7). ──
DO $create$
BEGIN
  EXECUTE replace($def$CREATE FUNCTION public.ottoq_arrival_forecast(p_depot_id uuid, p_sim_clock timestamp with time zone,
                                              p_sim_run_id uuid DEFAULT NULL::uuid, p_horizon_min integer DEFAULT 30)
 RETURNS TABLE(incoming_count integer, charge_needed_count integer, predicted_charge_kw numeric,
               predicted_charge_kwh numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0766 (G485): the cars due home within the horizon and the charge they will want, by the formula
  -- public.ottoq_predict_arrivals has always used (it computes through this one), rounded as it returns them, with
  -- nothing written. A reader that must not hold the run's row, the agent's board, reads this. p_depot_id is not read,
  -- as it never was: a run's dispatches are its depot's.
  SELECT COUNT(*)::int,
         (COUNT(*) FILTER (WHERE v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1))::int,
         ROUND(COALESCE(SUM(CASE WHEN v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1
                                 THEN LEAST(COALESCE(v.inlet_max_kw,150), 250)
                                      * CASE WHEN v.current_soc < 35 THEN 0.90 WHEN v.current_soc < 55 THEN 0.80
                                             WHEN v.current_soc < 75 THEN 0.50 ELSE 0.25 END
                                 ELSE 0 END), 0), 0),
         ROUND(COALESCE(SUM(GREATEST(0, (COALESCE(v.target_soc, public.ottoq_default_target_soc()) - v.current_soc)/100.0
                                        * COALESCE(v.battery_capacity_kwh,75))), 0), 0)
    FROM ottoq_vehicle_dispatches d
    JOIN vehicles v ON v.id = d.vehicle_id
   WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning')
     AND d.scheduled_return_at IS NOT NULL
     AND d.scheduled_return_at <= p_sim_clock + (p_horizon_min || ' minutes')::interval
     AND d.scheduled_return_at >  p_sim_clock - INTERVAL '5 minutes';
$function$$def$, E'\r', '');
END $create$;

REVOKE ALL ON FUNCTION public.ottoq_arrival_forecast(uuid, timestamp with time zone, uuid, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_arrival_forecast(uuid, timestamp with time zone, uuid, integer) TO service_role;

COMMENT ON FUNCTION public.ottoq_arrival_forecast(uuid, timestamp with time zone, uuid, integer) IS
  '0766 (G485): the arrival forecast public.ottoq_predict_arrivals returns, by its formula, with nothing written. The '
  'agent''s board reads this, so its read holds no lock on the run''s row (an event insert''s key check would).';

-- ── (b) and (c): the substitutions ──
CREATE TEMP TABLE _0766_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0766_patch VALUES
('public.ottoq_predict_arrivals(uuid,timestamp with time zone,uuid,integer)', 1,
$p1o$  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1),
    COALESCE(SUM(CASE WHEN v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1
              THEN LEAST(COALESCE(v.inlet_max_kw,150), 250)
                   * CASE WHEN v.current_soc < 35 THEN 0.90 WHEN v.current_soc < 55 THEN 0.80
                          WHEN v.current_soc < 75 THEN 0.50 ELSE 0.25 END
              ELSE 0 END), 0),
    COALESCE(SUM(GREATEST(0, (COALESCE(v.target_soc, public.ottoq_default_target_soc()) - v.current_soc)/100.0 * COALESCE(v.battery_capacity_kwh,75))), 0)
  INTO v_in_count, v_chg_count, v_kw, v_kwh
  FROM ottoq_vehicle_dispatches d
  JOIN vehicles v ON v.id = d.vehicle_id
  WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning')
    AND d.scheduled_return_at IS NOT NULL
    AND d.scheduled_return_at <= p_sim_clock + (p_horizon_min || ' minutes')::interval
    AND d.scheduled_return_at >  p_sim_clock - INTERVAL '5 minutes';
$p1o$,
$p1n$  -- 0766 (G485): the four numbers by the one formula, public.ottoq_arrival_forecast, which writes nothing; this
  -- function returns them and records its event as before
  SELECT f.incoming_count, f.charge_needed_count, f.predicted_charge_kw, f.predicted_charge_kwh
    INTO v_in_count, v_chg_count, v_kw, v_kwh
    FROM public.ottoq_arrival_forecast(p_depot_id, p_sim_clock, p_sim_run_id, p_horizon_min) f;
$p1n$),
('public.ottoq_agent_board(uuid)', 1,
$p2o$          FROM ottoq_predict_arrivals(v_depot, v_clock, p_sim_run_id, 60))),
$p2o$,
$p2n$          FROM public.ottoq_arrival_forecast(v_depot, v_clock, p_sim_run_id, 60))),  --: 0766 (G485): read, not recorded
$p2n$);

-- A paste can arrive with Windows line endings (the SQL editor did so with 0765 on 2026-10-23); the stored definitions end
-- their lines in a bare newline, so the anchors and their replacements are read with bare newlines.
UPDATE _0766_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0766_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0766_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0766: anchor % of % matches % times, not 1', p.seq, f, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0766: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: the board reads the forecast once and calls ottoq_predict_arrivals nowhere ──
DO $v1$
DECLARE v_src text := regexp_replace(regexp_replace(
          (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_agent_board(uuid)'::regprocedure),
          '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g');
BEGIN
  IF (SELECT count(*) FROM regexp_matches(v_src, '\mottoq_arrival_forecast\s*\(', 'g')) <> 1
     OR v_src ~ '\mottoq_predict_arrivals\s*\(' THEN
    RAISE EXCEPTION '0766 V1 FAILED: the board does not read the forecast once, or still calls ottoq_predict_arrivals';
  END IF;
END $v1$;

-- ── V2, V3: each definition less its change is its pre-image ──
DO $v23$
DECLARE r record; p record; v_def text; v_old text;
BEGIN
  FOR r IN SELECT DISTINCT fn FROM _0766_patch LOOP
    v_def := pg_get_functiondef(r.fn::regprocedure);
    FOR p IN SELECT * FROM _0766_patch WHERE fn = r.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    SELECT s.definition INTO v_old FROM public.ottoq_schema_snapshots s
     WHERE s.label = '0766_pre' AND s.def_md5 = md5(v_def)
       AND s.object_name = split_part(split_part(r.fn, '(', 1), '.', 2) LIMIT 1;
    IF v_old IS NULL THEN
      RAISE EXCEPTION '0766 V2/V3 FAILED: % less its change is not its pre-image (md5 %)', r.fn, md5(v_def);
    END IF;
  END LOOP;
END $v23$;

-- ── V4: the read forecast equals the old formula, on every running run and the latest five, at 30 and 60 minutes ──
DO $v4$
DECLARE r record; h int; a record; b record; v_n int := 0;
BEGIN
  FOR r IN SELECT sim_run_id, depot_id, sim_clock_current FROM (
             SELECT sim_run_id, depot_id, sim_clock_current, status, started_at FROM public.ottoq_sim_runs
              WHERE status = 'running'
             UNION
             (SELECT sim_run_id, depot_id, sim_clock_current, status, started_at FROM public.ottoq_sim_runs
               ORDER BY started_at DESC NULLS LAST LIMIT 5)) x
            WHERE sim_clock_current IS NOT NULL LOOP
    FOREACH h IN ARRAY ARRAY[30, 60] LOOP
      SELECT * INTO a FROM public.ottoq_arrival_forecast(r.depot_id, r.sim_clock_current, r.sim_run_id, h);
      SELECT COUNT(*)::int AS incoming_count,
             (COUNT(*) FILTER (WHERE v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1))::int
               AS charge_needed_count,
             ROUND(COALESCE(SUM(CASE WHEN v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1
                       THEN LEAST(COALESCE(v.inlet_max_kw,150), 250)
                            * CASE WHEN v.current_soc < 35 THEN 0.90 WHEN v.current_soc < 55 THEN 0.80
                                   WHEN v.current_soc < 75 THEN 0.50 ELSE 0.25 END
                       ELSE 0 END), 0), 0) AS predicted_charge_kw,
             ROUND(COALESCE(SUM(GREATEST(0, (COALESCE(v.target_soc, public.ottoq_default_target_soc()) - v.current_soc)/100.0
                                            * COALESCE(v.battery_capacity_kwh,75))), 0), 0) AS predicted_charge_kwh
        INTO b
        FROM public.ottoq_vehicle_dispatches d JOIN public.vehicles v ON v.id = d.vehicle_id
       WHERE d.sim_run_id = r.sim_run_id AND d.status IN ('active','returning')
         AND d.scheduled_return_at IS NOT NULL
         AND d.scheduled_return_at <= r.sim_clock_current + (h || ' minutes')::interval
         AND d.scheduled_return_at >  r.sim_clock_current - INTERVAL '5 minutes';
      IF (a.incoming_count, a.charge_needed_count, a.predicted_charge_kw::text, a.predicted_charge_kwh::text)
         IS DISTINCT FROM (b.incoming_count, b.charge_needed_count, b.predicted_charge_kw::text,
                           b.predicted_charge_kwh::text) THEN
        RAISE EXCEPTION '0766 V4 FAILED: run %, % minutes: read % against the formula %', r.sim_run_id, h,
          row(a.incoming_count, a.charge_needed_count, a.predicted_charge_kw, a.predicted_charge_kwh),
          row(b.incoming_count, b.charge_needed_count, b.predicted_charge_kw, b.predicted_charge_kwh);
      END IF;
      v_n := v_n + 1;
    END LOOP;
  END LOOP;
  RAISE NOTICE '0766 V4 PASSED (% run-horizon pairs)', v_n;
END $v4$;

-- ── V5: nothing the board reaches, five calls deep, writes or records an event ──
DO $v5$
DECLARE v_bad text;
BEGIN
  WITH RECURSIVE fns AS (
    SELECT (p.proname::text) COLLATE "default" AS proname,
           regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'twin', 'ottoq')
       AND p.prolang IN (SELECT oid FROM pg_language WHERE lanname IN ('plpgsql', 'sql'))
  ), names AS (SELECT DISTINCT proname FROM fns),
  g(proname, depth, path) AS (
    SELECT 'ottoq_agent_board'::text COLLATE "default", 0, 'ottoq_agent_board'::text COLLATE "default"
    UNION
    SELECT nm.proname, g.depth + 1, g.path || ' > ' || nm.proname
      FROM g JOIN fns f ON f.proname = g.proname
      JOIN names nm ON nm.proname <> g.proname AND f.src ~ ('(^|[^a-z0-9_])' || nm.proname || '\s*\(')
     WHERE g.depth < 5 AND position((' ' || nm.proname || ' ') IN (' ' || g.path || ' ')) = 0
  )
  SELECT string_agg(DISTINCT g.path, '; ') INTO v_bad
    FROM g JOIN fns f ON f.proname = g.proname
   WHERE f.src ~* '(INSERT\s+INTO|UPDATE\s+[a-z_\.]+\s+SET|DELETE\s+FROM)' OR f.src ~ 'ottoq_record_event\s*\(';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0766 V5 FAILED: the board still reaches a writer: %', v_bad;
  END IF;
END $v5$;

-- ── V6: who may run what ──
DO $v6$
DECLARE v_acl text := (SELECT proacl::text FROM pg_proc
                        WHERE oid = 'public.ottoq_arrival_forecast(uuid,timestamp with time zone,uuid,integer)'::regprocedure);
BEGIN
  IF v_acl IS NULL OR v_acl ~ '(^|[{,])=X' OR v_acl ~ '(^|[{,])(anon|authenticated)=' OR v_acl !~ 'service_role=X' THEN
    RAISE EXCEPTION '0766 V6 FAILED: ottoq_arrival_forecast''s ACL is %', v_acl;
  END IF;
  IF EXISTS (SELECT 1 FROM _0766_attrs a JOIN pg_proc p ON p.oid = a.fn::regprocedure
              WHERE (p.proacl::text, p.prosecdef, p.provolatile, p.proconfig::text, p.proowner)
                    IS DISTINCT FROM (a.acl, a.prosecdef, a.provolatile, a.config, a.proowner)) THEN
    RAISE EXCEPTION '0766 V6 FAILED: a patched function''s ACL, security, volatility, settings or owner moved';
  END IF;
END $v6$;

-- ── V7: the patched bodies are byte for byte the ones the scratch PostgreSQL ran ──
DO $v7$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_board(uuid)'::regprocedure)
       IS DISTINCT FROM 'cc155a31209fd8e89260028d24a9715f'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = 'public.ottoq_predict_arrivals(uuid,timestamp with time zone,uuid,integer)'::regprocedure)
       IS DISTINCT FROM '535c1600093266e53b2e743ad3667073'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = 'public.ottoq_arrival_forecast(uuid,timestamp with time zone,uuid,integer)'::regprocedure)
       IS DISTINCT FROM '70317860cba9f347bac7571a53ba11ac' THEN
    RAISE EXCEPTION '0766 V7 FAILED: a body is not the one the tests ran';
  END IF;
END $v7$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0766_the_agents_board_reads_the_arrival_forecast_without_writing_it', false, false,
        'G485. public.ottoq_arrival_forecast (new, STABLE, no write) carries ottoq_predict_arrivals'' formula; '
        'ottoq_predict_arrivals computes through it and records its event as before (outputs and payload unchanged); '
        'ottoq_agent_board reads it in place of ottoq_predict_arrivals, so the agent''s read writes no event and holds no '
        'key lock on the run''s row (on 78c0624c the world steps that began within 9 s of an agent pass took a mean '
        '5,693 ms against 1,504). The board''s value is unchanged and its one reader is the agent edge function, '
        'quiesced in certification arms; no dial.',
        now());

COMMIT;
