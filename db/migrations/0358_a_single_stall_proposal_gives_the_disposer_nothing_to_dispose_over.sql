-- migration-version: 20260920005644
-- migration-name:    a_single_stall_proposal_gives_the_disposer_nothing_to_dispose_over
--
-- 0358  THE RANKED PROPOSAL CONTRACT. A PROPOSER MAY NOW NAME AN ORDERED SET OF
--       STALLS, AND THE KERNEL TAKES THE FIRST ONE STILL FEASIBLE.
--
-- G71 measured the problem: **29 of 39 refused proposals (74%) asked for a stall
-- that was ALREADY HELD at the moment the proposal was created** (db/checks/0255).
-- That is not the depot being busy, it is the proposer being late -- G62's 30,394 ms
-- mean agent chain against a 30-second beat produces proposals about a world that
-- has already moved.
--
-- ══ 1. WHY RANKING AND NOT LOWER LATENCY ═══════════════════════════════════
--
-- Cutting the chain below one tick attacks the symptom and loses: an external model
-- call's latency is not ours to control, and a single-stall proposal is a bet that
-- the world has not moved. **A ranked set degrades gracefully where a single pick
-- does not** -- if the primary is gone the kernel takes the runner-up, and the
-- proposal still lands. Latency stops being fatal and becomes merely a cost.
--
-- It is also the correct division of labour, and CLAUDE.md already names it:
-- *agents propose, solver disposes*. The kernel owns FEASIBILITY -- it holds the
-- calendar and the EXCLUDE constraint, so it is the only thing that can know what
-- is free at the instant of decision. The proposer owns PREFERENCE. A single-stall
-- proposal inverts that: it makes the proposer decide feasibility from a stale
-- frame, and gives the disposer nothing to dispose over.
--
-- ══ 2. WHERE IT LANDS, AND WHY THAT IS ONE INSERTION POINT ═════════════════
--
-- Measured sequence inside `ottoq_decide_tick` (82,988 chars): it reads
-- `proposal->>'stall_id'` at char 21,372, writes `enacted_by_kernel` at 80,773, and
-- calls `ottoq_dispose_external_proposals` at 81,720. **Enactment happens first;
-- disposal is the cleanup at the end.**
--
-- So promotion goes at the TOP OF THE DISPOSER: rewrite the target to the first
-- feasible candidate and leave the proposal `pending`, so the NEXT tick's enactment
-- takes it. That costs one tick, which is exactly the one-tick right-of-first-refusal
-- the cuOpt deferral machinery already grants (`cuopt_first_refusal_max_defers=1`),
-- and it is nothing against being refused outright. The alternative -- promoting
-- early enough to be enacted in the SAME tick -- means editing an 83 KB function in
-- the middle of its assignment cursor. One insertion point into a 4 KB function I
-- have read end to end beats that.
--
-- The disposer's own feasibility predicate is reused VERBATIM rather than restated:
--
--     s.current_vehicle_id IS NULL
--     AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
--          OR s.reservation_expires_at <= v_clock)
--     AND c.station_state = 'Available'
--     AND c.last_heartbeat_at >= v_clock - interval '90 seconds'
--
-- Two copies of a feasibility rule drift. A6 asserts they are still the same shape.
--
-- ══ 3. THE CONTRACT ════════════════════════════════════════════════════════
--
--   proposal = {
--     "stall_id":   "<uuid>",             -- the PRIMARY, unchanged, still required
--     "candidates": ["<uuid>", "<uuid>"], -- NEW, optional, RANKED best-first
--     ...
--   }
--
-- BACKWARD COMPATIBLE BY CONSTRUCTION. A proposal with no `candidates` key is
-- untouched and refused exactly as before -- A3 asserts that, because a
-- "compatible" change that quietly alters the old path is the worst outcome here.
-- Nothing writes `candidates` yet, so this migration is INERT until a proposer
-- emits them; that is deliberate staging, not an oversight. (The two existing
-- routines mentioning 'candidates' -- `ottoq_mpc_energy_lookahead` and
-- `twin.ottoq_sim_advance_service_flow` -- are unrelated and do not collide.)
--
-- On promotion the proposal gains an audit trail, IN THE JSON so it travels with
-- the row: `promoted_from`, `promotion_count`, `promoted_at_tick`.
--
-- ══ 4. FOUR THINGS THAT WOULD HAVE BROKEN THIS ═════════════════════════════
--
-- 1. **NO WALL CLOCK IN THE PROPOSAL JSON.** `ottoq_hash_proposals` digests
--    `p.proposal::text` -- I checked its source rather than trusting a regex, which
--    first told me it did not. So a `now()` written into the JSON would differ
--    between two arms of a determinism pair and break `h_prop` on every run.
--    `promoted_at_tick` carries the TICK, which is deterministic. A5 asserts the
--    function body contains no `now()`/`clock_timestamp()` reaching the JSON.
--
-- 2. **DETERMINISTIC WALK ORDER.** Candidates are walked with
--    `jsonb_array_elements ... WITH ORDINALITY ORDER BY ord`, never by a set's
--    natural order and never tie-broken on a uuid (0195's defect).
--
-- 3. **A PROMOTION CAP.** Without one a proposal could hop stalls forever, living
--    past every TTL as its targets go stale in turn. `p_max_promotions` defaults to
--    3 and `promotion_count` is carried in the JSON. A4 asserts the cap holds.
--
-- 4. **IT CANNOT ABORT DISPOSAL.** The call is wrapped in
--    `EXCEPTION WHEN OTHERS THEN RAISE WARNING`: a promotion failure must never
--    stop proposals being disposed, or pending rows would accumulate forever. Per
--    CLAUDE.md, a failure must never abort the tick path.
--
-- ══ 5. WHAT THIS DOES NOT DO ═══════════════════════════════════════════════
--
-- * It does not make anything emit candidates. Stage 2 is a SQL-side proposer
--   emitting them (live without an edge deploy, so the effect is measurable
--   immediately); stage 3 is `ottoq-cuopt-propose`, which is where the 74% lives.
-- * It does not touch enactment, booking, or the EXCLUDE constraint. Promotion only
--   rewrites a proposal's target; the actual booking still happens in the enactor
--   under the same calendar guard, so no double-booking is possible.
-- * It does not change the staging/greenlight machinery, which already exists
--   (`ottoq_reserve_inbound_bays` -> `ottoq_activate_due_bay_reservations`), nor its
--   priority order -- that is the separate EDF question, still open and Chase's call.
--
-- forces_recert: TRUE. `ottoq_hash_proposals` digests `p.proposal::text`, and a
-- promoted proposal's JSON differs. Classified TRUE rather than argued down.
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
    RAISE EXCEPTION '0358 P0: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0358 P1: % certification pair(s) are active', v_pairs;
  END IF;

  SELECT string_agg(sim_run_id::text, ', ') INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_live IS NOT NULL THEN
    RAISE NOTICE '0358 P2: applying while Twin run(s) % are active -- tainted for reproducibility from here, deliberately', v_live;
  END IF;

  -- P3. The disposer must exist with the signature we are replacing, and must still
  -- be the 4 KB shape this file was written against rather than something larger
  -- that has grown other responsibilities since.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_dispose_external_proposals';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0358 P3a: public.ottoq_dispose_external_proposals not found';
  END IF;
  IF position('ottoq_promote_proposal_candidates' in v_src) > 0 THEN
    RAISE EXCEPTION '0358 P3b: the promotion call is already present';
  END IF;

  -- P4. The anchor for the insertion must appear exactly once.
  IF (length(v_src) - length(replace(v_src, '  UPDATE public.ottoq_external_proposals p', '')))
     / length('  UPDATE public.ottoq_external_proposals p') <> 1 THEN
    RAISE EXCEPTION '0358 P4: the disposer UPDATE anchor does not appear exactly once';
  END IF;

  -- P5. The premise of §4(1): the proposals hash digests the proposal jsonb, which
  -- is why forces_recert is TRUE and why no wall clock may enter the JSON. If this
  -- ever stops being true the classification is wrong and should be revisited.
  IF position('p.proposal::text' in
        (SELECT prosrc FROM pg_proc WHERE proname='ottoq_hash_proposals')) = 0 THEN
    RAISE EXCEPTION '0358 P5: ottoq_hash_proposals no longer digests p.proposal::text -- re-derive forces_recert before applying';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0358 P6: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $pre$;

-- ── THE PROMOTION PASS ─────────────────────────────────────────────────────────
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
  v_clock timestamptz;
  v_row   record;
  v_cand  uuid;
  v_n     integer := 0;
  v_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
BEGIN
  --: The disposer's clock resolution, copied so promotion and refusal judge
  --: feasibility against the SAME instant. Two clocks here would let a stall be
  --: feasible to one and not the other on the same tick.
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, clock_timestamp())
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, clock_timestamp());

  FOR v_row IN
    SELECT p.proposal_id, p.entity_id, p.proposal,
           COALESCE((p.proposal->>'promotion_count')::int, 0) AS promotions
      FROM public.ottoq_external_proposals p
     WHERE p.sim_run_id = p_sim_run_id
       AND p.status = 'pending'
       AND p.action_context = 'stall_assignment'
       --: only proposals that actually carry a ranked set
       AND jsonb_typeof(p.proposal->'candidates') = 'array'
       AND jsonb_array_length(p.proposal->'candidates') > 0
       AND COALESCE((p.proposal->>'promotion_count')::int, 0) < p_max_promotions
       --: ...and only those whose CURRENT target is no longer feasible. A feasible
       --: primary is left completely alone: promotion is a rescue, not a re-rank.
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
     --: deterministic row order; never the proposal's own uuid alone (0195)
     ORDER BY p.tick_seq NULLS LAST, p.proposal_id
  LOOP
    --: THE WALK. WITH ORDINALITY and ORDER BY ord is what makes "first feasible"
    --: mean first BY RANK rather than whatever order the set happens to come back
    --: in. The proposer's ordering is the preference; we honour it exactly.
    SELECT cand INTO v_cand
      FROM (
        SELECT (e.value #>> '{}')::uuid AS cand, e.ord
          FROM jsonb_array_elements(v_row.proposal->'candidates') WITH ORDINALITY AS e(value, ord)
         WHERE e.value #>> '{}' ~ v_uuid_re
         ORDER BY e.ord) c
     WHERE c.cand IS DISTINCT FROM
             CASE WHEN COALESCE(v_row.proposal->>'stall_id','') ~ v_uuid_re
                  THEN (v_row.proposal->>'stall_id')::uuid ELSE NULL END
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
     LIMIT 1;

    IF v_cand IS NOT NULL THEN
      --: NO WALL CLOCK IN HERE. ottoq_hash_proposals digests proposal::text, so a
      --: timestamp would differ between two arms of a determinism pair and break
      --: h_prop on every run. The tick is deterministic; a clock is not.
      UPDATE public.ottoq_external_proposals
         SET proposal = proposal || jsonb_build_object(
                          'stall_id',         v_cand::text,
                          'promoted_from',    proposal->>'stall_id',
                          'promotion_count',  v_row.promotions + 1,
                          'promoted_at_tick', p_tick_seq)
       WHERE proposal_id = v_row.proposal_id;
      v_n := v_n + 1;
    END IF;

    v_cand := NULL;
  END LOOP;

  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_promote_proposal_candidates(uuid, bigint, timestamptz, integer) IS
'0358. THE RANKED PROPOSAL CONTRACT, disposer side. A proposer may put an ordered best-first array of stall uuids in proposal->''candidates''; when the primary proposal->>''stall_id'' is no longer feasible this promotes the first candidate that IS, leaves the proposal pending for the next tick''s enactment, and records promoted_from / promotion_count / promoted_at_tick in the JSON. Exists because G71 measured 29 of 39 refusals (74%) asking for a stall ALREADY HELD when the proposal was made -- proposer staleness, not contention (G62: a 30,394 ms chain against a 30-second beat). A ranked set degrades gracefully under latency where a single pick does not, and it restores the propose/dispose division of labour: the kernel owns feasibility because it holds the calendar, the proposer owns preference. Feasibility is the disposer''s predicate verbatim so the two cannot drift. Deterministic by construction: candidates walked WITH ORDINALITY in rank order, and NO wall clock enters the JSON because ottoq_hash_proposals digests proposal::text. Capped by p_max_promotions (default 3) so a proposal cannot hop stalls past its TTL forever. A feasible primary is never touched -- this is a rescue, not a re-rank.';

-- ── WIRED INTO THE DISPOSER, AS ONE INSERTION ──────────────────────────────────
DO $rewrite$
DECLARE v_src text; v_new text; v_anchor text := '  UPDATE public.ottoq_external_proposals p';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_dispose_external_proposals';

  v_new := replace(v_src, v_anchor, concat_ws(E'\n',
    '  -- ═══════════ 0358: RESCUE BEFORE REFUSAL ═══════════',
    '  -- G71: 74% of refusals named a stall that was ALREADY HELD when the proposal',
    '  -- was made -- proposer staleness, not contention. If the proposal carries a',
    '  -- ranked candidate set, take the first still-feasible one and leave the row',
    '  -- pending for the next tick''s enactment instead of refusing it outright.',
    '  -- Runs BEFORE the UPDATE below so that UPDATE re-reads the promoted target and',
    '  -- no longer has grounds to refuse it.',
    '  -- Never allowed to abort disposal: if promotion fails, pending rows must still',
    '  -- be disposed or they accumulate forever.',
    '  BEGIN',
    '    PERFORM public.ottoq_promote_proposal_candidates(',
    '              p_sim_run_id, p_tick_seq, v_clock);',
    '  EXCEPTION WHEN OTHERS THEN',
    '    RAISE WARNING ''0358 promote_proposal_candidates: %'', SQLERRM;',
    '  END;',
    '',
    v_anchor));

  IF v_new = v_src THEN
    RAISE EXCEPTION '0358 R1: the anchored substitution changed nothing';
  END IF;
  IF position('ottoq_promote_proposal_candidates' in v_new) = 0 THEN
    RAISE EXCEPTION '0358 R2: the rewritten disposer does not call the promotion pass';
  END IF;

  EXECUTE v_new;
END $rewrite$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0358_a_single_stall_proposal_gives_the_disposer_nothing_to_dispose_over', true,
  'THE RANKED PROPOSAL CONTRACT, stage 1 of 3. G71 (db/checks/0255) measured 29 of 39 refused proposals '
  '(74%) asking for a stall ALREADY HELD at the moment the proposal was created -- proposer staleness, not '
  'contention, and G62''s 30,394 ms chain against a 30-second beat is the mechanism. A proposer may now put '
  'an ordered best-first array in proposal->''candidates''; ottoq_promote_proposal_candidates rewrites the '
  'target to the first still-feasible candidate when the primary has gone, leaves the proposal pending for '
  'the next tick''s enactment, and records promoted_from / promotion_count / promoted_at_tick. Wired as ONE '
  'insertion at the top of ottoq_dispose_external_proposals, chosen because decide_tick enacts at char '
  '80,773 and disposes at 81,720 -- promoting in the disposer costs one tick, which is the same '
  'right-of-first-refusal the cuOpt deferral already grants, and avoids editing an 83 KB function mid-cursor. '
  'FORCES RECERT because ottoq_hash_proposals digests p.proposal::text and a promoted proposal''s JSON '
  'differs; that same fact is why NO wall clock enters the JSON (promoted_at_tick carries the tick, which is '
  'deterministic) and A5 asserts it. Backward compatible by construction -- a proposal without candidates is '
  'untouched and A3 asserts it is still refused exactly as before. Feasibility is the disposer''s predicate '
  'verbatim so the two cannot drift (A6). Capped at 3 promotions so a proposal cannot hop stalls past its '
  'TTL. INERT until a proposer emits candidates: stage 2 is a SQL-side proposer (live without an edge '
  'deploy), stage 3 is ottoq-cuopt-propose where the 74% lives.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ── ASSERTIONS ─────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_run uuid; v_veh uuid; v_busy uuid; v_free uuid; v_free2 uuid;
  v_pid uuid; v_pid2 uuid; v_src text; v_n int; v_status text; v_stall text;
  v_promoted int; v_block int;
BEGIN
  -- A1. The pieces exist and are wired.
  IF to_regprocedure('public.ottoq_promote_proposal_candidates(uuid,bigint,timestamptz,integer)') IS NULL THEN
    RAISE EXCEPTION '0358 A1a: the promotion function is absent';
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_dispose_external_proposals';
  IF position('ottoq_promote_proposal_candidates' in v_src) = 0 THEN
    RAISE EXCEPTION '0358 A1b: the disposer does not call the promotion pass';
  END IF;
  --: and it must run BEFORE the refusal UPDATE, or it rescues nothing.
  IF position('ottoq_promote_proposal_candidates' in v_src)
     > position('UPDATE public.ottoq_external_proposals p' in v_src) THEN
    RAISE EXCEPTION '0358 A1c: the promotion pass runs AFTER the refusal UPDATE, so it can rescue nothing';
  END IF;

  -- A5. NO WALL CLOCK REACHES THE JSON. ottoq_hash_proposals digests
  -- proposal::text, so this is the difference between a working determinism pair
  -- and one that disagrees on h_prop on every single run.
  SELECT p.prosrc INTO v_src FROM pg_proc p
   WHERE p.proname='ottoq_promote_proposal_candidates';
  IF v_src ~* 'jsonb_build_object\s*\([^)]*(now\s*\(\)|clock_timestamp)' THEN
    RAISE EXCEPTION '0358 A5: a wall clock is written into the proposal JSON';
  END IF;
  IF position('promoted_at_tick' in v_src) = 0 THEN
    RAISE EXCEPTION '0358 A5b: promoted_at_tick is absent, so promotion carries no deterministic stamp';
  END IF;

  -- A6. The feasibility predicate must match the disposer's, or the two drift and a
  -- stall becomes feasible to one and not the other on the same tick.
  IF position('c2.last_heartbeat_at >= v_clock - interval ''90 seconds''' in v_src) = 0
     OR position('s.current_vehicle_id IS NULL' in v_src) = 0
     OR position('s.reservation_expires_at <= v_clock' in v_src) = 0 THEN
    RAISE EXCEPTION '0358 A6: the promotion feasibility predicate is not the disposer''s';
  END IF;

  -- ══ A2. NON-VACUITY, ON REAL ROWS. Build a proposal whose PRIMARY is occupied
  -- ══ and whose SECOND candidate is free, run the disposer, and require that the
  -- ══ proposal survived and moved. Before this migration it would have been
  -- ══ refused with 'stall_occupied'. This is the whole file in one assertion.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0358 A2a: no run on the twin depot, so A2 would be vacuous';
  END IF;

  --: an OCCUPIED stall for the primary, and two FREE healthy ones for candidates
  SELECT s.id INTO v_busy
    FROM public.stalls s
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
     AND s.current_vehicle_id IS NOT NULL AND s.ocpp_charger_id IS NOT NULL
   ORDER BY s.stall_code LIMIT 1;

  SELECT s.id INTO v_free
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id=s.ocpp_charger_id
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND c.station_state='Available'
     AND c.last_heartbeat_at >= (SELECT COALESCE(sim_clock_current, now())
                                   FROM public.ottoq_sim_runs WHERE sim_run_id=v_run)
                                - interval '90 seconds'
   ORDER BY s.stall_code LIMIT 1;

  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id='11111111-1111-1111-1111-111111111111' ORDER BY v.id LIMIT 1;

  IF v_busy IS NULL OR v_free IS NULL OR v_veh IS NULL THEN
    RAISE NOTICE '0358 A2: need one occupied stall, one free healthy stall and one vehicle on the twin depot; have busy=% free=% veh=% -- NON-VACUITY NOT PROVEN on this apply', v_busy, v_free, v_veh;
  ELSE
    --: primary = the occupied stall. candidates = [occupied, free]. The walk must
    --: skip the first (it is the infeasible primary) and take the second.
    INSERT INTO public.ottoq_external_proposals
      (sim_run_id, action_context, entity_type, entity_id, proposal, source, status, tick_seq)
    VALUES (v_run, 'stall_assignment', 'vehicle', v_veh,
            jsonb_build_object('stall_id', v_busy::text,
                               'candidates', jsonb_build_array(v_busy::text, v_free::text),
                               'requested_kw', 50,
                               'probe', '0358_nonvacuity'),
            'cuopt', 'pending', 0)
    RETURNING proposal_id INTO v_pid;

    --: A3's control, in the same breath: identical proposal, NO candidates. It must
    --: be refused, proving the promotion did not quietly rescue everything.
    INSERT INTO public.ottoq_external_proposals
      (sim_run_id, action_context, entity_type, entity_id, proposal, source, status, tick_seq)
    VALUES (v_run, 'stall_assignment', 'vehicle', v_veh,
            jsonb_build_object('stall_id', v_busy::text,
                               'requested_kw', 50,
                               'probe', '0358_backcompat'),
            'cuopt', 'pending', 0)
    RETURNING proposal_id INTO v_pid2;

    PERFORM public.ottoq_dispose_external_proposals(v_run, 0, NULL, false);

    -- A2: the ranked one SURVIVED and MOVED to the free candidate.
    SELECT status, proposal->>'stall_id', COALESCE((proposal->>'promotion_count')::int,0)
      INTO v_status, v_stall, v_promoted
      FROM public.ottoq_external_proposals WHERE proposal_id = v_pid;
    IF v_status <> 'pending' THEN
      RAISE EXCEPTION '0358 A2b: the ranked proposal was % instead of surviving as pending', v_status;
    END IF;
    IF v_stall <> v_free::text THEN
      RAISE EXCEPTION '0358 A2c: the ranked proposal points at % , expected the free candidate %', v_stall, v_free;
    END IF;
    IF v_promoted <> 1 THEN
      RAISE EXCEPTION '0358 A2d: promotion_count is % , expected 1', v_promoted;
    END IF;

    -- A3: BACKWARD COMPATIBILITY. The candidate-less twin must still be refused.
    SELECT status INTO v_status
      FROM public.ottoq_external_proposals WHERE proposal_id = v_pid2;
    IF v_status <> 'refused' THEN
      RAISE EXCEPTION '0358 A3: a proposal WITHOUT candidates was % instead of refused -- the old path changed', v_status;
    END IF;

    -- A4: THE CAP. Drive promotion_count to the limit and require it stops.
    UPDATE public.ottoq_external_proposals
       SET proposal = proposal || jsonb_build_object('stall_id', v_busy::text,
                                                     'promotion_count', 3),
           status = 'pending', disposition_reason = NULL, disposed_at = NULL
     WHERE proposal_id = v_pid;
    SELECT public.ottoq_promote_proposal_candidates(v_run, 0, NULL, 3) INTO v_n;
    SELECT proposal->>'stall_id' INTO v_stall
      FROM public.ottoq_external_proposals WHERE proposal_id = v_pid;
    IF v_stall <> v_busy::text THEN
      RAISE EXCEPTION '0358 A4: promotion ran past the cap (target moved to %)', v_stall;
    END IF;

    --: clean up both probes; they are test rows, not evidence.
    DELETE FROM public.ottoq_external_proposals WHERE proposal_id IN (v_pid, v_pid2);
    RAISE NOTICE '0358 A2/A3/A4 OK: ranked proposal promoted to the free candidate, candidate-less twin refused, cap held';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0358 A7: the registry guard now reports % blocking defect(s)', v_block;
  END IF;
END $post$;

COMMIT;
