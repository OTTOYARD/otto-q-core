-- migration-version: 20260927122408
-- migration-name:    a_dial_experiment_restarts_only_for_a_change_that_can_move_an_arm
--
-- 0523  **G250: a dial experiment counted only the pairs run on the current engine, and the engine was the md5 of every
--       migration version, so every migration restarted every experiment -- 0522, a cron schedule, took G240 from
--       three counted pairs to none. Pairs now count from a dial floor that moves only for a migration that can move
--       an arm, classified the way the recert floor is: unclassified restarts, FALSE is the author's statement.**
--       `db/checks/0393`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_engine_hash()` is `md5(string_agg(version ORDER BY version))` over `supabase_migrations.schema_migrations`.
--   The verdict counted a pair only when its recorded `engine_hash` equalled it, the runner chose experiments and seeds
--   by it, and `ottoq_dial_pair` refused a seed already paired on it. At 12:18 UTC G240 (143a11c7) read "0 of 6 counted
--   pairs needed for the first look", 3 recorded and 3 stale: its pairs ran at 09:40, 10:10 and 10:40 UTC, after 0521
--   (the last change that could move an arm) and before 0522 (the dial window's close moved from 11:00 to 10:41). The
--   energy experiment (82c5568b) had 4 pairs since 0521 and counted none. At this repo's pace -- nine migrations on
--   2026-09-27 before 7 AM CT -- an experiment that needs six pairs on one engine concludes only on a night when
--   nothing at all is applied, however little the applied things touch.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_cert_lineage.forces_dial_restart`, nullable. NULL restarts dial experiments -- the safe default, as an
--       unclassified migration forces recert. FALSE is the author's statement that no dial arm can come out
--       differently. `forces_recert` alone cannot say it: canon columns run at the dials' defaults, so a change on a
--       non-default path is correctly `forces_recert = false` and still moves a treatment arm. 0517 is that case on
--       record (the calibrated booking window behind `charge_window_calibration_id`, G240's own treatment).
--   (2) `public.ottoq_dial_pair_floor()`: the later of the recert floor -- a change that can move a canon column can
--       move an arm -- and the last migration that restarts dial pairs, read as the recert floor is read.
--   (3) `ottoq_dial_experiment_verdict`, `ottoq_dial_experiment_runner` and `ottoq_dial_pair` count, choose and refuse by
--       "ran since the dial floor" instead of "ran on this engine". The ledger keeps each pair's engine hash as
--       recorded, and the verdict reports the floor beside it. `pairs.stale_engine` keeps its name and now counts
--       pairs run before the floor.
--   (4) `ottoq_dial_counted_pairs(uuid, timestamptz)` replaces `(uuid, text)` (the verdict was its only caller) and
--       takes each seed once, its first valid pair since the floor: G153's rule -- under determinism a re-run is
--       repetition, not replication -- made structural in the count instead of resting on the refusal alone.
--   (5) 0522 is classified `forces_dial_restart = false`: a cron schedule. So is this file: it changes which pairs
--       count, not what any arm does.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   The dial-experiment bookkeeping only; no certified path reads any of it.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0523 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_dial_pair_floor()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                   AND table_name = 'ottoq_cert_lineage' AND column_name = 'forces_dial_restart') THEN
    RAISE EXCEPTION '0523 P2: already applied';
  END IF;
  -- the verdict is the only caller of the counted-pairs function this file replaces
  IF (SELECT array_agg(p.oid::regprocedure::text) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'ottoq_dial_counted_pairs\s*\('
         AND p.proname <> 'ottoq_dial_counted_pairs')
     IS DISTINCT FROM ARRAY['ottoq_dial_experiment_verdict(uuid)'] THEN
    RAISE EXCEPTION '0523 P2: something other than the verdict calls ottoq_dial_counted_pairs';
  END IF;
  IF to_regprocedure('public.ottoq_dial_counted_pairs(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '0523 P2: ottoq_dial_counted_pairs(uuid,text) is not the function this file replaces';
  END IF;
  -- 0522 is what this file classifies, and it is a cron schedule that forces no recert
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0522_the_dial_window_closes_before_its_last_pair_could_outlast_it' AND NOT forces_recert) THEN
    RAISE EXCEPTION '0523 P2: 0522''s lineage row is not the one this file classifies';
  END IF;
  -- a pair's ran_at is its transaction's start, so no pair can straddle a migration (P0 refuses one in flight)
  IF (SELECT column_default FROM information_schema.columns WHERE table_schema = 'public'
        AND table_name = 'ottoq_dial_pair_ledger' AND column_name = 'ran_at') IS DISTINCT FROM 'now()' THEN
    RAISE EXCEPTION '0523 P2: the pair ledger''s ran_at is not stamped the way this file assumes';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0523_pre', 'function', 'public', s.object_name, pg_get_functiondef(s.oid), md5(pg_get_functiondef(s.oid))
  FROM (VALUES ('ottoq_dial_experiment_verdict', 'public.ottoq_dial_experiment_verdict(uuid)'::regprocedure::oid),
               ('ottoq_dial_experiment_runner',  'public.ottoq_dial_experiment_runner()'::regprocedure::oid),
               ('ottoq_dial_pair',               'public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure::oid),
               ('ottoq_dial_counted_pairs',      'public.ottoq_dial_counted_pairs(uuid,text)'::regprocedure::oid))
       AS s(object_name, oid);

-- ── (1) the classification ──
ALTER TABLE public.ottoq_cert_lineage ADD COLUMN forces_dial_restart boolean;
COMMENT ON COLUMN public.ottoq_cert_lineage.forces_dial_restart IS
  '0523 (G250): whether this migration can change what a dial pair''s arm does. NULL restarts every dial experiment (the '
  'safe default, as an unclassified migration forces recert); FALSE is the author''s statement that no arm can come out '
  'differently. forces_recert alone cannot say it: canon columns run at dial defaults, and a change on a non-default '
  'path (0517) is correctly forces_recert=false and still moves a treatment arm. Read by ottoq_dial_pair_floor().';

UPDATE public.ottoq_cert_lineage SET forces_dial_restart = false
 WHERE name = '0522_the_dial_window_closes_before_its_last_pair_could_outlast_it';

-- ── (2) the floor ──
CREATE FUNCTION public.ottoq_dial_pair_floor()
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
  /* 0523 (G250): a dial pair counts, and a seed counts as paired, only if it ran at or after this. The later of the
     recert floor (a change that can move a canon column can move an arm) and the last migration that restarts dial
     pairs -- COALESCE(forces_dial_restart, true), so an unclassified one does -- read as ottoq_cert_recert_floor() reads
     its own: schema_migrations joined on the name with any NNNN_ prefix stripped from both sides (0226), and the lineage
     rows' own times for anything applied outside it (0199). */
  SELECT GREATEST(
    public.ottoq_cert_recert_floor(),
    (SELECT max(make_timestamptz(
              substr(m.version,1,4)::int,  substr(m.version,5,2)::int,
              substr(m.version,7,2)::int,  substr(m.version,9,2)::int,
              substr(m.version,11,2)::int, substr(m.version,13,2)::numeric, 'UTC'))
       FROM supabase_migrations.schema_migrations m
       LEFT JOIN public.ottoq_cert_lineage l
              ON regexp_replace(l.name, '^[0-9]{4}[a-z]?_', '')
               = regexp_replace(m.name, '^[0-9]{4}[a-z]?_', '')
      WHERE COALESCE(l.forces_dial_restart, true)
        AND m.version ~ '^[0-9]{14}$'),
    (SELECT max(l.classified_at) FROM public.ottoq_cert_lineage l
      WHERE COALESCE(l.forces_dial_restart, true)));
$fn$;

-- ── (4) the counted pairs: since the floor, each seed once ──
CREATE FUNCTION public.ottoq_dial_counted_pairs(p_experiment_id uuid, p_floor timestamptz)
RETURNS TABLE(k bigint, pair_id bigint, seed bigint, differs boolean, a jsonb, b jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
  /* 0439: the pairs the decision rule counts, in the order they ran: a valid instrument (complete, same world, both
     arms paid the shield) and the primary metric present on both arms. 0523 (G250): run since the dial floor -- was
     "on this engine", which every migration moved -- and each seed once, its first such pair, because under
     determinism a second pair of one seed is repetition, not replication (G153). */
  SELECT row_number() OVER (ORDER BY z.pair_id), z.pair_id, z.seed, z.differs, z.metrics_a, z.metrics_b
    FROM (SELECT DISTINCT ON (l.seed) l.pair_id, l.seed, l.differs, l.metrics_a, l.metrics_b
            FROM public.ottoq_dial_pair_ledger l
            JOIN public.ottoq_dial_experiments x ON x.experiment_id = l.experiment_id
           WHERE l.experiment_id = p_experiment_id AND l.ran_at >= p_floor
             AND l.complete AND l.world_identical AND l.both_paid_shield
             AND jsonb_typeof(l.metrics_a -> x.primary_metric) = 'number'
             AND jsonb_typeof(l.metrics_b -> x.primary_metric) = 'number'
           ORDER BY l.seed, l.pair_id) z
$fn$;

-- ── (3) the verdict, the runner and the pair count, choose and refuse by the floor ──
DO $patch$
DECLARE
  v_def text; v_fn text; v_old text; v_new text; v_want int; n int; i int;
  -- (function, old, new, how many times old must occur)
  v_edits text[][] := ARRAY[
    ARRAY['public.ottoq_dial_experiment_verdict(uuid)',
          $o$  v_engine text; v_sign numeric; v_weights jsonb; v_alpha_look numeric;$o$,
          $n$  v_engine text; v_sign numeric; v_weights jsonb; v_alpha_look numeric;
  v_floor timestamptz;   -- 0523 (G250)$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_verdict(uuid)',
          $o$  v_engine := public.ottoq_engine_hash();$o$,
          $n$  v_engine := public.ottoq_engine_hash();
  v_floor  := public.ottoq_dial_pair_floor();   -- 0523 (G250): a pair counts if it ran since the dial floor$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_verdict(uuid)',
          $o$         count(*) FILTER (WHERE l.engine_hash <> v_engine),
         count(*) FILTER (WHERE l.engine_hash = v_engine AND NOT (l.complete AND l.world_identical AND l.both_paid_shield))$o$,
          $n$         count(*) FILTER (WHERE l.ran_at < v_floor),   -- 0523 (G250): stale = ran before the dial floor
         count(*) FILTER (WHERE l.ran_at >= v_floor AND NOT (l.complete AND l.world_identical AND l.both_paid_shield))$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_verdict(uuid)',
          $o$public.ottoq_dial_counted_pairs(p_experiment_id, v_engine)$o$,
          $n$public.ottoq_dial_counted_pairs(p_experiment_id, v_floor)$n$, '4'],
    ARRAY['public.ottoq_dial_experiment_verdict(uuid)',
          $o$    'engine_hash', v_engine,$o$,
          $n$    'engine_hash', v_engine, 'pair_floor', v_floor,$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_runner()',
          $o$  v_res jsonb; v_verdict jsonb; v_prom jsonb;$o$,
          $n$  v_res jsonb; v_verdict jsonb; v_prom jsonb;
  v_floor timestamptz;   -- 0523 (G250)$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_runner()',
          $o$  v_engine := public.ottoq_engine_hash();
  SELECT e.* INTO x FROM public.ottoq_dial_experiments e
   WHERE e.status = 'active'
   ORDER BY (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
              WHERE l.experiment_id = e.experiment_id AND l.engine_hash = v_engine), e.created_at, e.experiment_id$o$,
          $n$  v_engine := public.ottoq_engine_hash();
  v_floor  := public.ottoq_dial_pair_floor();   -- 0523 (G250): pairs count from the dial floor, not the engine hash
  SELECT e.* INTO x FROM public.ottoq_dial_experiments e
   WHERE e.status = 'active'
   ORDER BY (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
              WHERE l.experiment_id = e.experiment_id AND l.ran_at >= v_floor), e.created_at, e.experiment_id$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_runner()',
          $o$  -- the next seed of this experiment's own sequence not yet paired on this engine; twice the final look allows$o$,
          $n$  -- the next seed of this experiment's own sequence not yet paired since the dial floor (0523); twice the final look allows$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_runner()',
          $o$                      WHERE l.experiment_id = x.experiment_id AND l.seed = s.seed AND l.engine_hash = v_engine)$o$,
          $n$                      WHERE l.experiment_id = x.experiment_id AND l.seed = s.seed AND l.ran_at >= v_floor)$n$, '1'],
    ARRAY['public.ottoq_dial_experiment_runner()',
          $o$                       format('all %s seeds of the sequence were spent on engine %s without a decision; the invalid pairs say why',
                              2 * x.final_look_pairs, v_engine))$o$,
          $n$                       format('all %s seeds of the sequence were spent since the dial floor %s (engine %s) without a decision; the invalid pairs say why',
                              2 * x.final_look_pairs, v_floor, v_engine))$n$, '1'],
    ARRAY['public.ottoq_dial_pair(uuid,bigint,integer)',
          $o$  v_engine := public.ottoq_engine_hash();
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_pair_ledger
              WHERE experiment_id = p_experiment_id AND seed = p_seed AND engine_hash = v_engine) THEN
    RAISE EXCEPTION 'dial_pair: seed % is already paired on engine % -- under determinism a re-run is repetition, not replication (G153)',
      p_seed, v_engine USING ERRCODE = '23505';
  END IF;$o$,
          $n$  v_engine := public.ottoq_engine_hash();
  -- 0523 (G250): "already paired" means since the dial floor, the rule the verdict counts by. Keyed on the engine hash,
  -- which every migration moves, a seed could be paired again after a change that cannot move an arm.
  IF EXISTS (SELECT 1 FROM public.ottoq_dial_pair_ledger
              WHERE experiment_id = p_experiment_id AND seed = p_seed AND ran_at >= public.ottoq_dial_pair_floor()) THEN
    RAISE EXCEPTION 'dial_pair: seed % is already paired since the dial floor % -- under determinism a re-run is repetition, not replication (G153)',
      p_seed, public.ottoq_dial_pair_floor() USING ERRCODE = '23505';
  END IF;$n$, '1']];
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.ottoq_dial_experiment_verdict(uuid)', 'public.ottoq_dial_experiment_runner()',
                              'public.ottoq_dial_pair(uuid,bigint,integer)'] LOOP
    v_def := pg_get_functiondef(v_fn::regprocedure);
    FOR i IN 1 .. array_length(v_edits, 1) LOOP
      CONTINUE WHEN v_edits[i][1] <> v_fn;
      v_old := v_edits[i][2]; v_new := v_edits[i][3]; v_want := v_edits[i][4]::int;
      n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      IF n <> v_want THEN RAISE EXCEPTION '0523: edit % to % matched % times, not %', i, v_fn, n, v_want; END IF;
      v_def := replace(v_def, v_old, v_new);
    END LOOP;
    EXECUTE v_def;
  END LOOP;
END $patch$;

DROP FUNCTION public.ottoq_dial_counted_pairs(uuid, text);

DO $verify$
DECLARE v_verdict text; v_runner text; v_pair text;
BEGIN
  v_verdict := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  v_runner  := pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure);
  v_pair    := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  -- V1: nothing counts, chooses or refuses by the engine hash any more; everything that did now reads the floor; the
  --     old counted-pairs signature is gone and the new one exists; 0522 is classified; all three keep their security
  --     and search_path
  IF position('engine_hash = v_engine' IN v_verdict) > 0 OR position('engine_hash <> v_engine' IN v_verdict) > 0
     OR position('engine_hash = v_engine' IN v_runner) > 0 OR position('engine_hash = v_engine' IN v_pair) > 0
     OR (length(v_verdict) - length(replace(v_verdict, 'ottoq_dial_counted_pairs(p_experiment_id, v_floor)', '')))
          / length('ottoq_dial_counted_pairs(p_experiment_id, v_floor)') <> 4
     OR position('''pair_floor'', v_floor' IN v_verdict) = 0
     OR position('l.ran_at >= v_floor), e.created_at' IN v_runner) = 0
     OR position('AND l.seed = s.seed AND l.ran_at >= v_floor)' IN v_runner) = 0
     OR position('AND ran_at >= public.ottoq_dial_pair_floor()) THEN' IN v_pair) = 0
     OR to_regprocedure('public.ottoq_dial_counted_pairs(uuid,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_dial_counted_pairs(uuid,timestamptz)') IS NULL
     OR (SELECT forces_dial_restart FROM public.ottoq_cert_lineage
          WHERE name = '0522_the_dial_window_closes_before_its_last_pair_could_outlast_it') IS DISTINCT FROM false
     OR NOT (SELECT bool_and(prosecdef) FROM pg_proc
              WHERE oid IN ('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure,
                            'public.ottoq_dial_experiment_runner()'::regprocedure,
                            'public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure,
                            'public.ottoq_dial_counted_pairs(uuid,timestamptz)'::regprocedure,
                            'public.ottoq_dial_pair_floor()'::regprocedure)) THEN
    RAISE EXCEPTION '0523 V1: the dial bookkeeping is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3: the floor reads it, and a migration being applied without its
-- lineage row would read as one that restarts dial pairs.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0523_a_dial_experiment_restarts_only_for_a_change_that_can_move_an_arm', false, false,
  'Dial-experiment bookkeeping only: pairs count, are chosen and are refused by a dial floor (the recert floor, or the '
  'last migration that does not declare forces_dial_restart=false) instead of an engine hash every migration moves; '
  'counted pairs take each seed once (G250).', now())
ON CONFLICT (name) DO NOTHING;

-- V3: rolled back. (a) The dial floor is the recert floor (0521's apply) and G240 counts its three pairs, none stale;
--     (b) a migration with no dial classification restarts every experiment: a lineage row stamped now moves the floor
--     to now and G240 counts none, and classifying it FALSE puts the floor back; (c) one that forces recert restarts
--     even when it claims not to restart dial pairs; (d) every active experiment's counted pairs carry each seed once.
DO $v3$
DECLARE v_msg text; v_floor0 timestamptz; v_c int; v_s int; v_bad int;
BEGIN
  BEGIN
    v_floor0 := public.ottoq_dial_pair_floor();
    IF v_floor0 IS DISTINCT FROM public.ottoq_cert_recert_floor() THEN
      RAISE EXCEPTION '0523 V3 FAILED (a): the dial floor % is not the recert floor %', v_floor0, public.ottoq_cert_recert_floor();
    END IF;
    v_c := (public.ottoq_dial_experiment_verdict('143a11c7-6740-4624-b747-e145f3533e60')->'pairs'->>'counted')::int;
    v_s := (public.ottoq_dial_experiment_verdict('143a11c7-6740-4624-b747-e145f3533e60')->'pairs'->>'stale_engine')::int;
    IF v_c IS DISTINCT FROM 3 OR v_s IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION '0523 V3 FAILED (a): G240 counts % and has % stale, not 3 and 0', v_c, v_s;
    END IF;

    INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
    VALUES ('0523_v3_unclassified', false, '0523 V3', now());
    IF public.ottoq_dial_pair_floor() IS DISTINCT FROM now()
       OR (public.ottoq_dial_experiment_verdict('143a11c7-6740-4624-b747-e145f3533e60')->'pairs'->>'counted')::int <> 0 THEN
      RAISE EXCEPTION '0523 V3 FAILED (b): an unclassified migration did not restart the experiment';
    END IF;
    UPDATE public.ottoq_cert_lineage SET forces_dial_restart = false WHERE name = '0523_v3_unclassified';
    IF public.ottoq_dial_pair_floor() IS DISTINCT FROM v_floor0 THEN
      RAISE EXCEPTION '0523 V3 FAILED (b): classifying it FALSE did not put the floor back';
    END IF;

    UPDATE public.ottoq_cert_lineage SET forces_recert = true WHERE name = '0523_v3_unclassified';
    IF public.ottoq_dial_pair_floor() IS DISTINCT FROM now() THEN
      RAISE EXCEPTION '0523 V3 FAILED (c): a migration that forces recert did not restart dial experiments';
    END IF;

    SELECT count(*) INTO v_bad
      FROM public.ottoq_dial_experiments e,
           LATERAL (SELECT count(*) AS n, count(DISTINCT c.seed) AS d
                      FROM public.ottoq_dial_counted_pairs(e.experiment_id, v_floor0) c) z
     WHERE e.status = 'active' AND z.n <> z.d;
    IF v_bad > 0 THEN
      RAISE EXCEPTION '0523 V3 FAILED (d): % experiment(s) count a seed twice', v_bad;
    END IF;
    RAISE EXCEPTION '0523 V3 PASSED: the dial floor is the recert floor (%); G240 counts 3 of 3; an unclassified migration restarts and a FALSE one does not; one that forces recert restarts regardless; no seed counted twice', v_floor0;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0523 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0523 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0523_pre' (the old counted-pairs
--   signature included), DROP FUNCTION public.ottoq_dial_counted_pairs(uuid, timestamptz), DROP FUNCTION
--   public.ottoq_dial_pair_floor(), ALTER TABLE public.ottoq_cert_lineage DROP COLUMN forces_dial_restart.
COMMIT;
