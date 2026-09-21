-- migration-version: 20260920010111
-- migration-name:    a_promoted_candidate_must_carry_its_own_kilowatts_or_the_shield_judges_the_wrong_load
--
-- 0359  0358 REWROTE THE STALL AND LEFT THE KILOWATTS BEHIND. FOUR ENERGY RULES
--       READ THOSE KILOWATTS.
--
-- 0358 shipped the ranked proposal contract: a proposer may name an ordered set of
-- stalls and the kernel takes the first still feasible, which is G71's 74%-stale
-- refusals fixed at the contract level. It promoted `proposal.stall_id` and stopped
-- there.
--
-- `requested_kw` is not decoration. Measured -- it is read by **four L1 energy
-- evaluators and the decide path**:
--
--   ottoq_eval_en_001_grid_capacity        the engineering-cap gate
--   ottoq_eval_en_002_stall_power_ceiling  the per-stall ceiling
--   ottoq_eval_en_003_bess_limits          battery dispatch limits
--   ottoq_eval_en_004_demand_response      DR-window compliance
--   ottoq_decide_tick                      the enactor itself
--
-- So a promotion that moves a proposal to a stall of different capability while
-- leaving `requested_kw` untouched makes **the shield evaluate the grid against a
-- load the vehicle will not draw**. On a depot that has run to within 26.1 kW of its
-- engineering cap (db/checks/0253 §3) that is not a rounding error.
--
-- NOTHING IS WRONG TODAY, and the reason is worth stating precisely: 0358 is INERT
-- -- no proposer emits `candidates`, so no promotion has ever occurred, so no wrong
-- kW has ever reached an evaluator. This file closes the hole BEFORE the edge
-- function starts emitting candidates, which is the next step. Caught by asking what
-- consumes the field rather than by assuming a stall swap is a stall swap.
--
-- ══ 1. THE CONTRACT, COMPLETED ═════════════════════════════════════════════
--
-- `candidates` now accepts TWO element shapes, and the difference is a safety rule
-- rather than a convenience:
--
--   "candidates": [
--     {"stall_id": "<uuid>", "requested_kw": 85.0},   -- PREFERRED: carries its load
--     "<uuid>"                                        -- LEGACY: bare uuid
--   ]
--
--   * OBJECT element -> promote and rewrite `requested_kw` from the element. The
--     emitter computed the draw for that specific stall, so the shield gets the
--     right number.
--
--   * BARE UUID element -> promotable ONLY IF the candidate's `connector_max_kw`
--     equals the primary's. Without a per-candidate kW the existing `requested_kw`
--     is only valid on a like-for-like plug, so a bare uuid on a different-capacity
--     stall is SKIPPED rather than promoted with a stale load. That is the
--     self-enforcing half: the contract refuses to guess.
--
-- Recomputing the draw in SQL was the obvious alternative and is rejected: the taper
-- formula lives in the edge function (`min(connector, inlet) x curve`, its "brain's
-- exact E3 formula") and a second copy in plpgsql would drift from it silently --
-- the same reasoning that made 0358 reuse the disposer's feasibility predicate
-- verbatim instead of restating it.
--
-- ══ 2. WHAT ELSE THIS FIXES, FOUND THE SAME WAY ════════════════════════════
--
-- CONNECTOR COMPATIBILITY. The disposer's feasibility predicate -- which 0358
-- reuses, deliberately and verbatim -- checks occupancy, reservation, charger state
-- and heartbeat. **It does not check whether the vehicle can physically plug into
-- the stall.** For a single-stall proposal that never mattered: the proposer chose
-- the stall and had already applied its own `compatible()` test. For a PROMOTED
-- candidate it matters enormously, because the kernel is now choosing.
--
-- So promotion additionally requires the candidate to be inlet-compatible with the
-- vehicle, using the same rules the emitter uses: exact connector match, membership
-- of `supported_inlet_types`, or the NACS/Tesla_Proprietary equivalence. A vehicle
-- is never promoted onto a plug it cannot take. A4 asserts it by construction.
--
-- ══ 3. AND ONE THING DELIBERATELY NOT ENFORCED ═════════════════════════════
--
-- Promotion does NOT require the candidate to be the same `stall_type`. An l2
-- vehicle promoted to a free dcfc stall is a legitimate and often better outcome --
-- it is the pressure valve Chase described, and the kW rules above keep it honest.
-- What is enforced is that the load is correct and the plug fits; the service class
-- is the proposer's business, expressed through its ranking.
--
-- forces_recert: TRUE. Same reason as 0358 -- `ottoq_hash_proposals` digests
-- `p.proposal::text` and a promoted proposal's JSON differs, now in one more field.
--
-- Applied through the Management API, so the `schema_migrations` row is written
-- explicitly -- see 0354's header.

BEGIN;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- ── PRECONDITIONS ──────────────────────────────────────────────────────────────
DO $pre$
DECLARE v_jobs text; v_pairs int; v_live text; v_block int; v_src text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0359 P0: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0359 P1: % certification pair(s) are active', v_pairs;
  END IF;

  SELECT string_agg(sim_run_id::text, ', ') INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_live IS NOT NULL THEN
    RAISE NOTICE '0359 P2: applying while Twin run(s) % are active -- tainted for reproducibility from here, deliberately', v_live;
  END IF;

  -- P3. 0358 must be in place: this file extends its walk, it does not create it.
  IF to_regprocedure('public.ottoq_promote_proposal_candidates(uuid,bigint,timestamptz,integer)') IS NULL THEN
    RAISE EXCEPTION '0359 P3: 0358 is not applied (the promotion function is absent)';
  END IF;

  -- P4. Not already applied.
  SELECT p.prosrc INTO v_src FROM pg_proc p
   WHERE p.proname = 'ottoq_promote_proposal_candidates';
  IF position('v_cand_kw' in v_src) > 0 THEN
    RAISE EXCEPTION '0359 P4: the per-candidate kW handling is already present';
  END IF;

  -- P5. THE PREMISE: requested_kw must still be read by the energy evaluators, or
  -- this file is solving a problem that no longer exists.
  SELECT count(*) INTO v_block
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname IN ('ottoq_eval_en_001_grid_capacity','ottoq_eval_en_002_stall_power_ceiling',
                       'ottoq_eval_en_004_demand_response')
     AND position('requested_kw' in p.prosrc) > 0;
  IF v_block <> 3 THEN
    RAISE EXCEPTION '0359 P5: expected 3 energy evaluators reading requested_kw, found % -- re-derive the premise', v_block;
  END IF;

  -- P6. The connector columns this file's compatibility test needs.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='stalls'
                    AND column_name='supported_inlet_types')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='stalls'
                       AND column_name='connector_type')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='stalls'
                       AND column_name='connector_max_kw') THEN
    RAISE EXCEPTION '0359 P6: stalls lacks connector_type / supported_inlet_types / connector_max_kw';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0359 P7: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $pre$;

-- ── THE COMPATIBILITY TEST, AS ITS OWN FUNCTION ───────────────────────────────
-- Extracted rather than inlined so it can be tested on its own and so the edge
-- function's `compatible()` has exactly one SQL counterpart to agree with.
CREATE OR REPLACE FUNCTION public.ottoq_inlet_fits_stall(p_inlet text, p_stall_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  --: The edge function's compatible() in SQL. Order matters and mirrors it:
  --:   1. no inlet declared -> anything fits (the vehicle does not constrain us)
  --:   2. supported_inlet_types, when non-empty, is AUTHORITATIVE
  --:   3. NACS accepts NACS and Tesla_Proprietary
  --:   4. otherwise an exact connector_type match
  SELECT CASE
    WHEN p_inlet IS NULL OR btrim(p_inlet) = '' THEN true
    ELSE COALESCE((
      SELECT CASE
        WHEN COALESCE(array_length(s.supported_inlet_types, 1), 0) > 0
          THEN upper(p_inlet) = ANY (SELECT upper(x)
                                       FROM unnest(s.supported_inlet_types) AS x)
        WHEN upper(COALESCE(s.connector_type,'')) = 'NACS'
          THEN upper(p_inlet) IN ('NACS','TESLA_PROPRIETARY')
        ELSE upper(COALESCE(s.connector_type,'')) = upper(p_inlet)
      END
      FROM public.stalls s WHERE s.id = p_stall_id), false)
  END;
$function$;

COMMENT ON FUNCTION public.ottoq_inlet_fits_stall(text, uuid) IS
'0359. Can this inlet physically use this stall? The SQL counterpart of ottoq-cuopt-propose''s compatible(), in the same precedence: a NULL/blank inlet fits anything; a non-empty supported_inlet_types is authoritative; NACS accepts NACS and Tesla_Proprietary; otherwise connector_type must match exactly. Exists because the disposer''s feasibility predicate checks occupancy, reservation, charger state and heartbeat but NOT whether the plug fits -- which never mattered while the proposer chose the stall, and matters entirely once the kernel promotes a candidate on its own.';

-- ── THE PROMOTION PASS, COMPLETED ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_promote_proposal_candidates(
  p_sim_run_id      uuid,
  p_tick_seq        bigint      DEFAULT NULL,
  p_sim_clock       timestamptz DEFAULT NULL,
  p_max_promotions  integer     DEFAULT 3)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock   timestamptz;
  v_row     record;
  v_cand    uuid;
  v_cand_kw numeric;          -- 0359: the candidate's OWN load, or NULL for a bare uuid
  v_n       integer := 0;
  v_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
BEGIN
  --: The disposer's clock resolution, copied so promotion and refusal judge
  --: feasibility against the SAME instant.
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, clock_timestamp())
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, clock_timestamp());

  FOR v_row IN
    SELECT p.proposal_id, p.entity_id, p.proposal,
           COALESCE((p.proposal->>'promotion_count')::int, 0) AS promotions,
           --: 0359. The vehicle's inlet and the PRIMARY's plug capacity: the two
           --: facts a promotion must respect. entity_id is the vehicle for a
           --: stall_assignment proposal.
           (SELECT v.inlet_type FROM public.vehicles v WHERE v.id = p.entity_id) AS inlet,
           (SELECT s.connector_max_kw FROM public.stalls s
             WHERE s.id = CASE WHEN COALESCE(p.proposal->>'stall_id','') ~ v_uuid_re
                               THEN (p.proposal->>'stall_id')::uuid ELSE NULL END) AS primary_kw
      FROM public.ottoq_external_proposals p
     WHERE p.sim_run_id = p_sim_run_id
       AND p.status = 'pending'
       AND p.action_context = 'stall_assignment'
       AND jsonb_typeof(p.proposal->'candidates') = 'array'
       AND jsonb_array_length(p.proposal->'candidates') > 0
       AND COALESCE((p.proposal->>'promotion_count')::int, 0) < p_max_promotions
       --: only proposals whose CURRENT target is no longer feasible. A feasible
       --: primary is left alone: promotion is a rescue, not a re-rank.
       AND NOT EXISTS (
         SELECT 1
           FROM public.stalls s
           JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
          WHERE s.id = CASE WHEN COALESCE(p.proposal->>'stall_id','') ~ v_uuid_re
                            THEN (p.proposal->>'stall_id')::uuid ELSE NULL END
            AND s.current_vehicle_id IS NULL
            AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
                 OR s.reservation_expires_at <= v_clock)
            AND c.station_state = 'Available'
            AND c.last_heartbeat_at >= v_clock - interval '90 seconds')
     ORDER BY p.tick_seq NULLS LAST, p.proposal_id
  LOOP
    --: THE WALK. WITH ORDINALITY + ORDER BY ord makes "first feasible" mean first
    --: BY RANK. Each element is either a bare uuid string or an object carrying its
    --: own requested_kw -- 0359's whole point, because four L1 energy evaluators
    --: read requested_kw and a promotion that leaves it stale makes the shield
    --: judge a load the vehicle will not draw.
    SELECT c.cand, c.cand_kw
      INTO v_cand, v_cand_kw
      FROM (
        SELECT CASE
                 WHEN jsonb_typeof(e.value) = 'object' THEN e.value->>'stall_id'
                 ELSE e.value #>> '{}'
               END AS cand_txt,
               CASE
                 WHEN jsonb_typeof(e.value) = 'object'
                  AND (e.value->>'requested_kw') ~ '^[0-9]+(\.[0-9]+)?$'
                 THEN (e.value->>'requested_kw')::numeric
                 ELSE NULL
               END AS cand_kw,
               e.ord
          FROM jsonb_array_elements(v_row.proposal->'candidates')
               WITH ORDINALITY AS e(value, ord)) raw
      CROSS JOIN LATERAL (SELECT raw.cand_txt::uuid AS cand, raw.cand_kw, raw.ord) c
     WHERE raw.cand_txt ~ v_uuid_re
       AND c.cand IS DISTINCT FROM
             CASE WHEN COALESCE(v_row.proposal->>'stall_id','') ~ v_uuid_re
                  THEN (v_row.proposal->>'stall_id')::uuid ELSE NULL END
       --: 0359 (a). THE PLUG MUST FIT. The disposer's predicate never checked this
       --: because the proposer used to choose the stall itself.
       AND public.ottoq_inlet_fits_stall(v_row.inlet, c.cand)
       --: 0359 (b). THE LOAD MUST BE RIGHT. An object candidate brings its own kW.
       --: A bare uuid does not, so it is only promotable onto a plug of the SAME
       --: capacity, where the proposal's existing requested_kw stays valid. The
       --: contract refuses to guess a load.
       AND (c.cand_kw IS NOT NULL
            OR EXISTS (SELECT 1 FROM public.stalls s2
                        WHERE s2.id = c.cand
                          AND s2.connector_max_kw IS NOT DISTINCT FROM v_row.primary_kw))
       AND EXISTS (
         SELECT 1
           FROM public.stalls s
           JOIN public.ottoq_ocpp_chargers c2 ON c2.charger_id = s.ocpp_charger_id
          WHERE s.id = c.cand
            AND s.current_vehicle_id IS NULL
            AND (s.reserved_by IS NULL OR s.reserved_by = v_row.entity_id
                 OR s.reservation_expires_at <= v_clock)
            AND c2.station_state = 'Available'
            AND c2.last_heartbeat_at >= v_clock - interval '90 seconds')
     ORDER BY c.ord
     LIMIT 1;

    IF v_cand IS NOT NULL THEN
      --: NO WALL CLOCK: ottoq_hash_proposals digests proposal::text, so a timestamp
      --: would differ between two arms of a pair. promoted_at_tick is deterministic.
      --: requested_kw is rewritten ONLY when the candidate supplied one; otherwise
      --: the (a)/(b) guards above have already proven the existing value still holds.
      UPDATE public.ottoq_external_proposals
         SET proposal = proposal
                        || jsonb_build_object(
                             'stall_id',         v_cand::text,
                             'promoted_from',    proposal->>'stall_id',
                             'promotion_count',  v_row.promotions + 1,
                             'promoted_at_tick', p_tick_seq)
                        || CASE WHEN v_cand_kw IS NOT NULL
                                THEN jsonb_build_object('requested_kw', v_cand_kw,
                                                        'requested_kw_promoted', true)
                                ELSE '{}'::jsonb END
       WHERE proposal_id = v_row.proposal_id;
      v_n := v_n + 1;
    END IF;

    v_cand := NULL; v_cand_kw := NULL;
  END LOOP;

  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_promote_proposal_candidates(uuid, bigint, timestamptz, integer) IS
'0358, completed by 0359. THE RANKED PROPOSAL CONTRACT, disposer side. A proposer puts an ordered best-first array in proposal->''candidates''; when the primary proposal->>''stall_id'' is no longer feasible this promotes the first candidate that IS, leaves the proposal pending for the next tick''s enactment, and records promoted_from / promotion_count / promoted_at_tick. Exists because G71 measured 29 of 39 refusals (74%) naming a stall ALREADY HELD when the proposal was made -- proposer staleness, not contention. 0359 added the two things a stall swap is not: (a) THE PLUG MUST FIT -- the disposer''s feasibility predicate never checked inlet compatibility because the proposer used to choose the stall, so promotion calls ottoq_inlet_fits_stall; (b) THE LOAD MUST BE RIGHT -- requested_kw is read by four L1 energy evaluators (EN.001/002/003/004) and decide_tick, so an object candidate carries its own requested_kw and is rewritten on promotion, while a bare-uuid candidate is promotable ONLY onto a plug of identical connector_max_kw where the existing value stays valid. The contract refuses to guess a load. Deterministic: candidates walked WITH ORDINALITY in rank order, no wall clock in the JSON. Capped by p_max_promotions (default 3). A feasible primary is never touched. Stall TYPE is deliberately not constrained -- l2 to a free dcfc is a legitimate rescue once the load and the plug are right.';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0359_a_promoted_candidate_must_carry_its_own_kilowatts_or_the_shield_judges_the_wrong_load', true,
  'Completes 0358''s ranked proposal contract with the two things a stall swap is not. (a) requested_kw is '
  'read by FOUR L1 energy evaluators (EN.001 grid capacity, EN.002 stall power ceiling, EN.003 BESS limits, '
  'EN.004 demand response) and by decide_tick, so 0358''s promotion -- which rewrote stall_id and left the '
  'kW behind -- would have made the shield evaluate a load the vehicle will not draw, on a depot that has '
  'run to within 26.1 kW of its engineering cap. candidates may now be objects carrying their own '
  'requested_kw, rewritten on promotion; a bare uuid is promotable ONLY onto a plug of identical '
  'connector_max_kw, where the existing value stays valid. Recomputing the taper in SQL was rejected: the '
  'formula lives in the edge function and a second copy would drift. (b) The disposer''s feasibility '
  'predicate checks occupancy, reservation, charger state and heartbeat but NOT whether the plug fits -- '
  'irrelevant while the proposer chose the stall, decisive once the kernel promotes one -- so '
  'ottoq_inlet_fits_stall mirrors the edge function''s compatible() in SQL and gates every promotion. '
  'NOTHING WAS WRONG IN PRODUCTION: 0358 is inert because no proposer emits candidates yet, so no promotion '
  'had occurred and no wrong kW ever reached an evaluator; this closes the hole before the edge function '
  'starts emitting. Stall TYPE deliberately unconstrained: l2 to a free dcfc is a legitimate rescue once '
  'load and plug are right. FORCES RECERT for 0358''s reason -- ottoq_hash_proposals digests '
  'p.proposal::text.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ── ASSERTIONS ─────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_run uuid; v_veh uuid; v_busy uuid; v_freeA uuid; v_freeB uuid;
  v_pid uuid; v_stall text; v_kw numeric; v_status text; v_n int; v_block int;
  v_inlet text; v_busy_kw numeric; v_freeA_kw numeric;
BEGIN
  -- A1. Both functions present, and the promotion pass now carries kW handling.
  IF to_regprocedure('public.ottoq_inlet_fits_stall(text,uuid)') IS NULL THEN
    RAISE EXCEPTION '0359 A1a: ottoq_inlet_fits_stall is absent';
  END IF;
  IF position('v_cand_kw' in
        (SELECT prosrc FROM pg_proc WHERE proname='ottoq_promote_proposal_candidates')) = 0 THEN
    RAISE EXCEPTION '0359 A1b: the promotion pass carries no per-candidate kW handling';
  END IF;
  IF position('ottoq_inlet_fits_stall' in
        (SELECT prosrc FROM pg_proc WHERE proname='ottoq_promote_proposal_candidates')) = 0 THEN
    RAISE EXCEPTION '0359 A1c: promotion does not gate on inlet compatibility';
  END IF;

  -- A2. THE COMPATIBILITY TEST IS NOT VACUOUS. A NULL inlet must fit anything, and
  -- a deliberately absurd inlet must fit nothing. A test that always returns true
  -- would silently disable (a).
  SELECT s.id INTO v_freeA FROM public.stalls s
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111' AND s.ocpp_charger_id IS NOT NULL
   ORDER BY s.stall_code LIMIT 1;
  IF v_freeA IS NULL THEN
    RAISE EXCEPTION '0359 A2a: no stall on the twin depot, so A2 would be vacuous';
  END IF;
  IF NOT public.ottoq_inlet_fits_stall(NULL, v_freeA) THEN
    RAISE EXCEPTION '0359 A2b: a NULL inlet does not fit -- the test is too strict and would block every promotion';
  END IF;
  IF public.ottoq_inlet_fits_stall('NO_SUCH_INLET_0359', v_freeA) THEN
    RAISE EXCEPTION '0359 A2c: an impossible inlet fits -- the test is vacuous and (a) is disabled';
  END IF;

  -- ══ A3. THE kW REWRITE, ON REAL ROWS. An object candidate must move BOTH the
  -- ══ stall and the load. This is the defect 0358 shipped, so it is asserted
  -- ══ rather than described.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id='11111111-1111-1111-1111-111111111111'
   ORDER BY r.started_at DESC LIMIT 1;

  SELECT s.id, s.connector_max_kw INTO v_busy, v_busy_kw
    FROM public.stalls s
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
     AND s.current_vehicle_id IS NOT NULL AND s.ocpp_charger_id IS NOT NULL
   ORDER BY s.stall_code LIMIT 1;

  SELECT s.id, s.connector_max_kw INTO v_freeB, v_freeA_kw
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id=s.ocpp_charger_id
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND c.station_state='Available'
     AND c.last_heartbeat_at >= (SELECT COALESCE(sim_clock_current, now())
                                   FROM public.ottoq_sim_runs WHERE sim_run_id=v_run)
                                - interval '90 seconds'
   ORDER BY s.stall_code LIMIT 1;

  --: a vehicle whose inlet actually fits the free stall, or (a) would correctly
  --: refuse the promotion and A3 would fail for the wrong reason.
  SELECT v.id, v.inlet_type INTO v_veh, v_inlet
    FROM public.vehicles v
   WHERE v.home_depot_id='11111111-1111-1111-1111-111111111111'
     AND public.ottoq_inlet_fits_stall(v.inlet_type, v_freeB)
   ORDER BY v.id LIMIT 1;

  IF v_run IS NULL OR v_busy IS NULL OR v_freeB IS NULL OR v_veh IS NULL THEN
    RAISE NOTICE '0359 A3: fixture unavailable (run=% busy=% free=% veh=%) -- THE kW REWRITE IS NOT PROVEN on this apply', v_run, v_busy, v_freeB, v_veh;
  ELSE
    INSERT INTO public.ottoq_external_proposals
      (sim_run_id, action_context, entity_type, entity_id, proposal, source, status, tick_seq)
    VALUES (v_run, 'stall_assignment', 'vehicle', v_veh,
            jsonb_build_object(
              'stall_id', v_busy::text,
              'requested_kw', 11.0,                       -- the PRIMARY's load
              'candidates', jsonb_build_array(
                 jsonb_build_object('stall_id', v_freeB::text, 'requested_kw', 137.5)),
              'probe', '0359_kw_rewrite'),
            'cuopt', 'pending', 0)
    RETURNING proposal_id INTO v_pid;

    SELECT public.ottoq_promote_proposal_candidates(v_run, 0, NULL, 3) INTO v_n;

    SELECT proposal->>'stall_id', (proposal->>'requested_kw')::numeric, status
      INTO v_stall, v_kw, v_status
      FROM public.ottoq_external_proposals WHERE proposal_id = v_pid;

    IF v_stall <> v_freeB::text THEN
      RAISE EXCEPTION '0359 A3a: promotion did not move the stall (got %)', v_stall;
    END IF;
    IF v_kw IS DISTINCT FROM 137.5 THEN
      RAISE EXCEPTION '0359 A3b: requested_kw is % , expected the candidate''s 137.5 -- the shield would judge the wrong load', v_kw;
    END IF;
    IF NOT COALESCE((SELECT (proposal->>'requested_kw_promoted')::boolean
                       FROM public.ottoq_external_proposals WHERE proposal_id=v_pid), false) THEN
      RAISE EXCEPTION '0359 A3c: the kW rewrite left no audit marker';
    END IF;

    -- A4. THE BARE-UUID GUARD. Same shape, but a bare uuid candidate on a stall of
    -- DIFFERENT capacity must NOT be promoted -- the contract refuses to guess.
    IF v_freeA_kw IS DISTINCT FROM v_busy_kw THEN
      UPDATE public.ottoq_external_proposals
         SET proposal = jsonb_build_object(
               'stall_id', v_busy::text, 'requested_kw', 11.0,
               'candidates', jsonb_build_array(v_freeB::text),
               'probe', '0359_bare_guard'),
             status='pending', disposition_reason=NULL, disposed_at=NULL
       WHERE proposal_id = v_pid;
      PERFORM public.ottoq_promote_proposal_candidates(v_run, 0, NULL, 3);
      SELECT proposal->>'stall_id' INTO v_stall
        FROM public.ottoq_external_proposals WHERE proposal_id=v_pid;
      IF v_stall <> v_busy::text THEN
        RAISE EXCEPTION '0359 A4: a bare uuid was promoted onto a %kW plug from a %kW primary, leaving requested_kw stale', v_freeA_kw, v_busy_kw;
      END IF;
    ELSE
      RAISE NOTICE '0359 A4: the free and occupied stalls have identical connector_max_kw (%), so the bare-uuid guard is not exercised on this apply', v_busy_kw;
    END IF;

    DELETE FROM public.ottoq_external_proposals WHERE proposal_id = v_pid;
    RAISE NOTICE '0359 A3/A4 OK: object candidate moved stall AND kW; bare-uuid guard held';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0359 A5: the registry guard now reports % blocking defect(s)', v_block;
  END IF;
END $post$;

COMMIT;
