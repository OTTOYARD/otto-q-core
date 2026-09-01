-- =====================================================================
-- 0148  The verdict sorts by every field it hashes, and hears the
--       energy stream
-- =====================================================================
-- Three edits to public.ottoq_determinism_pair, one pin.
--
-- (a) h_cmd's ORDER BY omitted reason_code, which it hashes. Two
--     same-tick refusals for one vehicle that differ only in reason_code
--     tie on the sort key, so string_agg emits them in physical-scan
--     order and the hash is nondeterministic. Proven on round 5's
--     1:57 PM CT pair: the stored verdict failed on h_cmd; recomputing
--     the as-is formula later gives identical hashes on both arms; the
--     two arms' command multisets on scrubbed content are identical
--     (538 vs 538, 0 differing). The instrument failed, not the engine.
--
-- (b) h_bkg has the same latent flaw: upper(during) hashed, not sorted.
--     Zero live ties across 36 recent arms, fixed alongside.
--
-- (c) h_nrg: the energy-command stream enters the verdict. Round 4's
--     12:45 PM pair PASSED while ottoq_energy_commands differed at 20 of
--     24 rows. Same blind-spot promotion 0139 made for endst.
--
-- RULE, made explicit: a hash's ORDER BY must include every field it
-- hashes. h_dec and h_evt already comply; h_cmd and h_bkg did not.
--
-- h_nrg hashes what the orchestrator DECIDED: tick_seq, command_type,
-- source, setpoint_kw, horizon_min, issued_at (sim clock, rendered UTC),
-- reason (jsonb::text is canonical). It deliberately EXCLUDES status,
-- executed_at and executed_note - execution lifecycle that an external
-- executor could stamp with wall-clock time. It excludes command_id
-- (random uuid), sim_run_id, depot_id, data_source, created_at.
-- =====================================================================

-- 1. Pin.
DO $pin$
DECLARE v_pin text; v_n int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), count(*) OVER () INTO v_pin, v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_n <> 1 THEN RAISE EXCEPTION '0148 expected 1 arity, found %', v_n; END IF;
  IF v_pin IS DISTINCT FROM '0099c5739a41efb0c01122f9692fdf2a' THEN
    RAISE EXCEPTION '0148 pin mismatch ottoq_determinism_pair: %', v_pin;
  END IF;
END $pin$;

-- 2. Every anchor exactly once, on the raw definition AND with comments
--    stripped (a commented copy would make replace() hit twice).
DO $anchor$
DECLARE
  v_raw text; v_src text; r record; v_nr int; v_ns int;
BEGIN
  SELECT pg_get_functiondef(p.oid),
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g')
    INTO v_raw, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  FOR r IN SELECT * FROM (VALUES
     ('h_cmd order-by', $a$ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status), ''))$a$),
     ('h_bkg order-by', $a$ORDER BY lower(during), vehicle_id, stall_id, purpose, state), ''))$a$),
     ('h_bkg tail',     $a$FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run))$a$),
     ('v_equal h_bkg',  $a$AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')$a$)
  ) AS t(name, anchor) LOOP
    v_nr := (length(v_raw)-length(replace(v_raw, r.anchor, '')))/length(r.anchor);
    v_ns := (length(v_src)-length(replace(v_src, r.anchor, '')))/length(r.anchor);
    IF v_nr <> 1 OR v_ns <> 1 THEN
      RAISE EXCEPTION '0148 anchor "%" expected once, raw=% stripped=%', r.name, v_nr, v_ns;
    END IF;
  END LOOP;

  IF position('h_nrg' in v_src) <> 0 THEN
    RAISE EXCEPTION '0148 h_nrg already present - refusing to double-apply';
  END IF;
END $anchor$;

-- 3. Proofs, all falsifiable, against runs that exist in this database.
--    (i)  The 1:57 PM CT pair: stored verdict recorded h_cmd UNEQUAL;
--         the corrected formula must make its two arms EQUAL.
--    (ii) h_nrg must distinguish exactly the case it was built for:
--         EQUAL on a pair whose energy commands matched (round 5, 1:45 PM),
--         UNEQUAL on the pair that passed while they differed (round 4,
--         12:45 PM, arms cbed41d4 / 309873d4).
DO $proof$
DECLARE
  v_a uuid := '9bcff6e9-5d53-420d-84f0-617e7135a699';  -- 1:57 PM arm A
  v_b uuid := 'f40f8c51-7daa-429e-9941-70808dd79931';  -- 1:57 PM arm B
  v_bad_a uuid := 'cbed41d4-11ea-4bea-a6fb-16d322da594e'; -- round 4 12:45 PM
  v_bad_b uuid := '309873d4-7c95-4bd2-a075-199f0fa69f4e';
  v_good_a uuid; v_good_b uuid;
  v_notes jsonb; v_ha text; v_hb text; v_n int;
BEGIN
  -- (i) stored verdict says h_cmd differed
  SELECT (validation_notes::jsonb) INTO v_notes FROM ottoq_sim_runs
   WHERE run_by='cert_harness' AND (validation_notes::jsonb)->'arm_a'->>'run' = v_a::text LIMIT 1;
  IF v_notes IS NULL THEN RAISE EXCEPTION '0148 proof: 1:57 PM pair not found'; END IF;
  IF (v_notes->'arm_a'->>'h_cmd') = (v_notes->'arm_b'->>'h_cmd') THEN
    RAISE EXCEPTION '0148 proof broken: stored verdict shows h_cmd EQUAL on the 1:57 PM pair';
  END IF;
  SELECT count(*) INTO v_n FROM ottoq_vehicle_commands WHERE sim_run_id IN (v_a, v_b);
  IF v_n < 100 THEN RAISE EXCEPTION '0148 proof: too few commands (%) for the 1:57 PM arms', v_n; END IF;

  SELECT md5(COALESCE(string_agg(issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
         E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')),''))
    INTO v_ha FROM ottoq_vehicle_commands WHERE sim_run_id = v_a;
  SELECT md5(COALESCE(string_agg(issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
         E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')),''))
    INTO v_hb FROM ottoq_vehicle_commands WHERE sim_run_id = v_b;
  IF v_ha IS DISTINCT FROM v_hb THEN
    RAISE EXCEPTION '0148 proof failed: corrected h_cmd still differs on the 1:57 PM arms (% vs %)', v_ha, v_hb;
  END IF;

  -- (ii) h_nrg on the good pair (energy matched) must be EQUAL
  SELECT (validation_notes::jsonb)->'arm_a'->>'run', (validation_notes::jsonb)->'arm_b'->>'run'
    INTO v_good_a, v_good_b
    FROM ottoq_sim_runs WHERE run_by='cert_harness' AND validation_status='passed'
     AND started_at BETWEEN '2026-09-01 18:44:00+00' AND '2026-09-01 18:46:00+00'
   ORDER BY sim_run_id LIMIT 1;
  IF v_good_a IS NULL THEN RAISE EXCEPTION '0148 proof: 1:45 PM pair not found'; END IF;
  SELECT count(*) INTO v_n FROM ottoq_energy_commands WHERE sim_run_id IN (v_good_a, v_good_b, v_bad_a, v_bad_b);
  IF v_n < 90 THEN RAISE EXCEPTION '0148 proof: too few energy commands (%) for the proof pairs', v_n; END IF;

  SELECT md5(COALESCE(string_agg(COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')||'|'||COALESCE(c.reason::text,'-'),
         E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text),''))
    INTO v_ha FROM ottoq_energy_commands c WHERE c.sim_run_id = v_good_a;
  SELECT md5(COALESCE(string_agg(COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')||'|'||COALESCE(c.reason::text,'-'),
         E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text),''))
    INTO v_hb FROM ottoq_energy_commands c WHERE c.sim_run_id = v_good_b;
  IF v_ha IS DISTINCT FROM v_hb THEN
    RAISE EXCEPTION '0148 proof failed: h_nrg differs on a pair whose energy commands matched (% vs %)', v_ha, v_hb;
  END IF;

  -- h_nrg on the bad pair (energy differed 20/24) must be UNEQUAL
  SELECT md5(COALESCE(string_agg(COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')||'|'||COALESCE(c.reason::text,'-'),
         E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text),''))
    INTO v_ha FROM ottoq_energy_commands c WHERE c.sim_run_id = v_bad_a;
  SELECT md5(COALESCE(string_agg(COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')||'|'||COALESCE(c.reason::text,'-'),
         E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text),''))
    INTO v_hb FROM ottoq_energy_commands c WHERE c.sim_run_id = v_bad_b;
  IF v_ha = v_hb THEN
    RAISE EXCEPTION '0148 proof failed: h_nrg is BLIND - equal on the round-4 pair whose energy commands differed 20/24';
  END IF;
END $proof$;

-- 4. The edits.
DO $edit$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  -- (a) h_cmd sorts by reason_code too
  v_def := replace(v_def,
    $a$ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status), ''))$a$,
    $a$ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')), ''))$a$);

  -- (b) h_bkg sorts by upper(during) too
  v_def := replace(v_def,
    $a$ORDER BY lower(during), vehicle_id, stall_id, purpose, state), ''))$a$,
    $a$ORDER BY lower(during), upper(during), vehicle_id, stall_id, purpose, state), ''))$a$);

  -- (c) h_nrg after h_bkg; the closing "))" of the jsonb_build_object moves down
  v_def := replace(v_def,
    $a$FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run))$a$,
    $a$FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run),
      'h_nrg', (SELECT md5(COALESCE(string_agg(
          COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')
          ||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')
          ||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')
          ||'|'||COALESCE(c.reason::text,'-'),
          E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text), ''))
        FROM ottoq_energy_commands c WHERE c.sim_run_id = v_run))$a$);

  -- (d) h_nrg enters the verdict
  v_def := replace(v_def,
    $a$AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')$a$,
    $a$AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')
         AND (v_arms[1]->>'h_nrg') = (v_arms[2]->>'h_nrg')$a$);

  EXECUTE v_def;
END $edit$;

-- 5. Post-check.
DO $post$
DECLARE v_src text; v_pin text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_n <> 1 THEN RAISE EXCEPTION '0148 arity changed to %', v_n; END IF;

  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g'),
         md5(pg_get_functiondef(p.oid))
    INTO v_src, v_pin
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  IF v_pin = '0099c5739a41efb0c01122f9692fdf2a' THEN RAISE EXCEPTION '0148 body did not change'; END IF;

  IF position($a$status), ''))$a$ in v_src) <> 0 THEN
    RAISE EXCEPTION '0148 old h_cmd order-by survived';
  END IF;
  IF position($a$status, COALESCE(reason_code,'-')), ''))$a$ in v_src) = 0 THEN
    RAISE EXCEPTION '0148 new h_cmd order-by missing';
  END IF;
  IF position($a$ORDER BY lower(during), upper(during), vehicle_id$a$ in v_src) = 0 THEN
    RAISE EXCEPTION '0148 new h_bkg order-by missing';
  END IF;
  -- 'h_nrg' appears three times after the edit: once as the jsonb key,
  -- twice in v_equal. Count the KEY form exactly once, and the total as 3.
  v_n := (length(v_src)-length(replace(v_src,$a$'h_nrg', (SELECT$a$,'')))/length($a$'h_nrg', (SELECT$a$);
  IF v_n <> 1 THEN RAISE EXCEPTION '0148 expected the h_nrg jsonb key once, found %', v_n; END IF;
  v_n := (length(v_src)-length(replace(v_src,$a$'h_nrg'$a$,'')))/length($a$'h_nrg'$a$);
  IF v_n <> 3 THEN RAISE EXCEPTION '0148 expected ''h_nrg'' three times (key + two verdict sides), found %', v_n; END IF;
  IF position($a$(v_arms[1]->>'h_nrg') = (v_arms[2]->>'h_nrg')$a$ in v_src) = 0 THEN
    RAISE EXCEPTION '0148 h_nrg not in the verdict';
  END IF;
  IF position($a$FROM ottoq_energy_commands c WHERE c.sim_run_id = v_run$a$ in v_src) = 0 THEN
    RAISE EXCEPTION '0148 h_nrg source read missing';
  END IF;
  -- the pair function must still parse and be callable (do not run it)
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair'
     AND pg_get_function_identity_arguments(p.oid) = 'p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer';
  IF NOT FOUND THEN RAISE EXCEPTION '0148 signature changed'; END IF;

  RAISE NOTICE '0148 applied; new pin %', v_pin;
END $post$;

-- 6. Classify. Hash values change (sort order, plus a new component),
--    so every canon moves.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0148_the_verdict_sorts_by_every_field_it_hashes_and_hears_the_energy_stream', true,
        'h_cmd and h_bkg ORDER BY completed to every hashed field; h_nrg (energy command stream) added to the arm object and the verdict. Instrument change: canon moves.',
        now())
ON CONFLICT (name) DO UPDATE
   SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note, classified_at = EXCLUDED.classified_at;
