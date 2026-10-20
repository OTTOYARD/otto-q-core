-- tests/fixtures/proposal_ttl_stub.sql: the world db/migrations/0756 runs in, for tests/test_proposal_ttl_stamp_clock_sql.py.
--
-- The disposer, public.ottoq_dispose_external_proposals, and the two readers that keep a pending proposal,
-- public.ottoq_l2_external_proposal and public.ottoq_cuopt_defer_hold, verbatim from live (pg_get_functiondef, read
-- 2026-10-18 between 3:50 and 4:01 AM CT; definition md5s 5ed4b746, d2279c16 and 9223813d; prosrc md5s 13b31d98, 97764998
-- and f6146663). The tables carry the columns those three and 0756 read, ottoq_external_proposals all of its live ones.
-- Two things are not live, on purpose: ottoq_promote_proposal_candidates promotes nothing (the disposer calls it inside a
-- handler that swallows its errors, and it only rewrites stall_assignment proposals, which no test here makes), and
-- ottoq_cuopt_defer_hold is created with function bodies unchecked and is never called (0756's P1 pins it; its tables
-- are not here).

CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS extensions;

CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_seq bigserial,
  scenario_id uuid NOT NULL,
  scenario_code text NOT NULL,
  depot_id uuid,
  status text NOT NULL DEFAULT 'initializing',
  started_at timestamptz NOT NULL DEFAULT now(),
  sim_clock_start timestamptz NOT NULL,
  sim_clock_current timestamptz NOT NULL,
  sim_clock_end timestamptz NOT NULL,
  random_seed bigint NOT NULL DEFAULT 42,
  run_by text,
  policy text NOT NULL DEFAULT 'otto_q');

CREATE TABLE public.ottoq_external_proposals (
  proposal_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id),
  depot_id uuid, action_context text, entity_type text, entity_id uuid, proposal jsonb, source text,
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz, declared_source text, submitted_by_role text, submitted_by uuid, tick_seq integer,
  disposition_reason text, disposed_at timestamptz, disposed_tick integer);

CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, station_state text, last_heartbeat_at timestamptz);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, current_vehicle_id uuid, reserved_by uuid, reservation_expires_at timestamptz,
                            ocpp_charger_id uuid REFERENCES public.ottoq_ocpp_chargers (charger_id));
CREATE TABLE public.ottoq_stall_bookings (sim_run_id uuid, stall_id uuid, vehicle_id uuid, state text, during tstzrange);
CREATE TABLE public.ottoq_proposer_precedence (source text PRIMARY KEY, rank integer, holds_tick boolean);

-- the disposition ledger 0756's V2 reads to prove its probe left nothing (live: ottoq_capture_proposal_disposition fills it
-- on a status change; the trigger is not here, so the ledger stays empty in this world)
CREATE TABLE public.ottoq_proposal_disposition_ledger (disposition_id bigserial PRIMARY KEY, sim_run_id uuid, proposal_id uuid,
                                                       status text, disposition_reason text);

CREATE TABLE public.ottoq_schema_snapshots (label text, object_kind text, schema_name text, object_name text, definition text,
                                            def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean, forces_dial_restart boolean, note text,
                                        classified_at timestamptz);

-- nothing in flight in the test world
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_sweeps boolean DEFAULT false) RETURNS integer
  LANGUAGE sql AS $$ SELECT 0 $$;

-- promotes nothing (see the header)
CREATE FUNCTION public.ottoq_promote_proposal_candidates(p_sim_run_id uuid, p_tick_seq bigint DEFAULT NULL::bigint,
                                                         p_sim_clock timestamptz DEFAULT NULL::timestamptz,
                                                         p_max_promotions integer DEFAULT 3) RETURNS integer
  LANGUAGE sql AS $$ SELECT 0 $$;

-- the live disposer
CREATE OR REPLACE FUNCTION public.ottoq_dispose_external_proposals(p_sim_run_id uuid, p_tick_seq bigint DEFAULT NULL::bigint, p_sim_clock timestamp with time zone DEFAULT NULL::timestamp with time zone, p_finalize boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock timestamptz;
  v_wall  timestamptz := clock_timestamp();
  v_n     integer := 0;
BEGIN
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, v_wall)
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, v_wall);

  -- ═══════════ 0358: RESCUE BEFORE REFUSAL ═══════════
  -- G71: 74% of refusals named a stall that was ALREADY HELD when the proposal
  -- was made -- proposer staleness, not contention. If the proposal carries a
  -- ranked candidate set, take the first still-feasible one and leave the row
  -- pending for the next tick's enactment instead of refusing it outright.
  -- Runs BEFORE the UPDATE below so that UPDATE re-reads the promoted target and
  -- no longer has grounds to refuse it.
  -- Never allowed to abort disposal: if promotion fails, pending rows must still
  -- be disposed or they accumulate forever.
  BEGIN
    PERFORM public.ottoq_promote_proposal_candidates(
              p_sim_run_id, p_tick_seq, v_clock);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0358 promote_proposal_candidates: %', SQLERRM;
  END;

  UPDATE public.ottoq_external_proposals p
     SET status = CASE
                    WHEN p_finalize THEN 'expired'
                    WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                                  p.created_at + interval '35 minutes') < v_wall THEN 'expired'
                    ELSE 'refused'
                  END,
         disposition_reason = CASE
           WHEN p_finalize THEN 'run_finalized'
           WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                         p.created_at + interval '35 minutes') < v_wall THEN 'ttl_elapsed'
           WHEN COALESCE(p.proposal->>'abstain', '') IN ('true', 't', '1')
             THEN 'proposer_abstained'
           WHEN COALESCE(p.proposal->>'stall_id', '') !~
                '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
             THEN 'invalid_stall_id'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid)
             THEN 'stall_missing'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.current_vehicle_id IS NOT NULL)
             THEN 'stall_occupied'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.reserved_by IS NOT NULL
                AND s.reserved_by <> p.entity_id
                AND (s.reservation_expires_at IS NULL OR s.reservation_expires_at > v_clock))
             THEN 'stall_reserved'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.station_state = 'Available')
             THEN 'charger_unavailable'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.last_heartbeat_at < v_clock - interval '90 seconds')
             THEN 'charger_heartbeat_stale'
           ELSE 'target_no_longer_eligible'
         END,
         disposed_at = v_wall,
         disposed_tick = p_tick_seq
   WHERE p.sim_run_id = p_sim_run_id
     AND p.status = 'pending'
     AND (
       p_finalize
       OR GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                   p.created_at + interval '35 minutes') < v_wall
       OR (
         p.action_context = 'stall_assignment'
         AND (
           COALESCE(p.proposal->>'stall_id', '') !~
             '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
           OR NOT EXISTS (
             SELECT 1
               FROM public.stalls s
               JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
              WHERE s.id = CASE
                WHEN COALESCE(p.proposal->>'stall_id', '') ~
                     '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
                THEN (p.proposal->>'stall_id')::uuid
                ELSE NULL
              END
                AND s.current_vehicle_id IS NULL
                AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
                     OR s.reservation_expires_at <= v_clock)
                AND c.station_state = 'Available'
                AND c.last_heartbeat_at >= v_clock - interval '90 seconds'
           )
         )
       )
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- the live reader section (5) of the decide takes a staged car's service order from
CREATE OR REPLACE FUNCTION public.ottoq_l2_external_proposal(p_sim_run_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT (CASE
           WHEN p.proposal ? 'source' THEN p.proposal
           ELSE p.proposal || jsonb_build_object('source', p.source)
         END)
         -- 0091: same normalization as 'source' above, for the verb. The local
         -- greedy proposer writes verb 'assign_stall' itself; cuOpt's edge proposer
         -- does not, so every cuOpt-won enactment recorded an action with no name.
         -- verb_by says the kernel supplied the word, not the proposer.
         || CASE
              WHEN p_action_context = 'stall_assignment'
                   AND NOT (p.proposal ? 'verb')
                   AND NOT COALESCE((p.proposal->>'abstain')::boolean, false)
                THEN jsonb_build_object('verb','assign_stall','verb_by','kernel_default')
              ELSE '{}'::jsonb
            END
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = p_sim_run_id AND p.action_context = p_action_context
     AND p.entity_type = p_entity_type AND p.entity_id = p_entity_id
     AND p.status = 'pending'
     -- proposal TTL stays in the REAL domain (see migration note)
     AND GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                  p.created_at + interval '35 minutes') >= now()
     AND (p.action_context <> 'stall_assignment' OR EXISTS (
        SELECT 1 FROM stalls s
          JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
         WHERE s.id = (p.proposal->>'stall_id')::uuid
           AND s.current_vehicle_id IS NULL
           -- SIM-domain: compare reservation expiry against the run's sim clock
           AND (s.reserved_by IS NULL OR s.reserved_by = p_entity_id
                OR s.reservation_expires_at <= COALESCE(
                     (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now()))
           AND c.station_state = 'Available'
           -- SIM-domain: charger heartbeat freshness against the run's sim clock
           AND c.last_heartbeat_at >= COALESCE(
                 (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now())
                 - interval '90 seconds'
           -- 0499 (G229): the calendar, the gate's last test. A charger another car's live booking covers
           -- at the run's clock is refused by ottoq.ottoq_validate_assignment, so a proposal for it is
           -- passed over here instead of being emitted to be refused. The proposal's own vehicle's booking
           -- does not count, as at the gate. Same states and clock domain as the gate.
           AND NOT EXISTS (
             SELECT 1 FROM ottoq_stall_bookings b
              WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                AND b.state IN ('held','active','done','interrupted')
                AND b.vehicle_id <> p_entity_id
                AND b.during @> COALESCE(
                      (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), now()))))
   -- 0259: the first key is DECLARED DATA. rank comes from
   -- ottoq_proposer_precedence; an unlisted source gets the maximum, i.e.
   -- exactly where every non-cuOpt source sorted when the two keys below
   -- were literals. Seeded cuopt=0, cuopt_fallback=1, so the old two-literal
   -- order (cuopt first, then cuopt_fallback, then created_at) is reproduced
   -- exactly (A2 recomputes every historical winner).
   ORDER BY COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp
                       WHERE pp.source = p.source), 2147483647) ASC,
            p.created_at DESC,
            -- 0238 / db/checks/0156: the three keys above TIE. created_at defaults
            -- to now(), which is the TRANSACTION timestamp, and a certification pair
            -- runs both arms and every tick in one transaction -- so 98.5% of all
            -- recorded proposals share one created_at and LIMIT 1 returned
            -- index-scan order. Proven: the same two proposals submitted A,B chose A
            -- and submitted B,A chose B. Same defect 0067 closed in the stall
            -- selector next door. These three keys are total ON THE ANSWER.
            -- proposal_id is deliberately NOT among them: gen_random_uuid() differs
            -- between arms, which would reintroduce the defect as its own remedy.
            p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC
   LIMIT 1
$function$;

-- the live reader the cuOpt deferral asks; never called here
SET check_function_bodies = off;
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_defer_hold(p_sim_run_id uuid, p_vehicle_id uuid, p_tick bigint)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0259: a second gate key, proposer_hold_enabled (default 0), so a run may hold
  -- for a non-cuOpt proposer with cuOpt switched off. Certification arms set
  -- neither (0152 sets cuopt_propose_enabled=0), so the gate stays FALSE there.
  SELECT (public.ottoq_policy_get(p_sim_run_id, 'cuopt_propose_enabled', 1) >= 1
          OR public.ottoq_policy_get(p_sim_run_id, 'proposer_hold_enabled', 0) >= 1)
     /* 0056: cert quiesce — a run with the proposer disabled never holds a
        vehicle for it, even if stale deferral rows exist. Fails open. */
     AND EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d
                  WHERE d.sim_run_id = p_sim_run_id
                    AND d.vehicle_id = p_vehicle_id
                    AND d.state = 'spent'
                    AND d.spent_at_tick = p_tick)
     -- RIGHT OF FIRST REFUSAL, NOT VETO: release the moment cuOpt has ANSWERED for this
     -- vehicle. The predicate is deliberately narrowed to cuOpt-SOURCED proposals. The
     -- old test (ottoq_l2_external_proposal(...) IS NULL) accepted greedy_constrained
     -- rows too, and ottoq_l2_optimize_assignments manufactures exactly such a row for
     -- every at-gate vehicle one statement AFTER the deferral is armed — so the hold
     -- released before it could ever bind. Measured: 52 of 80 armed vehicles enacted on
     -- their own arm tick.
     --
     -- Stall LIVENESS is deliberately NOT re-checked here. If cuOpt answered but the
     -- stall it named has since been taken, we WANT the hold to release so the local
     -- greedy path can serve the vehicle this tick. Every branch fails OPEN toward
     -- assigning the vehicle.
     AND NOT EXISTS (
           SELECT 1 FROM public.ottoq_external_proposals p
            WHERE p.sim_run_id     = p_sim_run_id
              AND p.action_context = 'stall_assignment'
              AND p.entity_type    = 'vehicle'
              AND p.entity_id      = p_vehicle_id
              AND p.status         = 'pending'
              -- 0259: every source that declares holds_tick releases the hold.
              AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                                WHERE pp.holds_tick)
              -- proposal TTL stays in the REAL domain, matching ottoq_l2_external_proposal
              AND GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                           p.created_at + interval '35 minutes') >= now());
$function$;
RESET check_function_bodies;
