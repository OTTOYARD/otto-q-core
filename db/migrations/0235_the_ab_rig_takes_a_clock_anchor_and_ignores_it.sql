-- migration-version: 20260909015606
-- migration-name:    the_ab_rig_takes_a_clock_anchor_and_ignores_it
--
-- G39 / db/checks/0155. public.ottoq_cert_arm's signature is
--
--   (p_seed bigint, p_policy text, p_ab_group uuid, p_ticks int,
--    p_start timestamptz, p_fault_chargers int)
--
-- and the body NEVER REFERENCES p_start. Measured: "references p_start -> false".
-- It declares `v_now timestamptz := now()` instead and uses it eleven times,
-- including for sim_clock_start on the run it creates.
--
-- So two arms of the same ab_group are anchored at whatever wall-clock instant
-- each CALL happened to begin. The parameter that exists to prevent exactly this
-- is accepted and discarded.
--
-- ---------------------------------------------------------------------------
-- WHY THAT BREAKS THE PAIRING, MEASURED ON A REAL PAIR
-- ---------------------------------------------------------------------------
-- twin.ottoq_sim_advance_site_energy computes two things per tick:
--
--   v_seed := abs(hashtextextended(p_depot_id::text
--               || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now)
--               || 'site', 11));                      <- RUN-RELATIVE. Correct.
--   v_salt := to_char(p_sim_clock_now, 'YYYYMMDD-HH24MISS');   <- ABSOLUTE.
--
-- and hands BOTH to ottoq_sim_compute_building_load_kw, which draws three
-- randoms off the salt:
--
--   ottoq_sim_seeded_random(p_seed, p_salt || '_svc')
--   ottoq_sim_seeded_random(p_seed, p_salt || '_wash')
--   ottoq_sim_seeded_random(p_seed, p_salt || '_bld_n')
--
-- ottoq_sim_seeded_random is a pure hash of (seed, salt). The seed was hardened
-- to be run-relative by 0051/0052. THE SALT WAS NOT. So two arms whose absolute
-- clocks differ get a different salt at every tick, and therefore a different
-- service-bay load, wash load and noise term -- a different world.
--
-- Measured on ab_group 02310000-0000-4000-8000-000000000003, benchmark depot,
-- both arms seed 555001, both 12 ticks:
--
--   arm       sim_clock_start                  building_load_kw over 12 ticks
--   otto_q    2026-09-08 22:47:38.902697+00    min 65.50  max 130.50  avg 84.033
--   fifo      2026-09-08 22:48:10.290243+00    min 60.30  max 147.20  avg 80.875
--
-- 31.4 seconds apart, and the two arms did not experience the same building.
-- That pair is the one db/checks/0152 used, and it was described in this repo as
-- a CRN pair. It was paired on the vehicle draw -- ottoq_cert_arm seeds those
-- from hash(p_seed || p_ab_group || 'wave'), which is correct -- and unpaired on
-- energy. A claim of "same seed, same ab_group, therefore same world" is true of
-- the fleet and false of the site.
--
-- ---------------------------------------------------------------------------
-- WHY THIRTY CERTIFICATION ROUNDS NEVER SAW IT
-- ---------------------------------------------------------------------------
-- Because ottoq_determinism_pair does the right thing and ottoq_cert_arm does
-- not. The pair takes p_sim_start and hands the SAME value to both arms:
--
--   PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);
--   v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');
--
-- One anchor, two arms, identical salts, byte-identical output. The certification
-- is not affected by this and its results stand. The defect lives only on the
-- path that was never exercised until today -- which is the same sentence as
-- G35, G37 and G38, and this is the fourth time it has been the answer.
--
-- ---------------------------------------------------------------------------
-- THE CHANGE
-- ---------------------------------------------------------------------------
--   v_now timestamptz := now();
--   ->
--   v_now timestamptz := COALESCE(p_start, now());
--
-- and NOTHING ELSE on that line -- no trailing comment. The DECLARE block is a
-- single line carrying six declarations, so an appended `--` silently comments
-- out v_wseed, v_deploy_n and v_total. The first draft did exactly that and the
-- dry run refused to compile it. Recorded because the replacement looks
-- obviously safe and is not.
--
-- Callers that pass a real anchor get it honoured; callers that pass NULL keep
-- today's behaviour exactly. Nothing else in the body changes -- all eleven
-- v_now uses simply resolve to the caller's instant.
--
-- WHAT THIS DOES NOT DO. It does not make a pair correct by itself: the CALLER
-- must now pass the SAME p_start to both arms. That is a usage rule, and the
-- honest way to state it is that this migration makes a correct pairing
-- POSSIBLE, where before it was not expressible at all. db/checks/0155 carries
-- the calling convention.
--
-- It also does not fix the underlying asymmetry -- v_salt on the absolute clock
-- while v_seed is run-relative -- inside twin.ottoq_sim_advance_site_energy.
-- That function is in the tick path and is forces_recert TRUE; it is filed as
-- G39b. With a shared anchor the absolute salts agree between arms, so the
-- pairing is sound even with the asymmetry present. Fixing the salt as well
-- would additionally make a pair reproducible across DIFFERENT wall-clock days,
-- which is worth having and is not needed for a comparison.
--
-- forces_recert: FALSE. ottoq_cert_arm is a benchmark-lane procedure;
-- ottoq_determinism_pair does not call it (asserted in P2), no verdict atom
-- depends on it, and with p_start NULL the behaviour is byte-identical to today.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n; END IF;
END $P$;

DO $P1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_cert_arm(bigint,text,uuid,integer,timestamptz,integer)'::regprocedure));
  IF h <> 'dbd2e506687de8c158ff7cfc4112804d' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_cert_arm md5 is %, pinned dbd2e506687de8c158ff7cfc4112804d', h;
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- P2  The determinism pair must NOT go through this procedure. If it ever does,
--     forces_recert FALSE stops being true and the apply must stop.
-- ---------------------------------------------------------------------------
DO $P2$
BEGIN
  IF (SELECT prosrc FROM pg_proc WHERE proname='ottoq_determinism_pair') ~* 'ottoq_cert_arm\s*\(' THEN
    RAISE EXCEPTION 'P2 REFUSED: ottoq_determinism_pair now calls ottoq_cert_arm; this is no longer benchmark-lane only';
  END IF;
END $P2$;

-- ---------------------------------------------------------------------------
-- P3  p_start really is unused today. If someone already wired it up, this
--     migration is stale and must not layer a second COALESCE on top.
-- ---------------------------------------------------------------------------
DO $P3$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.ottoq_cert_arm(bigint,text,uuid,integer,timestamptz,integer)'::regprocedure);
  -- p_start appears once, in the argument list, and nowhere in the body.
  IF (length(d) - length(replace(d, 'p_start', ''))) / 7 <> 1 THEN
    RAISE EXCEPTION 'P3 REFUSED: p_start appears % times, expected exactly 1 (the signature)',
                    (length(d) - length(replace(d, 'p_start', ''))) / 7;
  END IF;
END $P3$;

DO $CHG$
DECLARE d text; a text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_cert_arm(bigint,text,uuid,integer,timestamptz,integer)'::regprocedure);
  a := 'v_now timestamptz := now()';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: anchor occurs % times, expected 1', n; END IF;

  -- NO TRAILING COMMENT. ottoq_cert_arm's DECLARE block is a SINGLE LINE --
  -- "DECLARE v_run uuid; i int; v_now timestamptz := now(); v_wseed bigint; ..."
  -- so a `-- ...` appended here comments out v_wseed, v_deploy_n and v_total and
  -- the procedure fails to compile. The dry run caught exactly that; the note
  -- lives in this file instead, where it cannot break anything.
  EXECUTE replace(d, a, 'v_now timestamptz := COALESCE(p_start, now())');
END $CHG$;

DO $A1$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.ottoq_cert_arm(bigint,text,uuid,integer,timestamptz,integer)'::regprocedure);
  IF position('COALESCE(p_start, now())' in d) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the anchor is still not honoured';
  END IF;
  -- p_start now appears twice: the signature and the COALESCE.
  IF (length(d) - length(replace(d, 'p_start', ''))) / 7 <> 2 THEN
    RAISE EXCEPTION 'A1 FAILED: p_start appears % times, expected 2',
                    (length(d) - length(replace(d, 'p_start', ''))) / 7;
  END IF;
  IF (length(d) - length(replace(d, 'v_now', ''))) / 5 <> 11 THEN
    RAISE EXCEPTION 'A1 FAILED: v_now now used % times, expected 11 -- the body changed beyond the declaration',
                    (length(d) - length(replace(d, 'v_now', ''))) / 5;
  END IF;
END $A1$;

DO $A2$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A2 FAILED: ottoq_decide_tick md5 moved: %', h;
  END IF;
END $A2$;

DO $A3$
DECLARE k "char";
BEGIN
  SELECT prokind INTO k FROM pg_proc
   WHERE oid = 'public.ottoq_cert_arm(bigint,text,uuid,integer,timestamptz,integer)'::regprocedure;
  IF k <> 'p' THEN RAISE EXCEPTION 'A3 FAILED: prokind is %, expected p (procedure)', k; END IF;
END $A3$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'the_ab_rig_takes_a_clock_anchor_and_ignores_it',
  now(),
  false,
  'G39 / db/checks/0155. ottoq_cert_arm accepts p_start timestamptz and never '
  'references it, using v_now := now() instead, so two arms of one ab_group are '
  'anchored at different wall-clock instants. twin.ottoq_sim_advance_site_energy '
  'salts its building-load randoms on to_char(p_sim_clock_now,...) -- the ABSOLUTE '
  'clock -- while its seed is correctly run-relative, so the arms sample different '
  'buildings. Measured on ab_group 02310000-...-0003: anchors 31.4 s apart, '
  'building_load_kw avg 84.033 (otto_q) vs 80.875 (fifo) over 12 ticks each. That '
  'pair was described in this repo as CRN; it was paired on the vehicle draw and '
  'unpaired on energy. Certification is unaffected -- ottoq_determinism_pair hands '
  'the SAME p_sim_start to both arms, which is why thirty rounds never saw this. '
  'Fix honours p_start when given and falls back to now() when NULL, so behaviour '
  'is byte-identical for existing callers. Does not by itself make a pair correct: '
  'the caller must pass the same p_start to both arms (convention in 0155). Does '
  'not fix the v_salt asymmetry inside advance_site_energy, which is tick-path and '
  'forces_recert TRUE, filed as G39b.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 20:56 CT (2026-09-09 01:56 UTC). Four preconditions, three
-- assertions, first attempt. decide_tick md5 UNCHANGED. Floor unmoved at
-- 2026-09-07 21:36:53.363037.
--
-- *** PROVEN, and the test is worth reading because it isolates the variable. ***
--
-- Two arms, SAME seed (919191), SAME explicit anchor
-- ('2026-09-09 02:00:00+00'), BOTH otto_q -- so the policy is held constant and
-- the only thing under test is the clock:
--
--   64a1b741-0db4-4205-8015-5b8172f74404   sim_clock_start 2026-09-09 02:00:00+00
--   (second arm, ab_group ...0002)         sim_clock_start 2026-09-09 02:00:00+00
--
--   distinct_anchors   1
--   arm1_rows         12      arm2_rows        12
--   matching_ticks    12      differing_ticks   0
--
-- Building load is now identical TICK FOR TICK across two separate runs. The
-- comparison before the fix, on arms 31.4 s apart, differed at every tick
-- (avg 84.033 vs 80.875 kW). Same seed, same world, on demand.
--
-- Note what the anchor being honoured also proves incidentally: sim_clock_start
-- came back as exactly 02:00:00, a time that is neither now() nor anywhere near
-- it, so p_start is genuinely reaching the INSERT rather than being shadowed.
--
-- WHY BOTH ARMS ARE otto_q. A fifo arm still cannot complete -- it dies on G38
-- (db/checks/0154) -- and running one otto_q against one fifo would have
-- confounded the clock fix with the policy difference. Holding the policy
-- constant makes the 12/12 result attributable to this migration and nothing
-- else. The policy comparison itself still waits on G38.
-- ---------------------------------------------------------------------------
