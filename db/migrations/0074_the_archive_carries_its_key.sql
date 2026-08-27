-- migration-version: 20260827210000
-- migration-name:    the_archive_carries_its_key
-- 0074 -- The run archive writes its own reproducibility key. Found by fixing the K3
-- certification in db/checks/0044_kpi_certification.sql: the moment K3 could fail, it did.
--
--     K3 repro_key    archives 155    unstamped 153    verdict FAIL
--
-- 153 of 155 archived runs carry no config_hash. The two that do were stamped by hand on
-- 2026-08-19, the day 0044 shipped. Ten more runs were archived after that date and none of
-- them were stamped. CLAUDE.md 2.9: "no number ships without a run ID." The run IDs exist.
-- The key that makes them mean something does not.
--
-- ============================================================================================
-- DEFECT 1 -- ottoq_run_archive_stamp is defined once and called from nowhere.
--
-- 0044_canonical_kpis.sql:173 created a helper to stamp (pack_id, config_hash) onto an archive.
-- Grep the entire repo for its name: one hit, the CREATE. No SQL, no edge function, no Python
-- calls it. The reproducibility key was made opt-in and nothing opted in.
--
-- Meanwhile public.ottoq_archive_run -- the ONLY writer of ottoq_run_archives (baseline
-- functions_public.sql:1075) -- returns a field literally named `reproducible_from`:
--
--     'reproducible_from', jsonb_build_object('scenario', ..., 'random_seed', ...,
--                                             'policy', ..., 'depot_id', ...)
--
-- Four fields, and not the fifth. 0044's own comment defines the key as
-- (policy, pack_id, random_seed, config_hash). config_hash is the only component that pins the
-- CONFIGURATION rather than the scenario label -- two runs of the same named scenario under
-- different payloads are indistinguishable without it. So the function hands back a claim of
-- reproducibility while omitting the one field that would let anyone check it.
--
-- WHY THE HELPER COULD NEVER HAVE WORKED AS A LATER STEP, which is the interesting part.
-- The helper computes the hash by reading ottoq_sim_runs. Production right now:
--
--     ottoq_sim_runs   10 rows        ottoq_run_archives   155 rows
--
-- Runs are purged after archiving -- correctly, that is what the retention machinery is for.
-- So by the time anyone calls the helper the run row is usually gone. The hash cannot be
-- recovered after the fact; it has to be taken at archive time, while the payload is still in
-- hand. THE FIX puts it there. ottoq_archive_run already holds v_run.payload two lines above
-- the INSERT.
--
-- Same expression as the helper's (md5 of payload::text), deliberately, so the two rows stamped
-- on 2026-08-19 stay comparable with everything written from here on. jsonb::text is already
-- canonical in Postgres -- keys sorted, whitespace normalized -- which is what 0044 meant by
-- "canonicalized run config".
--
-- NULL payload yields md5(NULL) = NULL, not a hash. That is intentional; see defect 2.
--
-- ============================================================================================
-- DEFECT 2 -- the helper's fallback fabricates a hash that certifies nothing.
--
--     v_hash := md5(COALESCE(p_config::text, (SELECT r.payload::text FROM ottoq_sim_runs r
--                                              WHERE r.sim_run_id = p_run), ''));
--
-- Read the last argument. Called with no config on a run already purged -- the common case, per
-- the 10-vs-155 count above -- both COALESCE branches are NULL and it stamps md5('') =
-- d41d8cd98f00b204e9800998ecf8427e. A CONSTANT. Every such archive gets the same value, K3 goes
-- green, and 153 mutually unrelated runs are certified as sharing a configuration.
--
-- That is worse than the NULL it replaces, and it is the same shape as the bug this migration
-- came from: a check that cannot fail, and now a key that cannot disagree. Dropping the ''
-- fallback makes v_hash NULL when the config is genuinely unavailable, the column stays NULL,
-- and K3 reports it unstamped -- which is true. The helper also returns config_hash in its key
-- object, so a caller sees the NULL directly.
--
-- NOT BACKFILLED. The 153 rows cannot be repaired: their payloads were purged. Inventing hashes
-- for them would be the fabrication this file exists to remove. They stay unstamped and K3 keeps
-- reporting FAIL until they age out and every archive written from here carries its key.
-- The red is the honest state of the evidence, not a regression.
--
-- ============================================================================================
-- MECHANISM. Same self-verifying in-place patch as 0054-0073: anchors pre-verified read-only as
-- occurring exactly once, replacement by string substitution on pg_get_functiondef, and
-- post-conditions that RAISE if an anchor survives or a replacement is absent.
--
-- Pre-image pins, read from production 2026-08-27:
--   public.ottoq_archive_run          e110ad90048ee572cb059a70cdb51935
--   public.ottoq_run_archive_stamp    c01067dfce3f9c7617e406ab1237a0fa
-- All five anchors pre-verified read-only at exactly 1 occurrence, and the full substitution
-- was dry-run read-only: config_hash absent from ottoq_archive_run before (0 occurrences),
-- present in all four positions after.

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_anchor text; v_cnt int;

  --: The INSERT gains the column and the value. md5(v_run.payload::text) is the helper's own
  --: expression, kept identical so pre-existing stamps remain comparable.
  v_a1_old text := 'metrics, run_payload)';
  v_a1_new text := 'metrics, run_payload, config_hash)';
  v_a2_old text := 'v_metrics, v_run.payload)';
  v_a2_new text := 'v_metrics, v_run.payload, md5(v_run.payload::text))';

  --: Re-archiving a run (ON CONFLICT) refreshes the payload, so the hash must move with it or
  --: the key would describe a configuration the row no longer holds.
  v_a3_old text := 'metrics = EXCLUDED.metrics, run_payload = EXCLUDED.run_payload;';
  v_a3_new text := 'metrics = EXCLUDED.metrics, run_payload = EXCLUDED.run_payload, config_hash = EXCLUDED.config_hash;';

  --: `reproducible_from` becomes true to its name.
  v_a4_old text := E'''policy'', v_run.policy, ''depot_id'', v_run.depot_id)';
  v_a4_new text := E'''policy'', v_run.policy, ''depot_id'', v_run.depot_id, ''config_hash'', md5(v_run.payload::text))';

  --: Drops the '' fallback. NULL config now yields NULL hash, not md5('').
  v_a5_old text := E'p_run), ''''));';
  v_a5_new text := 'p_run)));';
BEGIN
  -- ---------- DEFECT 1: public.ottoq_archive_run ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_archive_run';

  v_src := pg_get_functiondef(v_oid);

  IF position('config_hash' in v_src) > 0 THEN
    RAISE EXCEPTION '0074 abort: ottoq_archive_run already mentions config_hash; refusing to patch twice';
  END IF;

  FOREACH v_anchor IN ARRAY ARRAY[v_a1_old, v_a2_old, v_a3_old, v_a4_old] LOOP
    v_cnt := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
    IF v_cnt <> 1 THEN
      RAISE EXCEPTION '0074 abort: ottoq_archive_run anchor [%] found % times, expected exactly 1', v_anchor, v_cnt;
    END IF;
  END LOOP;

  v_new := replace(v_src,  v_a1_old, v_a1_new);
  v_new := replace(v_new,  v_a2_old, v_a2_new);
  v_new := replace(v_new,  v_a3_old, v_a3_new);
  v_new := replace(v_new,  v_a4_old, v_a4_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, 'config_hash', ''))) / length('config_hash');
  IF v_cnt <> 4 THEN
    RAISE EXCEPTION '0074 abort: ottoq_archive_run carries config_hash % times after patch, expected 4', v_cnt;
  END IF;

  -- ---------- DEFECT 2: public.ottoq_run_archive_stamp ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_run_archive_stamp';

  v_src := pg_get_functiondef(v_oid);

  v_cnt := (length(v_src) - length(replace(v_src, v_a5_old, ''))) / length(v_a5_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0074 abort: stamp fallback anchor found % times, expected exactly 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a5_old, v_a5_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position(v_a5_old in v_src) > 0 THEN
    RAISE EXCEPTION '0074 abort: ottoq_run_archive_stamp still fabricates md5('''') on a missing config';
  END IF;

  RAISE NOTICE '0074 applied: ottoq_archive_run stamps config_hash at archive time; the empty-config fallback is gone.';
END
$do$;

-- ============================================================================================
-- VERIFICATION -- run after apply.
--
--   -- 1. The next archived run must carry a hash. Until one is archived this returns the
--   --    unchanged 2/153 split; it is not evidence either way on its own.
--   SELECT config_hash IS NULL AS unstamped, count(*), max(archived_at)
--     FROM public.ottoq_run_archives GROUP BY 1 ORDER BY 1;
--
--   -- 2. No archive may share the empty-string hash. This must return zero rows forever.
--   SELECT sim_run_id FROM public.ottoq_run_archives
--    WHERE config_hash = md5('');
--
--   -- 3. K3 in db/checks/0044_kpi_certification.sql moves toward PASS only as new runs land.
--
-- WHAT WOULD PROVE THIS WRONG: two archives with different run_payload sharing a config_hash,
-- or any archive whose config_hash is d41d8cd98f00b204e9800998ecf8427e. Either means a hash was
-- computed over something other than the run's own configuration, and the key is decorative
-- again.
