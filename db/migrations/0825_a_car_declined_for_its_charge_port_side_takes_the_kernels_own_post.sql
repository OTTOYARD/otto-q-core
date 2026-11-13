-- migration-version: 20261113054256
-- migration-name:    0825_a_car_declined_for_its_charge_port_side_takes_the_kernels_own_post
--
-- 0825  **A car whose proposed post is on the wrong side of it takes the kernel's own post in the same tick.**
--
-- WHY. CLAUDE.md rule 9: site pressure is never a lever on a vehicle, and a car waits only for capacity. 0824 made a
--   car wait for a reason that was neither.
--
-- §1 WHAT WAS SO (db/checks/0490, run a95e51a3, read 2026-11-13 05:39 to 05:41 UTC). 0824 declines any proposer's post whose
--   arm stands on the wrong side of the car, "as an abstention ... the car keeps its place". The charge step takes its
--   proposal from public.ottoq_honour_reservation_proposal, which answers with an external proposer's post when there
--   is one and asks the kernel's own proposer only when there is none. The external proposers (forward_lex, cuopt,
--   greedy_constrained) do not know the side rule. So a car they offered a wrong-side post was declined and NOT offered
--   another, tick after tick, while the kernel's proposer (which 0824 taught the rule) was never asked.
--   Measured on the run after 0824's apply: 4,454 declines on 44 cars (forward_lex 3,403, cuopt 994,
--   greedy_constrained 57), in 219 ticks with a mean of 20.3 cars declined a tick. In 208 of those 219 ticks a
--   left-arm post was free by the calendar (a mean of 8.3 of 15 taken). Of the 44 cars, 28 were seated later, a mean
--   103.6 sim minutes after their first decline (the longest 288.5), and 16 were not seated before the run ended.
--   The seats themselves were right: 63 of 63 left-port seats on left-arm posts.
--
-- §2 WHAT THIS DOES. In the charge step, when a proposal is declined for the side, the kernel's own proposer
--   (public.ottoq_l2_propose_stall_assignment, which offers only posts that fit) is asked in the same tick. If it
--   offers a post that fits, that post is the proposal, and it records what it replaced (`replaced_source`,
--   `replaced_stall_id`). The abstention remains only when the kernel has no fitting post either: the car then waits
--   for capacity, which is the only wait rule 9 allows. Nothing else moves: the order of the line, the shield, the
--   calendar and every other gate apply to the kernel's post as to any proposal.
--
-- §3 WHAT THIS DOES NOT DO. It does not teach the external proposers the rule: their wrong-side answers are still
--   written, and still declined (the proposal disposition ledger shows them as not enacted). It does not touch 0820's
--   decline (a car with a charge and a cabin clean waits for a fast-charger post): read on the same run, that decline
--   fired 0 times, since the twin depot's charge posts are all fast chargers.
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight (a run may be live, as for 0824).
--   P1 the body this file was written against (md5 of prosrc, read 2026-11-13 05:4x UTC). P2 once. V1 the patched body
--   with its patch reversed is its pre-image. V2 the anchor matched once. V3 what the new branch stands on: the kernel's
--   proposer still carries 0824's side filter, the setting is on at the twin depot, and, when a run is live at the
--   apply, the proposer asked for up to 20 left-port cars offers none of them a right-arm post. The branch itself is
--   first exercised by the next run's ticks: db/checks/0490 has the query to read.
--
-- §5 CLASSIFICATION. forces_recert TRUE (which post a declined car takes, and when, changes at the twin depot),
--   forces_dial_restart FALSE. Nothing acts on it until testing resumes (rule 12).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0825_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0825_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0, P1, P2 ──
DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0825 P0: a certification is in flight'; END IF;
  /* A run may be live, as for 0824: the body is replaced whole, and a tick in flight ends on the body it began on. */
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM '8454612c7529bbe9bba3c85ddc3bbf34' THEN
    RAISE EXCEPTION '0825 P1: public.ottoq_decide_tick is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0825_%') THEN RAISE EXCEPTION '0825 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0825_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_decide_tick(uuid)']) AS f;

-- ── the patch ──
CREATE TEMP TABLE _0825_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0825_patch VALUES
(1, 'public.ottoq_decide_tick(uuid)',
$o1$      v_proposal := jsonb_build_object('abstain', true, 'reason', 'waits_for_a_post_on_its_charge_port_side',
                                       'declined_stall_id', v_proposal->>'stall_id',
                                       'declined_source', v_proposal->>'source');
    END IF;
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;$o1$,
$n1$      /* 0825 (rule 9): the car is not made to wait for that. The kernel's own proposer offers only posts that fit
         (0824 (d)); it is asked now, and its post is taken when it has one. The abstention is left for the case
         where the kernel has no fitting post either: the car then waits for capacity and for nothing else. */
      DECLARE v_own jsonb;
      BEGIN
        v_own := public.ottoq_l2_propose_stall_assignment(v_req.vehicle_id, v_depot, v_ctx);
        IF NOT COALESCE((v_own->>'abstain')::boolean, true)
           AND NULLIF(v_own->>'stall_id', '') IS NOT NULL
           AND public.ottoq_port_side_fits_stall(p_sim_run_id, v_req.vehicle_id, NULLIF(v_own->>'stall_id', '')::uuid) THEN
          v_proposal := v_own || jsonb_build_object('replaced_stall_id', v_proposal->>'stall_id',
                                                    'replaced_source', v_proposal->>'source',
                                                    'replaced_for', 'charge_port_side');
        ELSE
          v_proposal := jsonb_build_object('abstain', true, 'reason', 'waits_for_a_post_on_its_charge_port_side',
                                           'declined_stall_id', v_proposal->>'stall_id',
                                           'declined_source', v_proposal->>'source');
        END IF;
      END;
    END IF;
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0825_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0825 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0825: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0825_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0825_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0825_pre' AND s.object_name = f.fn LIMIT 1) THEN
      RAISE EXCEPTION '0825 V1: % with its patch reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── V3 what the new branch stands on ──
CREATE TEMP TABLE _0825_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_car uuid; v_prop jsonb; v_side text; v_asked int := 0; v_offered int := 0;
BEGIN
  -- the kernel's proposer still carries 0824's filter: the post it offers a car fits the car
  IF position('AND public.ottoq_port_side_fits_stall(v_run, p_vehicle_id, s.id)' IN
              pg_get_functiondef(to_regprocedure('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'))) = 0 THEN
    RAISE EXCEPTION '0825 V3: the kernel''s proposer does not carry the side filter';
  END IF;
  IF COALESCE((SELECT pp.param_value FROM public.ottoq_policy_params pp
                WHERE pp.scope_type = 'depot' AND pp.scope_id = c_depot AND pp.param_key = 'charge_port_side_routing'), 0) < 1 THEN
    RAISE EXCEPTION '0825 V3: charge_port_side_routing is not on at the twin depot';
  END IF;
  -- with a run live, ask it for every left-port car of the depot: an offered post is a left-arm post
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.status = 'running' AND r.depot_id = c_depot ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    FOR v_car IN SELECT v.id FROM public.vehicles v
                  WHERE v.home_depot_id = c_depot AND v.category = 'autonomous'
                    AND (public.ottoq_vehicle_port_profile(v.id)).port_face = 'left'
                    AND NOT (public.ottoq_vehicle_port_profile(v.id)).presents_either_side
                  ORDER BY v.id LIMIT 20 LOOP
      v_asked := v_asked + 1;
      v_prop := public.ottoq_l2_propose_stall_assignment(v_car, c_depot, jsonb_build_object('current_soc', 20));
      IF NOT COALESCE((v_prop->>'abstain')::boolean, true) AND NULLIF(v_prop->>'stall_id', '') IS NOT NULL THEN
        v_side := public.ottoq_stall_arm_side((v_prop->>'stall_id')::uuid);
        IF v_side IS NOT NULL AND v_side <> 'left' THEN
          RAISE EXCEPTION '0825 V3: the kernel offers left-port car % a %-arm post', v_car, v_side;
        END IF;
        v_offered := v_offered + 1;
      END IF;
    END LOOP;
  END IF;
  INSERT INTO _0825_selftest VALUES (jsonb_build_object('run_live', v_run, 'left_port_cars_asked', v_asked, 'offered_a_left_arm_post', v_offered));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0825_a_car_declined_for_its_charge_port_side_takes_the_kernels_own_post', true, false,
        'A proposal declined for the charge-port side is replaced by the kernel''s own fitting post in the same tick. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0825_selftest LIMIT 1), 'no result'), now());
COMMIT;

-- APPLIED 2026-11-13 at 05:42:56 UTC (2026-11-12, 11:42 PM CT), ledger 20261113054256, through apply_migration, on the
--   first send. Before it, the same statements ran once against the live engine inside a transaction that ended on a
--   raised exception (05:42 UTC): the anchor matched once, V1 held and the patched body compiled.
--   No run was live at the apply. V3 at apply: run_live null, left_port_cars_asked 0 (the structural checks held; the
--   proposer was not asked, since it reads the setting from a live run).
--   Stored after the apply, md5(prosrc): ottoq_decide_tick d09961121632e5374405eb51d7ab6ee7.
--   The first run under it is read in db/checks/0490.
