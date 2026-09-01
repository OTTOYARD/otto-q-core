-- 0140: the matrix knows when it went stale
--
-- public.ottoq_cert_matrix() is the one command that answers "are we certified". Today it
-- answers by counting consecutive passes on the most recent canon and nothing else. It
-- reports last_pair_at but does not use it. So a column certified before the engine changed
-- reads exactly as green as one certified a minute ago.
--
-- That is not hypothetical either. At the time of writing the matrix reports six green
-- columns. Two of them last ran before four merged migrations changed the engine:
--
--   busy_day 171717/24t   last pair 08-31 16:08
--   busy_day 424242/24t   last pair 08-31 15:32
--   recert floor          08-31 23:12  (0137, which changed the world fingerprint itself)
--
-- Those two are certifying an engine that no longer exists, and the matrix calls them green.
-- Anyone reading it -- including me, an hour ago -- would ship on that.
--
-- This is the same defect class as 0139: an instrument that cannot fail where it should.
-- The fix uses the ledger that already exists rather than inventing one. Supabase records
-- every applied migration in supabase_migrations.schema_migrations with a sortable
-- timestamp version, all 793 of them well-formed. A column is green only if its last pair
-- ran at or after the most recent migration that forces re-certification.
--
-- Two kinds of migration force it, and both are covered by one flag:
--   * canon-invalidating  -- the five hashes themselves would move (0134-0137)
--   * verdict-strengthening -- the pass criterion got stricter, so earlier passes were
--                              never tested to the current standard (0139)
-- A migration that touches neither the engine nor the verdict -- a KPI view, a reader --
-- is exempt, and must say so explicitly. Absence from the exemption table means it forces
-- re-certification. That is the safe direction: an unclassified migration costs a re-run,
-- it never inherits a green it did not earn.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- 1. The exemption register. Rows are exemptions and confirmations; absence means "forces".
-- ---------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_cert_lineage (
  name           text PRIMARY KEY,
  forces_recert  boolean     NOT NULL DEFAULT true,
  note           text        NOT NULL,
  classified_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_cert_lineage IS
  'Which migrations force the determinism matrix to be re-certified. A migration absent '
  'from this table forces re-certification by default -- exemption must be claimed '
  'explicitly and justified in note. Keyed by migration name, matching '
  'supabase_migrations.schema_migrations.name.';

-- ---------------------------------------------------------------------------------------
-- 2. The floor. No pair older than this can be counted toward a green.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_cert_recert_floor()
RETURNS timestamptz LANGUAGE sql STABLE
SET search_path TO 'public', 'supabase_migrations', 'extensions'
AS $fn$
  -- The version guard is not decoration: a malformed version would otherwise be parsed by
  -- substr into a wrong date. 0140 asserts there are none at apply time; this keeps a
  -- future malformed one from silently lowering the floor.
  SELECT max(make_timestamptz(
           substr(m.version,1,4)::int,  substr(m.version,5,2)::int,
           substr(m.version,7,2)::int,  substr(m.version,9,2)::int,
           substr(m.version,11,2)::int, substr(m.version,13,2)::numeric, 'UTC'))
    FROM supabase_migrations.schema_migrations m
    LEFT JOIN public.ottoq_cert_lineage l ON l.name = m.name
   WHERE COALESCE(l.forces_recert, true)
     AND m.version ~ '^[0-9]{14}$';
$fn$;

COMMENT ON FUNCTION public.ottoq_cert_recert_floor() IS
  'Timestamp of the most recent migration that forces determinism re-certification. '
  'A pair that ran before this cannot count toward a green column.';

-- ---------------------------------------------------------------------------------------
-- 3. Classify what is already applied. Confirmations are recorded, not only exemptions,
--    so the register reads as a decision log rather than a list of excuses.
-- ---------------------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('the_energy_path_reads_only_its_own_run', true,
   '0134: run-scoped four cross-run world reads in the twin energy path. Moves the canon.'),
  ('the_battery_starts_cold_and_the_fingerprint_sees_it', true,
   '0135: canonicalized BESS reset state and added five columns to the fingerprint. Moves the canon.'),
  ('the_site_limit_is_an_input', true,
   '0136: the charge cap stopped following the simulated battery. Moves the canon.'),
  ('the_fingerprint_stops_hashing_a_write_timestamp', true,
   '0137: removed current_soc_updated_at from the world fingerprint. Moves the canon.'),
  ('the_demand_we_cause_carries_the_run_id', false,
   '0138: added the peak_site_kw_demand KPI view and a provenance block. Reads only -- '
   'touches no decide path, no fingerprint, no verdict. Exempt.'),
  ('the_end_state_is_part_of_the_verdict', true,
   '0139: puts the end-of-run world image in the pair verdict. Does not move the five '
   'canon hashes, but every earlier pass was judged by a weaker criterion, so the whole '
   'matrix must be re-earned under the stricter one.'),
  ('the_matrix_knows_when_it_went_stale', false,
   '0140: this migration. Changes only how the matrix is READ -- the recert floor, the '
   'stale flag, the green gate. No engine, no fingerprint, no verdict. Exempt.')
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = now();

-- ---------------------------------------------------------------------------------------
-- 4. Gate the matrix. Return type changes, so this is a drop and recreate.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  c_pin CONSTANT text := 'b3dbfd98a1f325ba992d58911f961464';
  v_pin text;
  v_bad int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_pin
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
  IF v_pin IS NULL THEN
    RAISE EXCEPTION '0140: public.ottoq_cert_matrix not found';
  END IF;
  IF v_pin <> c_pin THEN
    RAISE EXCEPTION '0140: ottoq_cert_matrix moved under this migration (pin %, found %)', c_pin, v_pin;
  END IF;

  SELECT count(*) INTO v_bad FROM supabase_migrations.schema_migrations
   WHERE version !~ '^[0-9]{14}$';
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0140: % migration versions are not 14-digit; the floor cannot be parsed', v_bad;
  END IF;
END
$do$;

DROP FUNCTION IF EXISTS public.ottoq_cert_matrix(timestamptz);

CREATE FUNCTION public.ottoq_cert_matrix(p_since timestamptz DEFAULT (now() - '30 days'::interval))
RETURNS TABLE(seed bigint, ticks integer, scenario text, pairs_seen integer,
              consecutive_passes integer, green boolean, last_pair_at timestamptz,
              canon_fp text, canon_cmd text, canon_dec text, canon_evt text, canon_bkg text,
              last_run_a uuid, last_run_b uuid, history text,
              stale boolean, recert_floor timestamptz)
LANGUAGE sql STABLE
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
WITH pair AS (
  SELECT DISTINCT ON (r.started_at)
         r.started_at                            AS t0,
         (r.validation_status = 'passed')        AS ok,
         (r.validation_notes::jsonb)             AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= p_since
     AND r.validation_status IS NOT NULL
     AND r.validation_notes IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
   ORDER BY r.started_at, r.sim_run_id
), col AS (
  SELECT p.t0, p.ok,
         (p.j->>'seed')::bigint                    AS c_seed,
         COALESCE((p.j->>'ticks')::int, -1)        AS c_ticks,
         COALESCE(p.j->>'scenario', '?')           AS c_scen,
         p.j->'arm_a'->>'fp'                       AS c_fp,
         p.j->'arm_a'->>'h_cmd'                    AS c_cmd,
         p.j->'arm_a'->>'h_dec'                    AS c_dec,
         p.j->'arm_a'->>'h_evt'                    AS c_evt,
         p.j->'arm_a'->>'h_bkg'                    AS c_bkg,
         (p.j->'arm_a'->>'run')::uuid              AS c_run_a,
         (p.j->'arm_b'->>'run')::uuid              AS c_run_b
    FROM pair p
), ranked AS (
  SELECT c.*, row_number() OVER (PARTITION BY c.c_seed, c.c_ticks, c.c_scen
                                 ORDER BY c.t0 DESC, c.c_run_a DESC) AS rn
    FROM col c
), canon AS (
  SELECT rk.c_seed, rk.c_ticks, rk.c_scen, rk.c_fp, rk.c_cmd, rk.c_dec, rk.c_evt, rk.c_bkg
    FROM ranked rk WHERE rk.rn = 1
), marked AS (
  SELECT r.c_seed, r.c_ticks, r.c_scen, r.rn,
         (r.ok
          AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
          AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
          AND r.c_dec IS NOT DISTINCT FROM k.c_dec
          AND r.c_evt IS NOT DISTINCT FROM k.c_evt
          AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg) AS on_canon
    FROM ranked r
    JOIN canon k ON k.c_seed = r.c_seed AND k.c_ticks = r.c_ticks AND k.c_scen = r.c_scen
), streak AS (
  SELECT x.c_seed, x.c_ticks, x.c_scen,
         count(*) FILTER (WHERE x.unbroken)::int AS n_pass
    FROM (
      SELECT m.c_seed, m.c_ticks, m.c_scen,
             bool_and(m.on_canon) OVER (PARTITION BY m.c_seed, m.c_ticks, m.c_scen
                                        ORDER BY m.rn
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS unbroken
        FROM marked m
    ) x
   GROUP BY x.c_seed, x.c_ticks, x.c_scen
), hist AS (
  SELECT c.c_seed, c.c_ticks, c.c_scen,
         string_agg(CASE WHEN c.ok THEN 'P' ELSE 'f' END, '' ORDER BY c.t0) AS h_hist,
         count(*)::int AS n_pairs
    FROM col c GROUP BY c.c_seed, c.c_ticks, c.c_scen
), fl AS (
  SELECT public.ottoq_cert_recert_floor() AS rf
)
SELECT h.c_seed, h.c_ticks, h.c_scen, h.n_pairs,
       COALESCE(s.n_pass, 0),
       -- Two consecutive passes on one canon is necessary and no longer sufficient: the
       -- canon must also postdate the last engine or verdict change.
       (COALESCE(s.n_pass, 0) >= 2 AND l.t0 >= fl.rf),
       l.t0, l.c_fp, l.c_cmd, l.c_dec, l.c_evt, l.c_bkg, l.c_run_a, l.c_run_b,
       h.h_hist,
       (l.t0 < fl.rf),
       fl.rf
  FROM hist h
  JOIN streak s ON s.c_seed = h.c_seed AND s.c_ticks = h.c_ticks AND s.c_scen = h.c_scen
  JOIN ranked l ON l.c_seed = h.c_seed AND l.c_ticks = h.c_ticks
               AND l.c_scen = h.c_scen AND l.rn = 1
  CROSS JOIN fl
 ORDER BY h.c_ticks DESC, h.c_scen, h.c_seed;
$function$;

COMMENT ON FUNCTION public.ottoq_cert_matrix(timestamptz) IS
  'The determinism certification matrix. green requires two consecutive passes on one '
  'canon AND a canon no older than ottoq_cert_recert_floor(). stale marks a column whose '
  'last pair predates the most recent engine or verdict change.';

-- ---------------------------------------------------------------------------------------
-- 5. Prove the gate distinguishes. If every column still reads green, the gate is inert
--    and this migration bought nothing.
-- ---------------------------------------------------------------------------------------
DO $chk$
DECLARE v_stale int; v_green int; v_floor timestamptz;
BEGIN
  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor IS NULL THEN
    RAISE EXCEPTION '0140: recert floor is null -- the migration ledger was not readable';
  END IF;

  SELECT count(*) FILTER (WHERE m.stale), count(*) FILTER (WHERE m.green)
    INTO v_stale, v_green
    FROM public.ottoq_cert_matrix() m;

  IF v_stale = 0 THEN
    RAISE EXCEPTION
      '0140: no column reads stale, but the 24-tick columns last ran 08-31 15:32 and 16:08 '
      'against a floor of %. The gate is inert.', v_floor;
  END IF;
  -- A parse bug in the floor would show up as an absurd timestamp long before it showed
  -- up as a wrong verdict, so check the floor itself rather than the count of survivors.
  IF v_floor > now() OR v_floor < now() - interval '1 year' THEN
    RAISE EXCEPTION '0140: recert floor % is not a plausible migration time', v_floor;
  END IF;

  -- v_green = 0 is NOT an error. Apply 0140 BEFORE 0139 and four columns survive; apply it
  -- after and every column is legitimately stale, because 0139 strengthens the verdict and
  -- no earlier pass was judged by it. Both are correct states, so this is a notice.
  IF v_green = 0 THEN
    RAISE NOTICE
      '0140: every column reads stale against floor %. Correct if a verdict-strengthening '
      'migration was just applied; all columns must be re-earned.', v_floor;
  END IF;
  RAISE NOTICE '0140: floor %, % column(s) stale, % green.', v_floor, v_stale, v_green;
END
$chk$;

COMMIT;
