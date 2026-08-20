-- migration-version: 20260820050000
-- migration-name:    manifest_run_relative_draw_salt
-- 0055 — C7 FOLLOW-UP #9, found by re-certification #9 (post-0054 arms
-- b982b594 vs 1c552be5: 1/20 identical, first divergence sim-min 60 — the
-- SAME tick-2 signature as #8: 10 vehicles swapping charge_complete_holding
-- <-> staged_for_departure with every SoC paired, and this time every cursor
-- on the path is proven ordered). The offender is one level down: the wash
-- triage's verdict is a pure function of each vehicle's SERVICE MANIFEST, and
-- twin.ottoq_sim_generate_service_manifest salts every one of its 21 seeded
-- draws (fault, urgency, inspection, tidy, wash, PM, calibration, ...) plus
-- its 3 duration-card deals with v_visit = vehicle || ':' ||
-- to_char(v_clock,'YYYYMMDDHH24MISS') — the ABSOLUTE sim clock (the 0045 salt
-- class), which its own 0020 note documents as deliberately doubling as the
-- draw salt. Two same-seed runs therefore deal different manifests by
-- construction, and the triage stages a different subset.
--
-- THE FIX splits the two roles: v_visit stays the ledger key everywhere
-- (visit_key, rider-flag binding, carryover, meta — nothing about run-scoped
-- visit identity moves); the 24 draw/deal sites move to a new v_salt in the
-- run-relative domain (whole minutes since sim_clock_start, GREATEST(0,...)
-- so the tick-1 arrival batch cannot straddle a bucket; no-run callers keep
-- the old absolute salt verbatim).
--
-- Same self-verifying in-place mechanism as 0054, extended with an expected
-- occurrence count per patch: pre-image md5 pinned
-- (17f845f5c31c6aab0dcf484df5ff4541), each anchor's occurrence count asserted
-- (the 21-site salt rename is one global replace asserting exactly 21), any
-- mismatch aborts the whole transaction.

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int; v_first boolean := true;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    (1,$anchor$  v_rf_place boolean := false; v_rf_retire boolean := false;$anchor$,$anchor$  v_rf_place boolean := false; v_rf_retire boolean := false;
  v_salt text;   /* 0055: run-relative draw salt; v_visit stays the ledger key */$anchor$),
    (1,$anchor$  v_visit := p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS');$anchor$,$anchor$  v_visit := p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS');
  /* ══════════ 0055: THE DRAW SALT LEAVES THE ABSOLUTE-CLOCK DOMAIN ══════════
     v_visit embeds the ABSOLUTE sim clock, and (per the 0020 note above) it was
     also the salt for every seeded draw below — so two same-seed runs, anchored
     to different wall-clock starts, drew DIFFERENT manifests by construction
     (measured: re-certs #8/#9, tick-2 holding<->staged swaps with every SoC
     paired — the manifests decided the wash-triage verdicts). The fix splits
     the two roles 0020 fused: v_visit REMAINS the ledger key everywhere
     (visit_key upsert, rider-flag binding, carryover note, meta), while the
     draws move to v_salt — whole MINUTES since the run's own sim_clock_start
     (the 0045 domain; minutes not seconds, and GREATEST(0,…), so the tick-1
     arrival batch — whose v_clock is the reset's wall clock, fractionally
     BEFORE sim_clock_start — lands in bucket 0 in every run instead of
     straddling a second boundary). No-run callers keep the old absolute salt
     verbatim, so live behavior is unchanged where there is no run to key on. */
  v_salt := p_vehicle_id::text || ':' ||
            COALESCE((SELECT GREATEST(0, floor(EXTRACT(EPOCH FROM (v_clock - r.sim_clock_start)) / 60.0))::text
                        FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run),
                     to_char(v_clock, 'YYYYMMDDHH24MISS'));$anchor$),
    (21,$anchor$ottoq_sim_seeded_random(v_seed, v_visit || $anchor$,$anchor$ottoq_sim_seeded_random(v_seed, v_salt || $anchor$),
    (1,$anchor$ottoq_twin_deal(v_run,'wash_time',        v_visit, v_clock, v_sim_day, 0, 'global')$anchor$,$anchor$ottoq_twin_deal(v_run,'wash_time',        v_salt, v_clock, v_sim_day, 0, 'global')$anchor$),
    (1,$anchor$ottoq_twin_deal(v_run,'detail_time',      v_visit, v_clock, v_sim_day, 0, 'global')$anchor$,$anchor$ottoq_twin_deal(v_run,'detail_time',      v_salt, v_clock, v_sim_day, 0, 'global')$anchor$),
    (1,$anchor$ottoq_twin_deal(v_run,'maintenance_time', v_visit, v_clock, v_sim_day, 0, 'global')$anchor$,$anchor$ottoq_twin_deal(v_run,'maintenance_time', v_salt, v_clock, v_sim_day, 0, 'global')$anchor$)
    ) AS t(n_expected, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'twin' AND pr.proname = 'ottoq_sim_generate_service_manifest';
    v_src := pg_get_functiondef(v_oid);
    IF v_first AND md5(v_src) <> '17f845f5c31c6aab0dcf484df5ff4541' THEN
      RAISE EXCEPTION '0055: twin.ottoq_sim_generate_service_manifest pre-image md5 % != pinned 17f845f5c31c6aab0dcf484df5ff4541', md5(v_src);
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0055: anchor occurs % times (need %): %', v_cnt, p.n_expected, left(p.old, 80);
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    v_first := false;
  END LOOP;
  RAISE NOTICE '0055 applied: twin.ottoq_sim_generate_service_manifest -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'twin' AND pr.proname = 'ottoq_sim_generate_service_manifest');
END
$do$;
