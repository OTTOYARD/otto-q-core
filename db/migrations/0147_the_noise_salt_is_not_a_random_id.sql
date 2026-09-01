-- =====================================================================
-- 0147  The noise salt is not a random id
-- =====================================================================
-- 0146 run- and depot-scoped the site-load sum. Round 4 then showed the
-- arms STILL disagree: on the 12:45 PM CT pair, desired_ev_kw differed
-- at 20 of 24 rows, net_load at 10, setpoints at 14, max delta 16 kW.
-- 0146 was necessary and insufficient.
--
-- THE RESIDUAL CARRIER. ocpp_sessions.id defaults to uuid_generate_v4().
-- Pairing the two arms of that pair on (vehicle_id, stall_id):
--
--   paired sessions        85
--   same session id         0
--   DIFFERENT session id   85
--   same started_at        85
--
-- Logically identical sessions — same vehicle, same stall, same start —
-- carrying different random identifiers. Two seeded draws are keyed on
-- that identifier, so the two arms draw different noise for the same
-- session:
--
--   ottoq_energy_orchestrate
--     'btemp:'||s.id::text        -> battery temp, up to 8 degC swing
--     s.id::text||':'||p_sim_clock -> charge-rate noise salt
--   ottoq_forecast_net_load
--     s.id::text                   -> charge-rate noise salt
--
-- A seeded RNG salted with a random value is not seeded. The seed
-- promise is that the same scenario replays identically; a v4 uuid in
-- the salt breaks that at the source.
--
-- SWEEP. Every salt site in public/ottoq/twin was enumerated. Exactly
-- these two functions salt with a random id. Every twin function uses a
-- deterministic salt, and the house pattern for this very draw is:
--
--   twin.ottoq_sim_advance_charge_sessions
--     p_noise_salt := v_session.vehicle_id::text || ':' || clock_salt...
--   twin.ottoq_sim_start_charge_session
--     p_noise_salt := p_vehicle_id::text || ':' || clock_salt...
--
-- so the two public energy functions are the deviation, not the rule.
-- This fix adopts the house key: vehicle_id, which is a fixed fleet row
-- identical in both arms, and unique among concurrently active sessions
-- because a vehicle occupies at most one stall at a time.
--
-- Deliberately NOT widened: the twin also wraps its clock in
-- ottoq_sim_clock_salt(). Raw p_sim_clock is already deterministic, so
-- changing it would be churn. Only the random component is replaced.
--
-- forecast_net_load never had the 0146 defect — its query already reads
-- WHERE s.sim_run_id = p_sim_run_id. It had only this one.
-- =====================================================================

-- 1. Pin both bodies.
DO $pin$
DECLARE v_a text; v_b text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_a FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_energy_orchestrate';
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_b FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_forecast_net_load';
  IF v_a IS DISTINCT FROM 'a1f7cab5b343b7afdb24b080d9599f21' THEN
    RAISE EXCEPTION '0147 pin mismatch ottoq_energy_orchestrate: %', v_a;
  END IF;
  IF v_b IS DISTINCT FROM '3ca05c53c17db6139f7d543a8a7624d7' THEN
    RAISE EXCEPTION '0147 pin mismatch ottoq_forecast_net_load: %', v_b;
  END IF;
END $pin$;

-- 2. One arity each; exactly 2 and 1 salt sites, comments stripped first.
DO $anchor$
DECLARE r record; v_n int; v_expect int;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('ottoq_energy_orchestrate',2),
                                 ('ottoq_forecast_net_load',1)) AS t(fname,want)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.fname;
    IF v_n <> 1 THEN RAISE EXCEPTION '0147 %: expected 1 arity, found %', r.fname, v_n; END IF;

    SELECT (length(src)-length(replace(src,'s.id::text','')))/length('s.id::text')
      INTO v_n
      FROM (SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g') AS src
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname=r.fname) q;
    v_expect := r.want;
    IF v_n <> v_expect THEN
      RAISE EXCEPTION '0147 %: expected % salt sites, found %', r.fname, v_expect, v_n;
    END IF;
  END LOOP;
END $anchor$;

-- 3. Prove the substitution changes determinism, not just text.
--    Same seed, two different session uuids -> two different draws;
--    same seed, the same vehicle id twice -> one draw. This CAN fail:
--    if the salt were ignored, both branches would be equal.
DO $proof$
DECLARE
  v_seed bigint := 171717;
  v_id_a uuid := uuid_generate_v4();
  v_id_b uuid := uuid_generate_v4();
  v_veh  uuid := '00000000-0000-0000-0000-0000000000aa';
BEGIN
  IF twin.ottoq_sim_seeded_random(v_seed,'btemp:'||v_id_a::text)
   = twin.ottoq_sim_seeded_random(v_seed,'btemp:'||v_id_b::text) THEN
    RAISE EXCEPTION '0147 proof broken: two random uuids gave the same draw';
  END IF;
  IF twin.ottoq_sim_seeded_random(v_seed,'btemp:'||v_veh::text)
  IS DISTINCT FROM twin.ottoq_sim_seeded_random(v_seed,'btemp:'||v_veh::text) THEN
    RAISE EXCEPTION '0147 proof broken: the same vehicle id gave two draws';
  END IF;
END $proof$;

-- 4. The edit: s.id -> s.vehicle_id at every salt site in both functions.
DO $edit$
DECLARE r record; v_def text; v_new text;
BEGIN
  FOR r IN SELECT unnest(ARRAY['ottoq_energy_orchestrate','ottoq_forecast_net_load']) AS fname
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.fname;
    IF position('s.id::text' in v_def) = 0 THEN
      RAISE EXCEPTION '0147 %: salt site absent from functiondef', r.fname;
    END IF;
    v_new := replace(v_def, 's.id::text', 's.vehicle_id::text');
    EXECUTE v_new;
  END LOOP;
END $edit$;

-- 5. Post-check: no random-id salt survives, both bodies moved,
--    arities unchanged, and the run/depot predicates 0146 added are
--    still intact in energy_orchestrate.
DO $post$
DECLARE r record; v_src text; v_pin text; v_n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('ottoq_energy_orchestrate','a1f7cab5b343b7afdb24b080d9599f21',2),
                                 ('ottoq_forecast_net_load','3ca05c53c17db6139f7d543a8a7624d7',1))
                        AS t(fname,oldpin,want)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.fname;
    IF v_n <> 1 THEN RAISE EXCEPTION '0147 %: arity changed to %', r.fname, v_n; END IF;

    SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g'),
           md5(pg_get_functiondef(p.oid))
      INTO v_src, v_pin
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.fname;

    IF v_pin = r.oldpin THEN
      RAISE EXCEPTION '0147 %: body did not change', r.fname;
    END IF;
    IF position('s.id::text' in v_src) <> 0 THEN
      RAISE EXCEPTION '0147 %: a random-id salt survived', r.fname;
    END IF;
    v_n := (length(v_src)-length(replace(v_src,'s.vehicle_id::text','')))/length('s.vehicle_id::text');
    IF v_n < r.want THEN
      RAISE EXCEPTION '0147 %: expected >= % vehicle-id salts, found %', r.fname, r.want, v_n;
    END IF;
  END LOOP;

  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_energy_orchestrate';
  IF position('AND st.depot_id = p_depot_id;' in v_src) = 0
  OR position('= COALESCE(p_sim_run_id,' in v_src) = 0 THEN
    RAISE EXCEPTION '0147 clobbered the 0146 run/depot predicates';
  END IF;
END $post$;

-- 6. Every migration classifies itself (0142).
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0147_the_noise_salt_is_not_a_random_id', true,
        'Replaces random session-uuid noise salts with vehicle_id in ottoq_energy_orchestrate and ottoq_forecast_net_load. Changes charge-rate and battery-temp draws, so every canon moves.',
        now())
ON CONFLICT (name) DO UPDATE
   SET forces_recert = EXCLUDED.forces_recert,
       note          = EXCLUDED.note,
       classified_at = EXCLUDED.classified_at;
