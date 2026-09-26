-- migration-version: 20260926112312
-- migration-name:    the_deploy_gates_technician_flag_was_never_cleared_and_took_service_bay_seats_in_later_runs
--
-- 0475  **The deploy gate's technician flag was never cleared, so it outlived the run that raised it and took
--       service-bay seats in the runs after.** `db/checks/0360`. FINDINGS G208.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run 49c45bd4 (busy_day, twin depot `11111111-…`), from its signed event stream after the stop: 44 of
--   the 116 cars entered the run already carrying `flagged_issue: true` with `flagged_issue_type: deploy_gate_stuck`,
--   raised by earlier runs; the seed then stripped the type and kept the flag. Two more were flagged during the run,
--   and 49 of the twin depot's cars carry the flag now. The service bay (2 stalls, the depot's scarcest) seated 10
--   cars; 7 were flagged, and all 7 flags were carried in, none raised on the run. Four of the seven credited nothing:
--   Waymo-AV-012 (44 min), Waymo-AV-040 (44 min, both seated 3 sim-minutes into the run), Tesla-AV-047 (52 min) and
--   Waymo-AV-037 (38 min), 178 of the 393 seat-minutes the bay gave.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The only writer of `flagged_issue: true` is the deploy gate's patience escalation in
--   `twin.ottoq_sim_advance_service_flow`: a car held 45 sim-minutes is flagged `deploy_gate_stuck` "so a technician
--   sees it". Its readers send a flagged car to the service bay: a wash or detail exit hands it `need_service` on the
--   flag alone, and 0468's need-gate keeps a flagged `need_service` car for its technician seat. Nothing clears the
--   flag. The service-bay exit leaves it; `twin.ottoq_sim_seed_fleet` strips `flagged_issue_type` at the start of an
--   operator run and keeps `flagged_issue`; only the certification reset (`ottoq_tick_invariance_reset_fleet`, a
--   whitelist) drops it, so certification arms start clean and operator runs start with every flag ever raised.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (A) The service-bay exit clears `flagged_issue` and `flagged_issue_type`: the technician seat is what the flag
--       asked for. If the car is stuck again, the gate raises it again after its patience. The exit's
--       `twin.service_completed` event names the flag it cleared (`flag_cleared`, null when there was none), so a seat
--       that credited no atom but served a flag is distinguishable from one that did nothing.
--   (B) Both overloads of `twin.ottoq_sim_seed_fleet` strip `flagged_issue` with `flagged_issue_type`, as the
--       certification reset already does: a flag belongs to the run that raised it, like the gate's own hold stamp
--       (0447). The 49 flags standing now clear at the next operator run's seed.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Tick path: a flagged car's exit from the service bay, and so its later routing, moves. The canon's arms start
--   unflagged (the reset's whitelist), so (B) cannot move them; (A) can, wherever an arm's gate flags a car that later
--   reaches the service bay.
--
--   PREDICTED on the next busy_day run: no car enters the run flagged; every flagged service-bay seat was flagged on
--   that run; each service-bay exit of a flagged car carries `flag_cleared` and leaves the car unflagged.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0475 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure))
     <> '66bac16b04402b97a28ef08bf970ed52' THEN
    RAISE EXCEPTION '0475 P2: twin.ottoq_sim_advance_service_flow is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint)'::regprocedure)) <> '602327d05acf7aa331a846dacd972c12'
     OR md5(pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure)) <> '46fc673bf3c7919901c23bb2f36268ee' THEN
    RAISE EXCEPTION '0475 P2: twin.ottoq_sim_seed_fleet is not the pair of bodies this file patches';
  END IF;
  -- the deploy gate is the flag's only writer, so clearing it at the seed erases nothing another path meant to carry
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname NOT IN ('pg_catalog','information_schema')
         AND p.prosrc ~ $x$'flagged_issue',\s*true$x$) <> 1
     OR position($x$'flagged_issue', true$x$ IN pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0475 P2: something other than the deploy gate raises flagged_issue';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0475_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
                 'twin.ottoq_sim_seed_fleet(uuid,bigint)'::regprocedure,
                 'twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);

-- ── (A) the service-bay exit clears the flag, and its event names the flag it cleared ──
DO $patch_exit$
DECLARE
  v_def  text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  v_pat1 text := $p$to_jsonb\('need_deploy'::text\)\), '\{service_ends_at\}', 'null'::jsonb\) - 'service_done' - 'awaiting_external_completion' - 'bay_need'\s+WHERE id = v_rec\.id;$p$;
  v_new1 text := $r$to_jsonb('need_deploy'::text)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion' - 'bay_need'
                    -- 0475 (G208): the technician seat is what the flag asked for, and the gate raises it again if the car is stuck again
                    - 'flagged_issue' - 'flagged_issue_type'
       WHERE id = v_rec.id;$r$;
  v_pat2 text := $p$'suppressed_n', COALESCE\(array_length\(v_bay_caps,1\),0\) - COALESCE\(array_length\(v_credit,1\),0\)\),$p$;
  v_new2 text := $r$'suppressed_n', COALESCE(array_length(v_bay_caps,1),0) - COALESCE(array_length(v_credit,1),0),
        -- 0475 (G208): the technician flag this service-bay seat cleared, if any
        'flag_cleared', CASE WHEN v_rec.current_state = 'in_service_bay' AND COALESCE((v_rec.config->>'flagged_issue')::boolean, false)
                             THEN COALESCE(v_rec.config->>'flagged_issue_type', 'untyped') END),$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat1, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0475: the service-bay exit matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat2, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0475: the service-completed payload matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat1, v_new1);
  v_def := regexp_replace(v_def, v_pat2, v_new2);
  EXECUTE v_def;
END $patch_exit$;

-- ── (B) the seed strips the flag with its type ──
DO $patch_seed$
DECLARE
  v_sig  regprocedure;
  v_def  text;
  v_pat  text := $p$- 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item'$p$;
  v_new  text := $r$- 'service_ends_at' - 'flagged_issue' - 'flagged_issue_type' - 'exception' - 'draining_item'$r$;
  n int;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY['twin.ottoq_sim_seed_fleet(uuid,bigint)'::regprocedure,
                               'twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure] LOOP
    v_def := pg_get_functiondef(v_sig);
    SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
    IF n <> 2 THEN RAISE EXCEPTION '0475: % strips the flag type % times, not twice', v_sig, n; END IF;
    v_def := replace(v_def, v_pat, v_new);
    EXECUTE v_def;
  END LOOP;
END $patch_seed$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_s  text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  v_f1 text := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint)'::regprocedure);
  v_f2 text := pg_get_functiondef('twin.ottoq_sim_seed_fleet(uuid,bigint,integer)'::regprocedure);
BEGIN
  -- V1: the service-bay exit strips the flag, the wash and detail exit does not, and the event names the flag.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$- 'bay_need'\s+-- 0475 \(G208\)[^\n]*\n\s+- 'flagged_issue' - 'flagged_issue_type'\s+WHERE id = v_rec\.id;$x$, 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_s, $x$- 'flagged_issue' - 'flagged_issue_type'$x$, 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_s, $x$'flag_cleared', CASE WHEN v_rec\.current_state = 'in_service_bay'$x$, 'g')) <> 1 THEN
    RAISE EXCEPTION '0475 V1: the service flow is not the body this file writes';
  END IF;
  -- V2: each seed strips the flag with its type, twice, and never the type alone.
  IF (SELECT count(*) FROM regexp_matches(v_f1, $x$- 'flagged_issue' - 'flagged_issue_type'$x$, 'g')) <> 2
     OR (SELECT count(*) FROM regexp_matches(v_f2, $x$- 'flagged_issue' - 'flagged_issue_type'$x$, 'g')) <> 2
     OR (SELECT count(*) FROM regexp_matches(v_f1 || v_f2, $x$- 'service_ends_at' - 'flagged_issue_type'$x$, 'g')) <> 0 THEN
    RAISE EXCEPTION '0475 V2: the seed is not the body this file writes';
  END IF;
  -- V3: no overload appeared; the ACLs are unchanged (postgres and service_role only).
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow') <> 1
     OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_seed_fleet') <> 2 THEN
    RAISE EXCEPTION '0475 V3: an overload appeared';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
                                        'twin.ottoq_sim_seed_fleet(uuid,bigint)',
                                        'twin.ottoq_sim_seed_fleet(uuid,bigint,integer)']) f
              WHERE has_function_privilege('anon', f, 'EXECUTE')
                 OR has_function_privilege('authenticated', f, 'EXECUTE')
                 OR NOT has_function_privilege('service_role', f, 'EXECUTE')) THEN
    RAISE EXCEPTION '0475 V3: an ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the three functions from ottoq_schema_snapshots label '0475_pre' (CREATE OR REPLACE; ACLs kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0475_the_deploy_gates_technician_flag_was_never_cleared_and_took_service_bay_seats_in_later_runs', true,
  'Tick path: the service-bay exit in twin.ottoq_sim_advance_service_flow clears flagged_issue and names it on '
  'twin.service_completed; twin.ottoq_sim_seed_fleet strips flagged_issue with its type. Flagged cars'' routing moves.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
