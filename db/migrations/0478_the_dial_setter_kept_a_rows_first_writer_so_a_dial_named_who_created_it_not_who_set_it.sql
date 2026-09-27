-- migration-version: 20260926115337
-- migration-name:    the_dial_setter_kept_a_rows_first_writer_so_a_dial_named_who_created_it_not_who_set_it
--
-- 0478  **The dial setter kept a row's first writer, so a dial named who created it, not who last set it.**
--       `db/checks/0361` §6. FINDINGS G213.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   At 11:25:33 UTC (6:25 AM CT) energy_reserve_shave was set back to 1 at the twin depot through
--   `public.ottoq_policy_set(..., p_by := 'claude_code:restore_promotion_9_after_0477')`. The row reads
--   `updated_by = ottoq_prime:promoter`, the label promotion 9 created it with at 09:40 UTC, although promotion 9 was
--   rolled back in between and the restore passed its own label.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The setter upserts with `ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value =
--   EXCLUDED.param_value, updated_at = now()`. An update keeps the old `updated_by`, so every depot and global dial
--   (96 rows today) names the first writer it ever had. The certification and dial-experiment harnesses write their
--   own rows with `updated_by = EXCLUDED.updated_by`; only the setter drops it.
--
--   Readers: the column's only readers are the two MPC lookaheads' cleanup (`DELETE … WHERE updated_by = 'mpc'`), and
--   neither runs (`ottoq_mpc_energy_lookahead` has no caller; `ottoq_mpc_lookahead`'s one caller, `ottoq_cil_tick`,
--   has no caller, no cron job and no recorded call). So the label misattributes and decides nothing.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The conflict clause also sets `updated_by = EXCLUDED.updated_by`. Nothing else moves: the clamp, the catalog
--   gates, the refusal contract and the AI.001 probe are untouched, and so are the grants (anon, authenticated and
--   service_role hold EXECUTE today; narrowing them belongs to the G69 security sweep, which is on hold).
--
-- ══ §4 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   No atom reads `ottoq_policy_params.updated_by`, and the setter's callers on a certification arm write run-scoped
--   rows keyed by a fresh run id, which always take the INSERT path this clause never reaches. Only the label on an
--   updated row changes.
--
--   PREDICTED: the next setter write on an existing depot row carries its caller's label in `updated_by`.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0478 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure))
     <> 'cc0c9dfbe8a9feba879bf9b566202f4d' THEN
    RAISE EXCEPTION '0478 P2: public.ottoq_policy_set is not the body this file patches';
  END IF;
  -- no atom reads the label (the functions that name both the table and the column only write it, or are the MPC
  -- lookaheads, which never run)
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE p.prosrc ~ 'ottoq_policy_params' AND p.prosrc ~ 'updated_by' AND n.nspname !~ '^pg_temp'
                AND n.nspname || '.' || p.proname NOT IN
                    ('public.ottoq_ab_pair', 'public.ottoq_determinism_pair', 'public.ottoq_determinism_pair_replay',
                     'public.ottoq_dial_pair', 'public.ottoq_mpc_energy_lookahead', 'public.ottoq_mpc_lookahead',
                     'public.ottoq_policy_set', 'twin.ottoq_grid_fixture_create')) THEN
    RAISE EXCEPTION '0478 P2: a new function reads or writes ottoq_policy_params.updated_by';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0478_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure;

DO $patch_setter$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure);
  v_pat text := $p$ON CONFLICT \(scope_type, scope_id, param_key\) DO UPDATE SET param_value = EXCLUDED\.param_value, updated_at = now\(\);$p$;
  v_new text := $r$ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_at = now(),
         -- 0478 (G213): the row names who set it last, not who created it
         updated_by = EXCLUDED.updated_by;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0478: the setter''s conflict clause matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_setter$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('public.ottoq_policy_set(text,uuid,text,numeric,text)'::regprocedure);
BEGIN
  -- V1: the conflict clause sets the writer, once, and the insert still takes p_by.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$updated_at = now\(\),\s+-- 0478 \(G213\)[^\n]*\n\s+updated_by = EXCLUDED\.updated_by;$x$, 'g')) <> 1
     OR position('VALUES (p_scope_type, p_scope_id, p_param_key, v_final, p_by)' IN v_s) = 0 THEN
    RAISE EXCEPTION '0478 V1: the setter is not the body this file writes';
  END IF;
  -- V2: one overload, the grants as they were.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'public' AND p.proname = 'ottoq_policy_set') <> 1 THEN
    RAISE EXCEPTION '0478 V2: an overload appeared';
  END IF;
  IF NOT has_function_privilege('anon', 'public.ottoq_policy_set(text,uuid,text,numeric,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_policy_set(text,uuid,text,numeric,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_policy_set(text,uuid,text,numeric,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0478 V2: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0478_pre' (CREATE OR REPLACE; the grants are kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0478_the_dial_setter_kept_a_rows_first_writer_so_a_dial_named_who_created_it_not_who_set_it', false,
  'Label only: ottoq_policy_set''s conflict clause also sets updated_by. No atom reads the column, and a '
  'certification arm''s run-scoped writes always take the insert path.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
