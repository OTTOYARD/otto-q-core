-- migration-version: 20261001233144
-- migration-name:    a_vehicle_card_names_each_steps_station_and_the_plan_it_replaced
--
-- 0592  **A vehicle card names each step's station, and the bookings OTTO-Q replaced on this visit.** Contract 1.5 of
--       `ottoq_depot_cards`: additive keys only, read-only.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-01, on the twin: "I just want each vehicle to be able to be tapped and a Q card to pop up and show its
--   list of completed and needed services and time frames for each and any progress meters", with each next step and
--   reservation checked off, and a future step re-assigned only before it begins. The Q card (ottoyarddepot-sim PR #131)
--   is drawn from this contract, and three things were not in it:
--     (a) WHERE each step is. A card's steps carry leg type, atom, status and times, but not the leg's station, so a
--         finished step shows no stall and an upcoming one only when a live booking or the snapshot's +-10 min leg
--         window happens to name it. Every leg already records it: ottoq_itinerary_legs.to_stall_id.
--     (b) WHAT OTTO-Q CHANGED. The card lists held and active bookings only, so a booking OTTO-Q replaced (superseded)
--         or let go before use (released) vanishes, and the cockpit can mark a re-assignment only from a feed row it
--         happens to have read. Every such booking is still in ottoq_stall_bookings, with its release_reason.
--     (c) HOW FAR BACK. Finished steps were cut at the newest three, so a long visit's first steps fell off the card.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_depot_cards`, contract 1.4 -> 1.5:
--     steps[]           each step also carries `to_stall_code` and `to_stall_kind`, its leg's to_stall_id resolved
--                       against stalls (absent when the leg names no stall: nulls are left null, as before).
--                       Finished steps: the newest TWELVE of the itinerary, was three.
--     plan_changes[]    per vehicle, beside `reservations`: this run's bookings for the car's CURRENT visit (the card's
--                       own need row's visit_id) that OTTO-Q superseded, or released before use for any reason but the
--                       run stopping. Each: purpose, need_atom, stall_code, stall_kind, starts_at, ends_at, state,
--                       release_reason, booked_at (sim). Oldest first, at most 12. Empty when there is no run, no need
--                       row, or nothing changed.
--   Nothing else moves; every 1.4 key is unchanged. ottoq_vehicle_card (its one caller besides the cockpits) passes it
--   through.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight (0513's probe). P1: the live body is exactly 0512's successor this file patches (md5).
--   Every patch must match its anchor exactly once, or the file refuses.
--   V1: the patched body compiles and, with no run at the depot, still returns its envelope (contract 1.5).
--   V2: the body names to_stall_code three times (done, current, upcoming) and plan_changes once.
--   Verified live on the first twin run after the apply (see MIGRATION_LOG).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: a cockpit read. Its callers are reads (ottoq_vehicle_card,
--   ottoq_t4_coverage) and no certified atom reads it.
--
-- ROLLBACK: restore public.ottoq_depot_cards from ottoq_schema_snapshots label '0592_pre' (CREATE OR REPLACE, ACL kept);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0592_a_vehicle_card_names_each_steps_station_and_the_plan_it_replaced'.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0592 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the body this file patches ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure)) <> '845156cf68af864f2de243e30af0f5b5' THEN
    RAISE EXCEPTION '0592 P1: public.ottoq_depot_cards is not the body this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0592_a_vehicle_card_names_each_steps_station_and_the_plan_it_replaced') THEN
    RAISE EXCEPTION '0592 P1: already applied';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0592_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure);
  v_pairs text[][] := ARRAY[
    -- (a) each step's station
    [$o1$'atom', l.duration_basis->>'atom', 'status', 'done',$o1$,
     $n1$'atom', l.duration_basis->>'atom', 'status', 'done',
        /* 1.5 (0592): the station this step is at */
        'to_stall_code', (SELECT st.stall_code FROM stalls st WHERE st.id = l.to_stall_id),
        'to_stall_kind', (SELECT st.stall_kind::text FROM stalls st WHERE st.id = l.to_stall_id),$n1$],
    [$o2$'atom', l.duration_basis->>'atom', 'status', 'current',$o2$,
     $n2$'atom', l.duration_basis->>'atom', 'status', 'current',
        'to_stall_code', (SELECT st.stall_code FROM stalls st WHERE st.id = l.to_stall_id),
        'to_stall_kind', (SELECT st.stall_kind::text FROM stalls st WHERE st.id = l.to_stall_id),$n2$],
    [$o3$'atom', l.duration_basis->>'atom', 'status', 'upcoming',$o3$,
     $n3$'atom', l.duration_basis->>'atom', 'status', 'upcoming',
        'to_stall_code', (SELECT st.stall_code FROM stalls st WHERE st.id = l.to_stall_id),
        'to_stall_kind', (SELECT st.stall_kind::text FROM stalls st WHERE st.id = l.to_stall_id),$n3$],
    -- (c) how far back
    [$o4$WHERE l.itinerary_id = c.itinerary_id AND l.status = 'done'
      ORDER BY l.seq DESC LIMIT 3)$o4$,
     $n4$WHERE l.itinerary_id = c.itinerary_id AND l.status = 'done'
      ORDER BY l.seq DESC LIMIT 12)$n4$],
    -- (b) what OTTO-Q changed on this visit
    [$o5$--: 0460 — the newest decision of THIS run per vehicle in scope.$o5$,
     $n5$--: 1.5 (0592) — this visit's bookings OTTO-Q replaced, or let go before use (not by the run stopping).
chg AS (
  SELECT x.vehicle_id,
         jsonb_agg(jsonb_build_object(
           'purpose', x.purpose, 'need_atom', x.need_atom, 'stall_code', x.stall_code, 'stall_kind', x.stall_kind,
           'starts_at', x.starts_at, 'ends_at', x.ends_at, 'state', x.state, 'release_reason', x.release_reason,
           'booked_at', x.booked_at_sim) ORDER BY x.booked_at_sim, x.booking_id) AS items
    FROM (
      SELECT b.vehicle_id, b.booking_id, b.purpose, b.need_atom, b.state, b.release_reason, b.booked_at_sim,
             lower(b.during) AS starts_at, upper(b.during) AS ends_at,
             st.stall_code, st.stall_kind::text AS stall_kind,
             row_number() OVER (PARTITION BY b.vehicle_id ORDER BY b.booked_at_sim DESC, b.booking_id DESC) AS rn
        FROM card c
        JOIN run r ON true
        JOIN ottoq_stall_bookings b ON b.sim_run_id = r.sim_run_id AND b.vehicle_id = c.vehicle_id
                                   AND b.visit_id = (c.need->>'visit_id')::uuid
        LEFT JOIN stalls st ON st.id = b.stall_id
       WHERE b.state = 'superseded'
          OR (b.state = 'released' AND COALESCE(b.release_reason, '') NOT LIKE '%run_stopped%')
    ) x
   WHERE x.rn <= 12
   GROUP BY x.vehicle_id
),
--: 0460 — the newest decision of THIS run per vehicle in scope.$n5$],
    [$o6$       'last_decision', dc.last_decision,$o6$,
     $n6$       'last_decision', dc.last_decision,
       'plan_changes', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN '[]'::jsonb
                            ELSE COALESCE(ch.items, '[]'::jsonb) END,$n6$],
    [$o7$     LEFT JOIN dec  dc    ON dc.vehicle_id = vh.id$o7$,
     $n7$     LEFT JOIN dec  dc    ON dc.vehicle_id = vh.id
     LEFT JOIN chg  ch    ON ch.vehicle_id = vh.id$n7$],
    [$o8$  'contract_version', '1.4',$o8$,
     $n8$  'contract_version', '1.5',$n8$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0592: cards patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ── V1: compiles and answers; V2: the keys are in the body ──
DO $verify$
DECLARE v_cards jsonb; v_def text := pg_get_functiondef('public.ottoq_depot_cards(uuid,uuid)'::regprocedure); n int;
BEGIN
  v_cards := public.ottoq_depot_cards('11111111-1111-1111-1111-111111111111'::uuid, NULL);
  IF v_cards->>'contract_version' IS DISTINCT FROM '1.5' THEN
    RAISE EXCEPTION '0592 V1: contract is %, not 1.5', v_cards->>'contract_version';
  END IF;
  n := (length(v_def) - length(replace(v_def, '''to_stall_code''', ''))) / length('''to_stall_code''');
  IF n <> 3 THEN RAISE EXCEPTION '0592 V2: to_stall_code appears % times, not 3', n; END IF;
  IF position('''plan_changes''' IN v_def) = 0 THEN RAISE EXCEPTION '0592 V2: plan_changes is missing'; END IF;
  RAISE NOTICE '0592: contract 1.5, % vehicles in the envelope', jsonb_array_length(v_cards->'vehicles');
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0592_a_vehicle_card_names_each_steps_station_and_the_plan_it_replaced', false, false,
  'Cockpit read only: ottoq_depot_cards contract 1.5. Each step carries to_stall_code/to_stall_kind (its leg''s '
  'to_stall_id), finished steps the newest 12 (was 3), and each vehicle plan_changes: this visit''s superseded bookings '
  'and those released before use other than by the run stopping. For the twin''s Q card (Chase, 2026-10-01). Callers are '
  'reads; no certified atom reads it.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
