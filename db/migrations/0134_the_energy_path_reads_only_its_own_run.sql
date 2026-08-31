-- migration-version: 20260831190000
-- migration-name:    the_energy_path_reads_only_its_own_run
-- 0134 -- the normal_day 171717/12t carrier, CONVICTED FROM THE ROWS IT READ (db/checks/0046).
--
-- THE EVIDENCE. Post-0132/0133 the six-column ladder came back five-of-six green on the
-- predicted fPP pattern; normal_day 171717/12t returned `ff`. The 18:00 pair (run_a 0ed4293b,
-- run_b ab1bf781) forked in the worst shape the harness defines: world fingerprints EQUAL
-- (bd0426bb), boot images EQUAL, and ALL FOUR streams unequal -- which by db/checks/0046 s1 is
-- always a real defect, never a harness artifact. Localizing by per-tick hash:
--     ticks 1-3   identical
--     tick 4      FIRST divergent write -- energy commands only:
--                   bess_setpoint -458.8 vs -458.7   charge_cap 811.8 vs 811.9
--     tick 6      first DECISION divergence (42 vs 43 site-cap refusals); gap now 3.6 kW
--     final       cap refusals 240 vs 242 | enacted 1452 vs 1454 | decisions 1947 vs 1953
-- Every energy command in both arms carries source='otto_q' and mpc_step=null, so the external
-- AWS MPC is not in the path -- these are locally generated. Their reason payloads show BESS
-- soc_pct diverging (A 91.34 vs B 91.46; A 83.99 vs B 84.04) and temp_c differing in the last
-- decimal (34.21 vs 34.22), which points the finger at the BESS step's two world inputs:
-- site solar and ambient temperature.
--
-- THE CONVICTION. twin.ottoq_sim_advance_bess pulls both inputs, and pulls them from the whole
-- table rather than from its own run:
--     SELECT COALESCE(SUM(ac_power_kw),0) ... FROM ottoq_solar_output
--      WHERE depot_id = p_depot_id AND sim_clock_at BETWEEN ...        -- no sim_run_id
--     SELECT ambient_temp_c ... FROM ottoq_weather_snapshots
--      WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now -- no sim_run_id
--      ORDER BY sim_clock_at DESC LIMIT 1                              -- and no tie-break
-- Measured on the live table at a single sim_clock_at: the solar SUM ranges over 280 rows
-- spanning 70 DISTINCT RUNS, and the ambient pick ranges over 70 tied rows carrying 2 DISTINCT
-- temperature values. Both arms of a pair run inside one transaction, arm A then arm B, so
-- arm B's reads see arm A's freshly written rows and arm A's did not: the contamination is
-- ORDER-DEPENDENT BY CONSTRUCTION, and the 2-valued ambient pick is a straight coin between
-- 34.21 and 34.22 -- verbatim the observed delta.
--
-- THE PROOF THAT THIS IS THE WHOLE DEFECT. Each arm's OWN series are byte-identical to the
-- other's:
--     own-run ambient series   md5 a362d84371a154b8adeb621bc8056476  (A) == (B)
--     own-run solar   series   md5 2d8b905bdcaba461ae47ef7e5072b672  (A) == (B)
-- The twin GENERATES identical weather and solar per run under a fixed seed. The nondeterminism
-- is manufactured entirely by the READ. Run-scope the reads and both arms consume identical
-- inputs. Corollary, and the honest reading of round 3: 0132 introduced nothing. It made a
-- PRE-EXISTING energy-path defect observable by promoting the site cap from an inert note to a
-- decision input. 0133 fixed exactly this defect in twin.ottoq_sim_advance_site_energy; the
-- sibling readers were not censused at the time. They are, here.
--
-- CENSUS. Five live functions read ottoq_solar_output/ottoq_weather_snapshots (backups
-- excluded). One (twin.ottoq_sim_advance_site_energy) already carries its 0133 fix. The other
-- four are patched below:
--
--   * twin.ottoq_sim_advance_bess -- THE CARRIER. Solar SUM gains the run scope; ambient gains
--     the run scope AND a tie-break. Two further picks in the same function are totalized while
--     open: the ottoq_energy_commands pick (`ORDER BY issued_at DESC, created_at DESC LIMIT 1`
--     -- run-scoped already, but created_at is FROZEN inside a pair transaction and so cannot
--     break a tie, exactly as 0130 found) and the site_energy_snapshots pick (`ORDER BY
--     s.timestamp DESC LIMIT 1`). Both are PROVABLY NO-OP TODAY -- measured max 1 row per
--     (run,depot,type,issued_at,created_at) and per (run,timestamp) respectively -- so they
--     cost this round nothing and close the class.
--   * twin.ottoq_sim_advance_grid -- the SAME unscoped, untied ambient read, feeding the grid
--     model's LMP/tariff path. A second live carrier, found by census rather than by symptom.
--   * twin.ottoq_sim_advance_weather_and_solar -- reads its OWN previous precip_state from the
--     cross-run pool to drive the precipitation Markov chain. Latent carrier of the highest
--     order: a wrong read here forks the entire weather stream, not one setpoint. It did NOT
--     fire in this pair (both arms' weather hashed identical above), and it is closed anyway --
--     an unfired coin is still a coin.
--   * public.ottoq_twin_snapshot -- already run-scoped; its `ORDER BY w.sim_clock_at DESC
--     LIMIT 1` gains the last-resort key. Display-only, cannot reach the ladder; totality only.
--
-- WHY THE SOLAR SUM NEEDS NO ORDERING FIX. ac_power_kw is `numeric`, so SUM is exact and
-- order-independent; the multi-row SUM per (run,depot,clock) is legitimate multi-canopy
-- aggregation. Run scope alone makes it total. ambient_temp_c is likewise `numeric`, and within
-- a single (run,depot,sim_clock_at) the measured max distinct ambient value count is 1 -- so
-- the run scope alone already restores determinism there, and the tie-breaks below are
-- discipline (0062/0063: content keys first, the random uuid only as last resort), not the fix.
--
-- Run-scoping uses the 0020/0124 zero-uuid idiom so production rows (NULL sim_run_id) keep
-- matching a NULL p_sim_run_id and the production path is untouched.
--
-- Pre-image pins, read live 2026-08-31 (every anchor asserted at exactly 1 occurrence):
--   twin.ottoq_sim_advance_bess               701bc9ddf75a1ae3bc7ebb4be4f4e76c
--   twin.ottoq_sim_advance_grid               34c34ca5f608c337259cc427f8257cd7
--   twin.ottoq_sim_advance_weather_and_solar  7037ff5b0ad496beafb94655b1c28b59
--   public.ottoq_twin_snapshot                723d1b70c3cd9fb0aba473ad33a354a4

CREATE FUNCTION pg_temp.ottoq_0134_total(p_ns text, p_fn text, p_md5 text,
                                         p_old text, p_new text, p_expect int,
                                         p_prior int DEFAULT 0)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn AND p.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0134 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_old, ''))) / length(p_old);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0134 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_old, p_new);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0134', ''))) / length('/* 0134');
  IF v_cnt <> p_prior + p_expect THEN
    RAISE EXCEPTION '0134 abort: %.% patch survived % of % sites', p_ns, p_fn, v_cnt - p_prior, p_expect;
  END IF;
  RAISE NOTICE '0134: %.% -- % site(s) scoped/totalized.', p_ns, p_fn, p_expect;
END
$helper$;

DO $apply$
BEGIN
  -- ============ A. THE CARRIER: twin.ottoq_sim_advance_bess ============
  -- A1. The solar SUM stops integrating seventy other runs.
  PERFORM pg_temp.ottoq_0134_total(
    'twin', 'ottoq_sim_advance_bess', '701bc9ddf75a1ae3bc7ebb4be4f4e76c',
    'FROM ottoq_solar_output' || chr(10) ||
    '   WHERE depot_id = p_depot_id',
    'FROM ottoq_solar_output' || chr(10) ||
    '   WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0134 */' || chr(10) ||
    '     AND depot_id = p_depot_id',
    1, 0);

  -- A2. The ambient pick stops flipping a coin between two runs' temperatures.
  PERFORM pg_temp.ottoq_0134_total(
    'twin', 'ottoq_sim_advance_bess', NULL,
    'FROM ottoq_weather_snapshots' || chr(10) ||
    '   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now' || chr(10) ||
    '   ORDER BY sim_clock_at DESC LIMIT 1;',
    'FROM ottoq_weather_snapshots' || chr(10) ||
    '   WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0134 */' || chr(10) ||
    '     AND depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now' || chr(10) ||
    '   ORDER BY sim_clock_at DESC, ambient_temp_c DESC, snapshot_id DESC LIMIT 1;',
    1, 1);

  -- A3. Pending energy command: created_at is frozen in a pair, so it cannot break a tie (0130).
  PERFORM pg_temp.ottoq_0134_total(
    'twin', 'ottoq_sim_advance_bess', NULL,
    'ORDER BY issued_at DESC, created_at DESC LIMIT 1;',
    'ORDER BY issued_at DESC, created_at DESC, command_id DESC  /* 0134 */ LIMIT 1;',
    1, 2);

  -- A4. The site-energy load read.
  PERFORM pg_temp.ottoq_0134_total(
    'twin', 'ottoq_sim_advance_bess', NULL,
    'ORDER BY s.timestamp DESC LIMIT 1',
    'ORDER BY s.timestamp DESC, s.id DESC  /* 0134 */ LIMIT 1',
    1, 3);

  -- ============ B. The second live carrier: the grid model's ambient ============
  PERFORM pg_temp.ottoq_0134_total(
    'twin', 'ottoq_sim_advance_grid', '34c34ca5f608c337259cc427f8257cd7',
    'FROM ottoq_weather_snapshots' || chr(10) ||
    '   WHERE depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now' || chr(10) ||
    '   ORDER BY sim_clock_at DESC LIMIT 1;',
    'FROM ottoq_weather_snapshots' || chr(10) ||
    '   WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0134 */' || chr(10) ||
    '     AND depot_id = p_depot_id AND sim_clock_at <= p_sim_clock_now' || chr(10) ||
    '   ORDER BY sim_clock_at DESC, ambient_temp_c DESC, snapshot_id DESC LIMIT 1;',
    1, 0);

  -- ============ C. The latent chain-forker: the precip Markov feedback read ============
  PERFORM pg_temp.ottoq_0134_total(
    'twin', 'ottoq_sim_advance_weather_and_solar', '7037ff5b0ad496beafb94655b1c28b59',
    'FROM ottoq_weather_snapshots' || chr(10) ||
    '   WHERE depot_id = p_depot_id' || chr(10) ||
    '     AND sim_clock_at < p_sim_clock_now' || chr(10) ||
    '   ORDER BY sim_clock_at DESC LIMIT 1;',
    'FROM ottoq_weather_snapshots' || chr(10) ||
    '   WHERE COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10) ||
    '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)  /* 0134 */' || chr(10) ||
    '     AND depot_id = p_depot_id' || chr(10) ||
    '     AND sim_clock_at < p_sim_clock_now' || chr(10) ||
    '   ORDER BY sim_clock_at DESC, snapshot_id DESC LIMIT 1;',
    1, 0);

  -- ============ D. Display-only totality ============
  PERFORM pg_temp.ottoq_0134_total(
    'public', 'ottoq_twin_snapshot', '723d1b70c3cd9fb0aba473ad33a354a4',
    'ORDER BY w.sim_clock_at DESC LIMIT 1',
    'ORDER BY w.sim_clock_at DESC, w.snapshot_id DESC  /* 0134 */ LIMIT 1',
    1, 0);

  RAISE NOTICE '0134 applied: the energy path reads only its own run (4 functions, 7 sites).';
END
$apply$;

-- Post-condition: exactly four functions carry the marker, and 0133's fix in the sibling
-- reader is still in place (proving this migration did not regress the function it learned from).
DO $verify$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind = 'f'
     AND pg_get_functiondef(p.oid) LIKE '%/* 0134%';
  IF v_n <> 4 THEN RAISE EXCEPTION '0134 abort: % functions carry the marker, expected 4', v_n; END IF;

  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_site_energy'
      AND pg_get_functiondef(p.oid) LIKE '%/* 0133%';
  IF NOT FOUND THEN
    RAISE EXCEPTION '0134 abort: advance_site_energy lost its 0133 run-scope';
  END IF;

  -- No live reader of the two world tables may remain unscoped.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind = 'f'
     AND p.proname NOT LIKE '%backup%'
     AND (pg_get_functiondef(p.oid) LIKE '%ottoq_solar_output%'
       OR pg_get_functiondef(p.oid) LIKE '%ottoq_weather_snapshots%')
     AND pg_get_functiondef(p.oid) NOT LIKE '%/* 0133%'
     AND pg_get_functiondef(p.oid) NOT LIKE '%/* 0134%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0134 abort: % live world-table reader(s) still unscoped', v_n;
  END IF;

  RAISE NOTICE '0134 verified: 4 markers, 0133 intact, no unscoped world-table reader remains.';
END
$verify$;
