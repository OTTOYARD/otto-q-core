-- migration-version: 20261002194411
-- migration-name:    the_in_flight_probe_sees_an_overnight_sweep_arm
--
-- 0579  **The in-flight probe every migration's P0 relies on now sees an overnight sweep arm.** Harness only. (G305)
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_certification_in_flight` counts other backends whose query text `ottoq_certification_rig_matches` accepts.
--   0513 wrote the patterns for the rigs that existed then: the determinism and A/B pairs, the recert runner, the dial
--   pair and the dial runner. 0568's overnight sweep came later and was never added. Its cron entry is
--   `SET statement_timeout = 0; SELECT public.ottoq_throughput_sweep_runner();`, and one arm holds the world for 96-140
--   minutes in that one statement. On 2026-10-01 at 11:22 UTC the probe read 0 with arm 28 eighty minutes in
--   (db/checks/0414 §5). Every P0 since 0571 reads "a pair, the recert runner, a dial pair or a sweep arm is running
--   right now"; the sweep-arm clause had never been true. The two guards that call the probe had the same blind spot:
--   the calibration write guard (a refit could land under a running arm) and the ingest refresh.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_certification_rig_matches` also accepts a call of `ottoq_throughput_sweep_runner(` or
--   `ottoq_throughput_sweep_arm(`, case-insensitive, with any whitespace before the parenthesis. It matches the CALL, not
--   the name: a plain `%ottoq_throughput_sweep_arm%` would also match anyone reading the `ottoq_throughput_sweep_arms`
--   table, and the window's own cron entries name the dial `throughput_sweep_runner_enabled`. The sweep goes with the
--   dial rigs, under `p_with_dial`: it is the research wing's test, not a certification. Every caller passes true.
--   Nothing else changes; the patterns that were there match exactly as before (V3).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the rig is the body 0513 wrote (md5 pinned), the sweep runner is scheduled, and this has not
--   been applied. The rig goes to `ottoq_schema_snapshots` as '0579_pre'.
--   V1: the rig accepts the live cron command of `ottoq-throughput-sweep-runner` with p_with_dial true and refuses it with
--   false, and accepts a hand-run arm in three spellings. V2: it refuses a read of the arms table, both window cron
--   commands, the depot tick and NULL. V3: everything 0513's V3 asserted still holds.
--   Executed end to end, with a second backend running a sweep arm, by tests/test_certification_probe_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: a harness probe. The engine never calls it.
--
-- ROLLBACK: re-create public.ottoq_certification_rig_matches from its '0579_pre' snapshot; restore the comment on
--   public.ottoq_certification_in_flight from 0513; DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0579_the_in_flight_probe_sees_an_overnight_sweep_arm'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0579 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: the rig 0513 wrote, the runner scheduled, not yet applied ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0579_the_in_flight_probe_sees_an_overnight_sweep_arm') THEN
    RAISE EXCEPTION '0579 P1: already applied';
  END IF;
  IF to_regprocedure('public.ottoq_certification_rig_matches(text,boolean)') IS NULL
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_certification_rig_matches(text,boolean)'::regprocedure)
        <> 'f00f680acecfec2f092e470c465269b2' THEN
    RAISE EXCEPTION '0579 P1: ottoq_certification_rig_matches is not the body 0513 wrote';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-throughput-sweep-runner'
                    AND command ILIKE '%ottoq_throughput_sweep_runner()%') THEN
    RAISE EXCEPTION '0579 P1: the sweep runner is not scheduled as 0568 scheduled it';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0579_pre', 'function', 'public', 'ottoq_certification_rig_matches', d, md5(d)
  FROM (SELECT pg_get_functiondef('public.ottoq_certification_rig_matches(text,boolean)'::regprocedure) AS d) z;

CREATE OR REPLACE FUNCTION public.ottoq_certification_rig_matches(p_query text, p_with_dial boolean DEFAULT true)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path = pg_catalog
AS $fn$
  -- 0513 (G243). pg_stat_activity keeps the first 1 kB of a query (track_activity_query_size), and the recert runner
  -- (cron 746) names ottoq_determinism_pair past it (G194). Its advisory-lock key, ottoq_recert_runner, is in its
  -- first 100 characters, so that is what identifies it.
  -- 0579 (G305): the overnight sweep is matched by its CALL, so a read of ottoq_throughput_sweep_arms or a write of the
  -- throughput_sweep_runner_enabled dial is not taken for an arm.
  SELECT COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_determinism_pair%', '%ottoq_ab_pair%', '%ottoq_recert_runner%'])
      OR (COALESCE(p_with_dial, true)
          AND (COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_dial_pair%', '%ottoq_dial_experiment_runner%'])
               OR COALESCE(p_query, '') ~* 'ottoq_throughput_sweep_(runner|arm)\s*\('));
$fn$;

COMMENT ON FUNCTION public.ottoq_certification_in_flight(boolean) IS
  '0513 (G243), 0579 (G305). Backends other than the caller running a certification rig: a determinism, A/B or dial '
  'pair, the dial experiment runner, the recert runner (matched by its lock key, since it names the pair past the 1 kB '
  'of query text pg_stat_activity keeps, G194), or an overnight sweep arm (the runner''s or an arm''s call). '
  'p_with_dial=false leaves out the research wing''s rigs: the dial pair, the dial runner and the sweep. Use this, not a copy.';

-- ── V1: the live cron entry and a hand-run arm are seen ──
DO $v1$
DECLARE v_cmd text;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'ottoq-throughput-sweep-runner';
  IF NOT public.ottoq_certification_rig_matches(v_cmd, true) THEN
    RAISE EXCEPTION '0579 V1: the probe does not see the sweep runner''s cron command: %', v_cmd;
  END IF;
  IF public.ottoq_certification_rig_matches(v_cmd, false) THEN
    RAISE EXCEPTION '0579 V1: the sweep is counted as a certification with p_with_dial false';
  END IF;
  IF NOT public.ottoq_certification_rig_matches(
           'SELECT public.ottoq_throughput_sweep_arm(''8a1e12ae-b64b-4b6e-a82d-370f6f58315c''::uuid, 1, false)', true)
     OR NOT public.ottoq_certification_rig_matches('select OTTOQ_THROUGHPUT_SWEEP_ARM (c, s, r) from t', true)
     OR NOT public.ottoq_certification_rig_matches(E'SELECT public.ottoq_throughput_sweep_runner\n()', true) THEN
    RAISE EXCEPTION '0579 V1: a hand-run arm or runner is not seen';
  END IF;
END $v1$;

-- ── V2: what names the sweep without running it is not seen ──
DO $v2$
DECLARE v_open text; v_close text;
BEGIN
  SELECT command INTO v_open FROM cron.job WHERE jobname = 'ottoq_sweep_window_open';
  SELECT command INTO v_close FROM cron.job WHERE jobname = 'ottoq_sweep_window_close';
  IF public.ottoq_certification_rig_matches('SELECT * FROM public.ottoq_throughput_sweep_arms ORDER BY arm_id', true)
     OR public.ottoq_certification_rig_matches(COALESCE(v_open, 'x'), true)
     OR public.ottoq_certification_rig_matches(COALESCE(v_close, 'x'), true)
     OR public.ottoq_certification_rig_matches('SELECT public.ottoq_cron_tick()', true)
     OR public.ottoq_certification_rig_matches(NULL, true) THEN
    RAISE EXCEPTION '0579 V2: the probe takes a read of the arms table, a window cron entry, the tick or NULL for an arm';
  END IF;
END $v2$;

-- ── V3: 0513's V3, unchanged ──
DO $v3$
BEGIN
  IF NOT public.ottoq_certification_rig_matches('SELECT public.ottoq_determinism_pair(p_seed => 1)', false)
     OR NOT public.ottoq_certification_rig_matches('SELECT pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner''))', false)
     OR NOT public.ottoq_certification_rig_matches('SELECT public.ottoq_ab_pair(1)', false)
     OR NOT public.ottoq_certification_rig_matches('SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();', true)
     OR public.ottoq_certification_rig_matches('SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();', false)
     OR NOT public.ottoq_certification_rig_matches('SELECT public.ottoq_dial_pair(e, 1, 10)', true)
     OR public.ottoq_certification_rig_matches('SELECT public.ottoq_dial_pair(e, 1, 10)', false) THEN
    RAISE EXCEPTION '0579 V3: a rig 0513 matched is matched differently now';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0579_the_in_flight_probe_sees_an_overnight_sweep_arm', false, false,
  'Lane A harness (G305). ottoq_certification_rig_matches also accepts a call of ottoq_throughput_sweep_runner( or '
  'ottoq_throughput_sweep_arm(, under p_with_dial, so every P0, the calibration write guard and the ingest refresh see '
  'an overnight sweep arm. On 2026-10-01 the probe read 0 with arm 28 eighty minutes in. A harness probe; the engine '
  'never calls it.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
