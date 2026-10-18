-- migration-version: 20261018113640
-- migration-name:    a_bay_seat_that_finished_early_is_done
--
-- 0757  **A bay seat that finished early is done.** (G474)
--       The bay release judges an active bay booking by its booked minutes alone: a car that left its bay before 80% of
--       its booked window, and at least 2 minutes early, is filed interrupted, and the booking purpose's atoms are reopened,
--       done ones included. But the only exit that credits bay work is the service flow's STEP 1, which lets a car out
--       when its timer has run out or a completion was reported; a bay fault or a vehicle exception moves a car out by its
--       own handler and credits nothing. So an early STEP 1 exit is work that took less time than its booking, and the
--       release undid it: the car was sent back for work it had had. Under a dial, a seat the service flow completed is
--       done however early, and a seat still filed interrupted no longer reopens what the service flow credited. The
--       robotic wash cells and the uptime-first cells carry the dial from their first arm.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 between 4:15 and 4:27 AM CT and between 4:31 and 4:45 AM CT; db/checks/0451
--      §20, queries (42)-(45)) ═════════════════════════════════════════════════════════════════════════════════════════
--
--   2d2c46af on arm 82, seated in a service bay at 2:00 PM CT sim for its mechanical PM, left it at 2:35 on its timer and
--   was credited the PM (twin.service_completed, credited [mechanical_pm], not on a null timer). In the same tick
--   ottoq.ottoq_release_vacated_spaces closed its booking (48 minutes booked, 35.5 held) as interrupted,
--   'bay_exit_before_planned_end', and public.ottoq_reopen_visit_atoms set the PM back to open. The departure recheck sent
--   the car back at 2:40, and it waited the 3 hours 20 minutes left of the run for a PM it had had. On arms 82-97 the
--   release filed 10 bookings interrupted, each in the tick the service flow let the car out with work credited, none on
--   a null timer: 9 service bookings (57.9 minutes booked and 41.1 held on average, 0.52-0.79 of the window) and 1 detail
--   booking (arm 88) whose car the twin had seated in a wash bay 2.4 minutes before the booking's window began, and which
--   left it with an exterior wash credited. The test this file adds, read against those ten on the live rows (query (45)),
--   finds the completion for the 9 service bookings and not for the detail booking, whose wash bay cannot do a detail.
--   That car was washed, though, and the release reopened the wash it had just had (atoms_reopened 1) while its detail's
--   interior work was still to do.
--
--   And it waits for 0746. Its robotic lanes (wash_lane_physics 2) time a seat by the work and keep the engine's
--   bookings, 9.0 minutes for a wash and 25.0 for a detail in tick (query (43)). A robotic wash takes 4.25-5.75 minutes,
--   so one drawn at or under 5.0 leaves at the next 5-minute tick, at 56% of its booking, and is reopened; a robotic detail
--   takes 13.2-19.8, so one at or under 15.0 leaves at 60% and is reopened. By the twin's deals on arms 82-97 (3,266 wash
--   and 3,278 detail cards, drawn on 0.7-1.3) that is 53% of robotic washes and 25% of robotic details, each sent back
--   for work it had had, up to the reopen cap of three: the robowash and uptime-first arms would measure robotic lanes
--   doing about half again as many washes as their cars need. Production meets it the day a robot or a technician reports
--   work done before 80% of its booked window.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   The dial bay_release_reads_the_work (0 or 1, default 0, not agent-writable). With it on, in the release's calendar
--   step (c), an active bay booking the booked-minutes test calls interrupted is done instead when its car has a
--   twin.service_completed in the run since the booking began (sim_clock_at in (lower(during), clock]), recorded no
--   earlier than the booking was made (occurred_at >= booked_at, which keeps the read to the index's range for the car),
--   not on a null timer (self_healed), out of a bay whose capability set holds every atom of the booking's purpose
--   (ottoq.ottoq_bay_purpose_atoms; a wash bay cannot finish a detail). Such a booking closes as any done seat does
--   ('bay_exit_transition', its window clipped to the exit), and its why says the minutes it held against the minutes
--   booked. Nothing is reopened and no booking_interrupted is emitted; the seat's legs were closed by STEP 1 at the exit.
--   A seat with no such completion (a bay fault, a vehicle exception, a null timer, a bay that cannot do the booking's
--   work) is judged by its booked minutes as before. And a booking still filed interrupted reopens only the atoms of its
--   purpose that no such completion credited (the same test, on the event's credited list): arm 88's detail booking
--   stays interrupted, its interior work stays due and its bound leg is re-planned, and the exterior wash the wash bay did
--   stays done. At 0 neither read is run and every booking is judged and reopened as before.
--
--   Rule 9 holds either way. STEP 1 credits only what its bay can do and the car still had to do, so a seat filed done
--   here leaves every atom it did not credit open, and the departure test (0543) holds a car with any open: the dial can
--   stop done work from being done again, never let work go undone.
--
--   The cells: every cell of robowash_normal_2026_10_18 (4) and uptimefirst_busy_2026_10_18 (2), the controls included,
--   carries bay_release_reads_the_work 1 from its first arm, so each contrast stands on one release. Their first cells are
--   therefore no longer exactly arm 84's cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) and the busy sweep's first
--   cell: a service seat the twin's own minutes ended early is done there, not reopened. Compare across sweeps with that
--   in hand.
--
--   Not changed: the booked-minutes test itself (ottoq.ottoq_booking_interrupted and its other callers), the reopen
--   itself (0757 changes what the release asks it to reopen, not how), a held booking's no-show grace, phases (a) and (b), the activation and the departed-space release. In production
--   STEP 1 lets a car out on a reported completion (service_done) and emits the same event, so the dial would read a
--   reported early finish as done; it is off there, and turning it on is a certified change.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the release is the body read (prosrc ec00f541); the service flow emits twin.service_completed
--   once, with 'self_healed' its null timer and 'bay_capable' its bay's set, and its three capability sets are the ones
--   this file compares with; no other function names the event as a string (public.ottoq_sim_release_depot names it in a
--   comment); ottoq.ottoq_bay_purpose_atoms is the body read (84bc5c36); ottoq_stall_bookings.booked_at defaults to
--   now(); 0746 and 0747 are applied, their two sweeps hold 4 and 2 cells and no arm, and the dial is nowhere yet. P2 not
--   already applied. Pre-image to ottoq_schema_snapshots as '0757_pre'. Each anchor matches once. V1 the body less its
--   changes is its pre-image. V2 the dial is catalogued as declared and no parameter row sets it. V3 the six cells carry
--   it and are otherwise as they were. No probe calls the release on live: its phases (a) and (b) write the depot's
--   vehicles and stalls whatever the run. tests/test_bay_release_reads_the_work_sql.py runs this file on the scratch
--   PostgreSQL against the live release and everything it calls (md5 asserted): 2d2c46af's seat before and after it, at
--   the default and with the dial; a robotic wash done in 5 of 9 booked minutes; a seat with no completion, on a null
--   timer, before the booking began, in another run, or recorded before the booking was made, each judged and reopened
--   as before; arm 88's detail booking from a wash bay, interrupted with its wash left done and its interior work due
--   (and at the default, its wash reopened as on arm 88); a full seat and a no-show unchanged; V1, P1 and P2.
--   The read fails safe: if the event were ever stamped otherwise, it would find nothing and the seat would be judged by
--   its booked minutes, as today.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at the default the release decides exactly as before (V1; the read is not run), and no
--   certification pair, canon cell or dial experiment sets the dial. forces_dial_restart FALSE for the same reason, and
--   because moving the dial floor re-queues every active sweep's cells. The six cells are the research wing's, set before
--   their first arm (P1 refuses otherwise).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0757_pre'; if no arm of the two sweeps has
--   run, UPDATE their cells SET fixed_params = fixed_params - 'bay_release_reads_the_work'; DELETE the dial's catalog row;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0757_a_bay_seat_that_finished_early_is_done'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0757 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the release, the event it will read, and the cells, as read ──
DO $p1$
DECLARE v_flow text;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_release_vacated_spaces(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'ec00f54181136bc0b6d4d34a1129f096' THEN
    RAISE EXCEPTION '0757 P1: ottoq.ottoq_release_vacated_spaces is not the body read (md5 ec00f541)';
  END IF;
  SELECT prosrc INTO v_flow FROM pg_proc
   WHERE oid = to_regprocedure('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)');
  IF v_flow IS NULL
     OR (length(v_flow) - length(replace(v_flow, 'twin.service_completed', ''))) / length('twin.service_completed') <> 1
     OR position($s1$p_event_type := 'twin.service_completed',
      p_entity_type := 'vehicle', p_entity_id := v_rec.id, p_payload := jsonb_build_object('from', v_rec.current_state, 'self_healed', (v_rec.config->>'service_ends_at') IS NULL,$s1$ IN v_flow) = 0
     OR position($s2$'bay_capable', to_jsonb(v_bay_caps), 'credited', to_jsonb(v_credit),$s2$ IN v_flow) = 0
     OR position($s3$    v_bay_caps := CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
                       WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
                       ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END;
$s3$ IN v_flow) = 0 THEN
    RAISE EXCEPTION '0757 P1: the service flow does not emit twin.service_completed as read (once, self_healed its null timer, bay_capable its bay''s set)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE position($q$'twin.service_completed'$q$ IN p.prosrc) > 0
                AND p.oid IS DISTINCT FROM to_regprocedure('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)')) THEN
    RAISE EXCEPTION '0757 P1: a function other than the service flow names twin.service_completed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('ottoq.ottoq_bay_purpose_atoms(text)'))
     IS DISTINCT FROM '84bc5c3630789622deecabd563636051' THEN
    RAISE EXCEPTION '0757 P1: ottoq.ottoq_bay_purpose_atoms is not the body read (md5 84bc5c36)';
  END IF;
  IF (SELECT pg_get_expr(d.adbin, d.adrelid)
        FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
       WHERE d.adrelid = 'public.ottoq_stall_bookings'::regclass AND a.attname = 'booked_at')
     IS DISTINCT FROM 'now()' THEN
    RAISE EXCEPTION '0757 P1: ottoq_stall_bookings.booked_at does not default to now()';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_cert_lineage
       WHERE name IN ('0746_robotic_wash_lanes_and_bay_work_timed_by_the_work',
                      '0747_the_bay_line_serves_the_car_that_rejoins_service_soonest')) <> 2 THEN
    RAISE EXCEPTION '0757 P1: 0746 and 0747 are not both applied';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'robowash_normal_2026_10_18') <> 4
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code = 'uptimefirst_busy_2026_10_18') <> 2 THEN
    RAISE EXCEPTION '0757 P1: the robowash and uptime-first sweeps are not their 4 and 2 cells';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code IN ('robowash_normal_2026_10_18', 'uptimefirst_busy_2026_10_18')) THEN
    RAISE EXCEPTION '0757 P1: an arm of the robowash or uptime-first sweep has run, so their cells cannot change';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code IN ('robowash_normal_2026_10_18', 'uptimefirst_busy_2026_10_18')
                AND c.fixed_params ? 'bay_release_reads_the_work')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_release_reads_the_work')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'bay_release_reads_the_work') THEN
    RAISE EXCEPTION '0757 P1: the dial bay_release_reads_the_work already exists';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0757_a_bay_seat_that_finished_early_is_done') THEN
    RAISE EXCEPTION '0757 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0757_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_release_vacated_spaces(uuid,uuid,timestamp with time zone)'::regprocedure;

-- ── the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_release_reads_the_work',
        '0757 (G474): 1 = the bay release files an active bay booking done, however early its car left, when the service '
        'flow let the car out with its work done: a twin.service_completed for the car since the booking began, not on a '
        'null timer, out of a bay that does every atom of the booking''s purpose. Its why says the minutes it held against '
        'the minutes booked, and nothing is reopened. A seat with no such completion is judged by its booked minutes. 0 = '
        'every active bay booking judged by its booked minutes, as before 0757. Research days only until certified.',
        0, 0, 1, 'ottoq.ottoq_release_vacated_spaces (c)', false);

-- ── the release: a seat the service flow completed is judged by its work, and what it credited stays done ──
CREATE TEMP TABLE _0757_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0757_patch VALUES
  -- 1: the dial's variable
  (1, $o1$        v_activated int := 0;
BEGIN
$o1$,
   $n1$        v_activated int := 0;
        v_reads_work boolean := false;   -- 0757 (G474): bay_release_reads_the_work
BEGIN
$n1$),
  -- 2: the dial, read with the run's other settings
  (2, $o2$  v_leg_cap := GREATEST(public.ottoq_policy_get(p_sim_run_id,'leg_replan_max_attempts',3)::int, 0);
$o2$,
   $n2$  v_leg_cap := GREATEST(public.ottoq_policy_get(p_sim_run_id,'leg_replan_max_attempts',3)::int, 0);
  -- 0757 (G474): with bay_release_reads_the_work on, (c) judges a seat the service flow completed by its work, not by
  -- its booked minutes.
  v_reads_work := COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_release_reads_the_work',0),0) >= 1;
$n2$),
  -- 3: the candidate's car and when its booking was made
  (3, $o3$      SELECT b.booking_id, b.state AS old_state, b.purpose,
$o3$,
   $n3$      SELECT b.booking_id, b.state AS old_state, b.purpose,
             b.vehicle_id AS car, b.booked_at AS booked,   -- 0757
$n3$),
  -- 4: the verdict reads the work, and the booked-minutes test is kept for the note
  (4, $o4$                         THEN 'interrupted' ELSE 'done' END
                  ELSE 'released' END                        AS new_state
$o4$,
   $n4$                          -- 0757 (G474): a seat the service flow completed is not judged by its booked minutes.
                          -- The completion is the car's twin.service_completed in this run since the booking began,
                          -- recorded no earlier than the booking was made, not on a null timer, out of a bay whose
                          -- capability set holds every atom of the booking's purpose. Only that exit credits work: a
                          -- bay fault or a vehicle exception moves a car out by its own handler. Off, this is not run.
                          AND NOT (CASE WHEN v_reads_work THEN EXISTS (
                                     SELECT 1 FROM public.ottoq_events e
                                      WHERE e.entity_type = 'vehicle' AND e.entity_id = c.car
                                        AND e.occurred_at >= c.booked
                                        AND e.sim_run_id = p_sim_run_id
                                        AND e.event_type = 'twin.service_completed'
                                        AND e.sim_clock_at > c.lo AND e.sim_clock_at <= p_clock
                                        AND NOT COALESCE((e.payload ->> 'self_healed')::boolean, false)
                                        AND cardinality(ottoq.ottoq_bay_purpose_atoms(c.purpose)) > 0
                                        AND (e.payload -> 'bay_capable') @> to_jsonb(ottoq.ottoq_bay_purpose_atoms(c.purpose)))
                                   ELSE false END)
                         THEN 'interrupted' ELSE 'done' END
                  ELSE 'released' END                        AS new_state,
             -- 0757: the booked-minutes test alone, for the note a seat done early carries
             (c.old_state = 'active'
              AND ottoq.ottoq_booking_interrupted(
                    c.purpose,
                    EXTRACT(epoch FROM (c.hi - c.lo))::numeric,
                    EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric)) AS cut_short
$n4$),
  -- 5: a seat done early says so
  (5, $o5$                                ELSE                    'no_show_grace_elapsed' END,
$o5$,
   $n5$                                ELSE                    'no_show_grace_elapsed' END,
             why            = CASE WHEN v_reads_work AND d.new_state = 'done' AND d.cut_short   -- 0757
                                   THEN concat_ws(' | ', NULLIF(b.why, ''),
                                          format('0757: the service flow completed the work; held %s of %s booked minutes',
                                                 round(d.actual_s / 60.0, 1), round(d.planned_s / 60.0, 1)))
                                   ELSE b.why END,
$n5$),
  -- 6: the interrupted row carries when its booking was made
  (6, $o6$      RETURNING b.booking_id, b.vehicle_id, b.stall_id, b.purpose,
                d.lo, d.planned_s, d.actual_s, d.new_state
$o6$,
   $n6$      RETURNING b.booking_id, b.vehicle_id, b.stall_id, b.purpose,
                d.lo, d.planned_s, d.actual_s, d.new_state,
                d.booked   -- 0757
$n6$),
  -- 7: an interrupted seat reopens only what the service flow did not credit
  (7, $o7$                    ottoq.ottoq_bay_purpose_atoms(v_rec.purpose),
$o7$,
   $n7$                    CASE WHEN v_reads_work
                         -- 0757 (G474): work the service flow credited since the booking began, not on a null
                         -- timer, stays done: a wash bay that washed a car booked for a detail did wash it.
                         THEN ARRAY(SELECT x.svc FROM unnest(ottoq.ottoq_bay_purpose_atoms(v_rec.purpose)) AS x(svc)
                                     WHERE NOT EXISTS (
                                       SELECT 1 FROM public.ottoq_events e
                                        WHERE e.entity_type = 'vehicle' AND e.entity_id = v_rec.vehicle_id
                                          AND e.occurred_at >= v_rec.booked
                                          AND e.sim_run_id = p_sim_run_id
                                          AND e.event_type = 'twin.service_completed'
                                          AND e.sim_clock_at > v_rec.lo AND e.sim_clock_at <= p_clock
                                          AND NOT COALESCE((e.payload ->> 'self_healed')::boolean, false)
                                          AND (e.payload -> 'credited') ? x.svc))
                         ELSE ottoq.ottoq_bay_purpose_atoms(v_rec.purpose) END,
$n7$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_release_vacated_spaces(uuid,uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0757_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0757: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('ottoq.ottoq_release_vacated_spaces(uuid,uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0757: the release is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its changes is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_release_vacated_spaces(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0757_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'ec00f54181136bc0b6d4d34a1129f096' THEN
    RAISE EXCEPTION '0757 V1: the release less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── the cells: the two sweeps' six, controls included, before their first arm ──
CREATE TEMP TABLE _0757_cells ON COMMIT DROP AS
SELECT c.cell_id, c.fixed_params
  FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
 WHERE s.sweep_code IN ('robowash_normal_2026_10_18', 'uptimefirst_busy_2026_10_18');
UPDATE public.ottoq_throughput_sweep_cells c
   SET fixed_params = c.fixed_params || '{"bay_release_reads_the_work": 1}'::jsonb
  FROM _0757_cells k
 WHERE k.cell_id = c.cell_id;

-- ── V2: the dial, as declared; V3: the six cells carry it and nothing else moved ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'bay_release_reads_the_work' AND NOT COALESCE(agent_writable, false)
         AND (default_value, min_value, max_value) = (0, 0, 1)) <> 1
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'bay_release_reads_the_work') THEN
    RAISE EXCEPTION '0757 V2: the dial is not catalogued as declared, or a parameter row sets it';
  END IF;
  IF (SELECT count(*) FROM _0757_cells) <> 6
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN _0757_cells k USING (cell_id)
          WHERE c.fixed_params ->> 'bay_release_reads_the_work' = '1'
            AND c.fixed_params - 'bay_release_reads_the_work' = k.fixed_params) <> 6 THEN
    RAISE EXCEPTION '0757 V3: the six cells do not carry the dial as declared';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0757_a_bay_seat_that_finished_early_is_done', false, false,
        'G474. Dial bay_release_reads_the_work (default 0). ottoq.ottoq_release_vacated_spaces, seven anchored changes: '
        'with the dial, (c) files an active bay booking done, however early its car left, when the car has a '
        'twin.service_completed in the run since the booking began, not on a null timer, out of a bay that does the '
        'booking''s work, and its why notes the minutes held against the minutes booked; any other early exit is judged '
        'by its booked minutes as before, and reopens only what the service flow did not credit since the booking began. '
        'At 0 the read is not run (V1: body less changes is its pre-image). Cells: '
        'robowash_normal_2026_10_18 (4) and uptimefirst_busy_2026_10_18 (2), controls included, before their first arm. '
        'No certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:36:40 UTC (6:36 AM CT), ledger version 20261018113640 ══════════════════════════════════════
--
--   Dry-run first on live, read at 11:35:53 UTC (6:35 AM CT): the executable part in one execute_sql ending in a block
--   that raises, so it rolled back. Every premise and check passed; the release after it read
--   0f666b832925fd0cd53c5fab1c827883 and the six cells carried the dial. Then through apply_migration after 0746, 0747
--   and 0756, with no arm of either sweep run and nothing in flight (the file's own P0 at the apply; no run live, read
--   at 11:36:47 UTC). The text sent, BEGIN through COMMIT and one newline, is 16,105 characters, md5
--   8cb724bb63122d6ed8f44634eb46264f, equal to the ledger's statements[1] read back; its executable part is 16,089
--   characters, md5 0449e02e8cb864d76a10e307f0a44abe, equal to this file's. ottoq.ottoq_release_vacated_spaces is now
--   md5 0f666b832925fd0cd53c5fab1c827883 (prosrc), the body tests/test_bay_release_reads_the_work_sql.py pins in its
--   test world, and carries v_reads_work; the four cells of robowash_normal_2026_10_18 and the two of
--   uptimefirst_busy_2026_10_18 carry bay_release_reads_the_work 1. Nothing here or after it called the release on live.
