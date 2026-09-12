-- migration-version: PENDING
-- migration-name: 0254_the_world_hash_moved_and_could_not_say_where
-- ===========================================================================
-- 0254  THE WORLD HASH MOVED AND COULD NOT SAY WHERE
-- ===========================================================================
-- probe:          db/checks/0169
-- forces_recert:  FALSE  (argued and asserted below, not assumed)
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only
-- authority: ottoq_sim_runs cannot see an in-flight pair (both arms are one
-- uncommitted transaction) and cron.job_run_details reports one as succeeded in
-- about a second.
--
-- WHY THIS EXISTS
--
-- The two 48-tick pairs of 2026-09-09 (15:45 and 16:10 UTC) agreed on thirteen of
-- fourteen atoms and disagreed on `endst` -- and inside endst, on exactly one of
-- seven sub-keys: `world`. Same boot fingerprint, same sim_start, byte-identical
-- command / decision / event / booking / energy / proposal / deferral / rule /
-- recall / SDR streams. Identical start, identical decisions, different final
-- world.
--
-- And the verdict could say nothing more than that, because
-- ottoq.ottoq_world_fingerprint returns ONE md5 over five concatenated sections:
--
--     vehicles # stalls # chargers # vehicle_need_profile # bess
--
-- A single hash over five independent subsystems is a blind spot of exactly the
-- kind CLAUDE.md 2.9a describes: it can prove a difference exists and can never
-- locate it. Re-running the column with this hash would cost ~80 minutes and
-- return the same uninformative answer, and the two end states that WOULD have
-- answered it are gone -- vehicles, stalls and ottoq_bess_units hold CURRENT
-- state, not per-run history, so there is nothing left to diff.
--
-- THEREFORE THE INSTRUMENT COMES BEFORE THE EXPERIMENT. That is db/checks/0167's
-- lesson applied forward instead of in hindsight: there, two instruments were
-- wrong before any finding they produced was worth reading.
--
-- WHY NOT SIMPLY SPLIT ottoq_world_fingerprint ITSELF
--
-- Because its OUTPUT VALUE is load-bearing. It is `fp` in every verdict and
-- `endst.world` in every canon. Any edit that perturbed the bytes -- even a
-- refactor into five sections recombined -- would move fp on all nine columns and
-- force a full recert, resetting every streak. So the original is left BYTE-
-- IDENTICAL and untouched, and the sections function is additive.
--
-- That leaves one real hazard: two copies of the same five expressions can drift
-- apart, and a diagnostic that disagrees with the thing it diagnoses is worse than
-- none. A1 closes it by construction -- the sections function also returns
-- `combined`, the five section TEXTS recombined exactly as the original
-- concatenates them, and A1 asserts combined = ottoq_world_fingerprint(depot) on
-- two real depots of different shape. If a single character of a single expression
-- is mistyped, combined diverges and this migration refuses to apply. The
-- self-check is what makes transcribing the expressions safe.
--
-- WHY forces_recert = FALSE, ARGUED
--
-- ottoq_world_fingerprint is not modified (A2 pins its body digest). `wsec` is
-- added to each arm's object but NOT to the verdict: v_equal is an explicit
-- fourteen-term AND chain, read from the live body rather than assumed, and A4
-- asserts all fourteen terms survive and that `wsec` appears nowhere in it. So no
-- enforced atom changes, no hash value changes, and no pair that passes today
-- could fail tomorrow. MEASURED first, per the blind-spot promotion doctrine --
-- the same sequence 0139 used for endst, 0203/0205 for h_rule and 0206/0217 for
-- h_rcl. Promotion to ENFORCED is a later migration and needs a flagship round
-- showing the arms agree on it.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The same five sections, hashed separately, plus the proof they are the same.
--
--    Each section expression is transcribed from ottoq.ottoq_world_fingerprint.
--    Do not "improve" one here: the only thing keeping the two honest is that
--    `combined` reproduces the original byte for byte, and A1 checks it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ottoq.ottoq_world_fingerprint_sections(p_depot uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
  WITH w AS (
    SELECT
      COALESCE((SELECT string_agg(v.id::text||'|'||COALESCE(v.current_soc::text,'-')||'|'
                       ||v.current_state::text||'|'||COALESCE(v.current_stall_id::text,'-')||'|'
                       ||COALESCE(v.current_soc_source,'-')||'|'||COALESCE(v.target_soc::text,'-')||'|'
                       ||COALESCE(public.ottoq_scrub_ids((v.config - 'condition_drawn_run')::text),'{}')||'|'||COALESCE(v.last_state_change::text,'-')||'|'||COALESCE(v.robotic_tether_phase::text,'-')||'|'||COALESCE(v.robotic_tether_until::text,'-')||'|'||COALESCE(v.robotic_tether_stall_id::text,'-')||'|'||COALESCE(v.robotic_tether_direction::text,'-')||'|'||COALESCE(v.current_depot_id::text,'-'),
                       E'\n' ORDER BY v.id)
                  FROM public.vehicles v
                 WHERE v.home_depot_id = p_depot AND v.category='autonomous'), '') AS t_veh,
      COALESCE((SELECT string_agg(s.id::text||'|'||s.status||'|'
                       ||COALESCE(s.current_vehicle_id::text,'-')||'|'||COALESCE(s.reserved_by::text,'-')||'|'
                       ||COALESCE(s.reserved_at::text,'-')||'|'||COALESCE(s.reservation_expires_at::text,'-'),
                       E'\n' ORDER BY s.id)
                  FROM public.stalls s WHERE s.depot_id = p_depot), '') AS t_stall,
      COALESCE((SELECT string_agg(c.charger_id::text||'|'||COALESCE(c.station_state,'-')||'|'
                       ||COALESCE(c.last_fault_code,'-'), E'\n' ORDER BY c.charger_id)
                  FROM public.ottoq_ocpp_chargers c
                  JOIN public.stalls s ON s.ocpp_charger_id = c.charger_id
                 WHERE s.depot_id = p_depot), '') AS t_chg,
      COALESCE((SELECT string_agg(np.vehicle_id::text||'|'||
                   (to_jsonb(np) - 'drawn_at' - 'updated_at' - 'drawn_for_run' - 'wear_km_applied_run')::text,
                   E'\n' ORDER BY np.vehicle_id)
                  FROM public.vehicle_need_profile np
                  JOIN public.vehicles v2 ON v2.id = np.vehicle_id
                 WHERE v2.home_depot_id = p_depot AND v2.category='autonomous'), '') AS t_np,
      COALESCE((SELECT string_agg(b.bess_id::text||'|'||COALESCE(b.current_power_kw::text,'-')||'|'
                       ||COALESCE(b.current_soc_pct::text,'-')||'|'||COALESCE(b.current_soc_kwh::text,'-')||'|'
                       ||COALESCE(b.current_state,'-')||'|'
                       ||COALESCE(b.current_temperature_c::text,'-')||'|'
                       ||COALESCE(b.current_soh_pct::text,'-')||'|'
                       ||COALESCE(b.current_cycle_count::text,'-')||'|'
                       ||COALESCE(b.lifetime_kwh_charged::text,'-')||'|'
                       ||COALESCE(b.lifetime_kwh_discharged::text,'-'), chr(10) ORDER BY b.bess_id)
                  FROM public.ottoq_bess_units b WHERE b.depot_id = p_depot), '') AS t_bess
  )
  SELECT jsonb_build_object(
    'vehicles',     md5(w.t_veh),
    'stalls',       md5(w.t_stall),
    'chargers',     md5(w.t_chg),
    'need_profile', md5(w.t_np),
    'bess',         md5(w.t_bess),
    -- Row counts alongside the hashes: "a row appeared" and "a value changed" are
    -- different diagnoses and the hash cannot tell them apart.
    'n', jsonb_build_object(
      'vehicles',     (SELECT count(*) FROM public.vehicles v
                        WHERE v.home_depot_id = p_depot AND v.category='autonomous'),
      'stalls',       (SELECT count(*) FROM public.stalls st WHERE st.depot_id = p_depot),
      'chargers',     (SELECT count(*) FROM public.ottoq_ocpp_chargers c
                        JOIN public.stalls st ON st.ocpp_charger_id = c.charger_id
                       WHERE st.depot_id = p_depot),
      'need_profile', (SELECT count(*) FROM public.vehicle_need_profile np
                        JOIN public.vehicles v2 ON v2.id = np.vehicle_id
                       WHERE v2.home_depot_id = p_depot AND v2.category='autonomous'),
      'bess',         (SELECT count(*) FROM public.ottoq_bess_units b WHERE b.depot_id = p_depot)),
    -- THE SELF-CHECK. Must equal ottoq.ottoq_world_fingerprint(p_depot) exactly.
    'combined', md5(w.t_veh || '#' || w.t_stall || '#' || w.t_chg || '#' || w.t_np || '#' || w.t_bess)
  ) FROM w;
$function$;

COMMENT ON FUNCTION ottoq.ottoq_world_fingerprint_sections(uuid) IS
  '0254: ottoq_world_fingerprint split into its five sections -- vehicles, stalls, '
  'chargers, need_profile, bess -- each hashed separately, with row counts and a '
  '`combined` hash that MUST equal ottoq_world_fingerprint(p_depot). Exists because '
  'the 48-tick column failed 0193''s bar on endst.world (db/checks/0169) and a single '
  'md5 over five subsystems can prove a difference without locating it. The original '
  'is deliberately left byte-identical -- its value is fp in every verdict -- so this '
  'is additive, and `combined` is what keeps the two from drifting apart. Diagnostic: '
  'carried in the pair verdict as `wsec`, MEASURED, not part of v_equal.';

-- ---------------------------------------------------------------------------
-- 2. Carry it in the verdict, MEASURED. Anchored substitution; the anchor's
--    uniqueness is asserted before the replacement, not hoped for.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
  d  text;
  a  text := E'      ''endst'', public.ottoq_boot_state_fingerprint(p_depot, v_run),\n';
  nd text;
  k  int;
BEGIN
  d := pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure);

  k := (length(d) - length(replace(d, a, ''))) / length(a);
  IF k <> 1 THEN
    RAISE EXCEPTION 'P1 FAILED: the endst anchor occurs % time(s), expected exactly 1', k;
  END IF;

  IF position('wsec' in d) > 0 THEN
    RAISE EXCEPTION 'P2 FAILED: wsec is already present; this migration is not idempotent by design';
  END IF;

  nd := replace(d, a,
    a || E'      ''wsec'', ottoq.ottoq_world_fingerprint_sections(p_depot),   -- 0254: MEASURED, not in v_equal\n');
  EXECUTE nd;
END
$mig$;

-- ---------------------------------------------------------------------------
-- 3. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_src   text;
  v_eq    text;
  v_sec   jsonb;
  v_mono  text;
  v_depot uuid;
  v_n     int;
  v_atoms text[] := ARRAY['fp','h_cmd','h_dec','h_evt','h_bkg','h_nrg','h_prop',
                          'h_defr','h_cal','h_rule','h_rcl','h_sdr','ticks','endst'];
  v_atom  text;
BEGIN
  -- A1. THE ASSERTION THAT MAKES THE TRANSCRIPTION SAFE. On two depots of
  --     different shape: the recombined sections equal the untouched original.
  FOREACH v_depot IN ARRAY ARRAY['11111111-1111-1111-1111-111111111111'::uuid,
                                 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid]
  LOOP
    v_sec  := ottoq.ottoq_world_fingerprint_sections(v_depot);
    v_mono := ottoq.ottoq_world_fingerprint(v_depot);
    IF (v_sec->>'combined') IS DISTINCT FROM v_mono THEN
      RAISE EXCEPTION 'A1 FAILED on depot %: sections recombine to % but the original is %. '
                      'One of the five expressions was transcribed wrongly.',
                      v_depot, v_sec->>'combined', v_mono;
    END IF;
    RAISE NOTICE 'A1 ok depot %: combined = % (vehicles=%, stalls=%, chargers=%, need_profile=%, bess=%)',
                 left(v_depot::text,8), left(v_mono,12),
                 v_sec->'n'->>'vehicles', v_sec->'n'->>'stalls', v_sec->'n'->>'chargers',
                 v_sec->'n'->>'need_profile', v_sec->'n'->>'bess';
  END LOOP;

  -- A2. The original is UNTOUCHED, pinned by digest. Its value is fp on nine
  --     columns and endst.world in every canon; if this migration moved a byte of
  --     it, every canon would be invalidated and forces_recert=FALSE would be a
  --     lie. The digest below was MEASURED from the live catalog immediately
  --     before applying (945fa4b9..., 3906 chars, 4 separators = 5 sections), not
  --     guessed -- a pin that cannot match is a comment wearing a check's clothes.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  IF md5(v_src) <> '945fa4b9e7bfd0d1c027fd92dc85fa06' THEN
    RAISE EXCEPTION 'A2 FAILED: ottoq_world_fingerprint body is % (% chars), expected '
                    '945fa4b9e7bfd0d1c027fd92dc85fa06. Either this migration moved it, or it '
                    'changed under me -- in which case A1''s transcription is against the wrong '
                    'source and the sections are not the sections.', md5(v_src), length(v_src);
  END IF;
  IF position('ottoq_world_fingerprint_sections' in v_src) > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: the original now calls the sections function; its bytes have moved';
  END IF;
  IF (length(v_src) - length(replace(v_src, '''#''', ''))) / 3 <> 4 THEN
    RAISE EXCEPTION 'A2 FAILED: the original no longer concatenates exactly five sections';
  END IF;

  -- A3. wsec is actually carried, exactly once, in the arm builder.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  v_n := (length(v_src) - length(replace(v_src, 'wsec', ''))) / 4;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A3 FAILED: wsec appears % time(s) in the pair, expected exactly 1', v_n;
  END IF;

  -- A4. MEASURED, NOT ENFORCED, and proven from the body rather than intended.
  --     v_eq is the text of the v_equal assignment; all fourteen atoms must still
  --     be compared in it and wsec must not appear.
  v_eq := substring(v_src from position('v_equal :=' in v_src)
                    for position('v_complete :=' in v_src) - position('v_equal :=' in v_src));
  IF v_eq IS NULL OR length(v_eq) < 200 THEN
    RAISE EXCEPTION 'A4 FAILED: could not isolate the v_equal assignment (got % chars)',
                    COALESCE(length(v_eq), 0);
  END IF;
  IF position('wsec' in v_eq) > 0 THEN
    RAISE EXCEPTION 'A4 FAILED: wsec entered the equality verdict; it must be MEASURED only';
  END IF;
  FOREACH v_atom IN ARRAY v_atoms LOOP
    IF position('''' || v_atom || '''' in v_eq) = 0 THEN
      RAISE EXCEPTION 'A4 FAILED: enforced atom % is no longer compared by v_equal', v_atom;
    END IF;
  END LOOP;

  -- A5. The sections payload has exactly the shape a later promotion will rely on.
  v_sec := ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111'::uuid);
  SELECT count(*) INTO v_n FROM jsonb_object_keys(v_sec) k
   WHERE k IN ('vehicles','stalls','chargers','need_profile','bess','n','combined');
  IF v_n <> 7 THEN
    RAISE EXCEPTION 'A5 FAILED: sections payload has % of 7 expected keys', v_n;
  END IF;

  RAISE NOTICE 'A1-A5 PASSED: sections recombine to the untouched original on two depots, '
               'wsec is carried once, and all fourteen enforced atoms still decide the verdict';
END $$;

-- ===========================================================================
-- WHAT THIS DOES NOT DO
--
-- It does not find the 48-tick divergence. It makes the NEXT occurrence name its
-- own section and say whether a row count moved with it. The experiment is two
-- fresh 48t pairs, and until they run busy_day/171717/48t remains uncertified and
-- the flagship matrix remains SIX of seven.
--
-- It also does not promote wsec to ENFORCED. Three of the five sections hold state
-- that is legitimately shared across runs at a depot -- BESS lifetime counters
-- most obviously -- so enforcing it before a flagship round shows the arms agree
-- would be exactly the mistake the blind-spot doctrine forbids.
--
-- COST: one extra pass over five small depot-scoped tables per arm (226 vehicles
-- and 330 stalls at flagship). Measured against the ~9.4 billion heap blocks
-- ottoq_stall_bookings alone has served (db/checks/0163), this is noise.
-- ===========================================================================
