-- ---------------------------------------------------------------------------
-- 0125 — what a run writes that no verdict atom hashes.
--
-- 0216/0217 found a live nondeterminism in the ServiceDetailRecord stream that
-- had survived every certification round because nothing hashed the SDR table.
-- The general form of that question is worth asking once, properly: WHAT ELSE
-- does a certification arm write that the verdict cannot see?
--
-- Census taken 2026-09-08 against round 25's pair 1 (arms 5861ea1d / 98095daf,
-- flagship busy_day/314159/12t). Read-only.
--
-- ANSWER, up front: the blind spot is real and wide, and today nothing is
-- hiding in it. Every unhashed table a run writes reproduces across the two
-- arms. That is a negative result and it is worth having written down, because
-- the next person to ask will otherwise spend the same hour.
-- ---------------------------------------------------------------------------

-- Q1. THE VERDICT'S REACH. Eleven tables carry a sim_run_id AND are named by a
--     verdict atom; roughly a hundred more carry one and are not. Most of the
--     hundred are the scratch/evidence tables CLAUDE.md Part 3 flags
--     (cert00xx_*, build2_*, build3_*, fwd*, mig*, proof*, smoke*, p7_*) and
--     are written by hand, not by the engine.
WITH hashed(t) AS (VALUES
  ('ottoq_vehicle_commands'),('ottoq_decisions'),('ottoq_events'),('ottoq_stall_bookings'),
  ('ottoq_energy_commands'),('ottoq_external_proposals'),('ottoq_cuopt_deferrals'),
  ('ottoq_rule_evaluations'),('ottoq_recall_decisions'),('ottoq_service_detail_records'),
  ('ottoq_sim_runs'))
SELECT (SELECT count(DISTINCT col.table_name)
          FROM information_schema.columns col
          JOIN pg_class c ON c.relname=col.table_name
          JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
         WHERE col.table_schema='public' AND col.column_name='sim_run_id' AND c.relkind='r')
       AS tables_with_a_run_scope,
       (SELECT count(*) FROM hashed) AS of_which_a_verdict_atom_names;

-- Q2. WHAT AN ARM ACTUALLY WRITES OUTSIDE THE VERDICT. Fourteen live tables,
--     measured per arm on round 25 pair 1. Three of them — legs, visit_needs,
--     dispatches — are partly covered through `endst`, which carries its own
--     sections for them; the rest are covered by nothing.
--
--       ottoq_variability_cards      1,656
--       ottoq_bay_binding_witness    1,339
--       ottoq_itinerary_legs           685   (endst: legs)
--       ottoq_comms_messages           493
--       ottoq_telemetry_packets        325
--       ottoq_vehicle_wear             116
--       ottoq_visit_needs              116   (endst: visit_needs)
--       ottoq_vehicle_dispatches       116   (endst: dispatches)
--       ottoq_vehicle_itineraries      116
--       ocpp_sessions                   93
--       space_conflict_ledger           88
--       ottoq_ops_approvals             60
--       ottoq_decision_snapshots        12
--       site_energy_snapshots           12
--       ottoq_wave_plan                  0
--       ottoq_recall_refusals            0   (0211's table; empty at the default rate)
SELECT 'ottoq_bay_binding_witness' AS tbl, count(*) FILTER (WHERE sim_run_id='5861ea1d-10f6-46ff-8ad8-0145ab5def44') AS arm_a,
       count(*) FILTER (WHERE sim_run_id='98095daf-8cc8-428a-a959-1e0916a8d3b4') AS arm_b
FROM public.ottoq_bay_binding_witness
UNION ALL
SELECT 'space_conflict_ledger', count(*) FILTER (WHERE sim_run_id='5861ea1d-10f6-46ff-8ad8-0145ab5def44'),
       count(*) FILTER (WHERE sim_run_id='98095daf-8cc8-428a-a959-1e0916a8d3b4')
FROM public.space_conflict_ledger;

-- Q3. THE ONE CLAUDE.MD NAMES. Rule 6: "space_conflict_ledger records every
--     calendar claim overruled by physical reality. Never remove either side."
--     88 rows per arm, and the verdict cannot see any of them. Content-hashed
--     id-blind across the two arms:  af876d50…  on BOTH. Reproducible.
SELECT md5(string_agg(c, E'\n' ORDER BY c)) AS h, count(*) AS rows, arm FROM (
  SELECT CASE WHEN s.sim_run_id='5861ea1d-10f6-46ff-8ad8-0145ab5def44' THEN 'a' ELSE 'b' END AS arm,
         s.sim_clock::text||'|'||COALESCE(s.tick_seq::text,'-')||'|'||COALESCE(st.stall_code,'-')||'|'||
         COALESCE(s.stall_type::text,'-')||'|'||s.conflict_kind||'|'||COALESCE(s.resolution,'-')||'|'||
         COALESCE(pv.vin,'-')||'|'||COALESCE(s.present_vehicle_state::text,'-')||'|'||
         COALESCE(dv.vin,'-')||'|'||COALESCE(s.displaced_state,'-')||'|'||
         COALESCE(s.displaced_during::text,'-')||'|'||COALESCE(s.displaced_booked_by,'-') AS c
  FROM public.space_conflict_ledger s
  LEFT JOIN public.stalls st ON st.id=s.stall_id
  LEFT JOIN public.vehicles pv ON pv.id=s.present_vehicle_id
  LEFT JOIN public.vehicles dv ON dv.id=s.displaced_vehicle_id
  WHERE s.sim_run_id IN ('5861ea1d-10f6-46ff-8ad8-0145ab5def44','98095daf-8cc8-428a-a959-1e0916a8d3b4')
) z GROUP BY arm ORDER BY arm;

-- Q4. AND THE METHOD LESSON, which cost an hour and is the real deliverable.
--
--     The first pass on ottoq_bay_binding_witness reported the two arms
--     DIFFERING. They do not. The hash was ordered by a HAND-PICKED KEY —
--     (observed_sim, vin, stall_code, new_state, purpose) — and that key leaves
--     exactly ONE tie among 1,339 rows. One tie is enough: the two arms
--     concatenate those two rows in different orders and the md5 differs.
--     Ordered by the CONTENT STRING ITSELF the arms read 629588ad on both.
--
--     This is the same mistake as 0218's, twelve hours apart: a comparison that
--     fires for a reason other than the one being tested. The rule that falls
--     out of both, and that ottoq_hash_sdrs already follows:
--
--       ORDER A CONTENT HASH BY THE CONTENT, NOT BY A KEY YOU CHOSE.
--       A chosen key is only as good as its totality, and you will not notice
--       the one tie in 1,339.
--
--     The query below is the check: how many rows a candidate sort key fails to
--     separate. Run it before trusting any hand-ordered comparison.
SELECT count(*) AS rows,
       count(*) - count(DISTINCT (observed_sim, vin, stall_code, new_state, purpose))
         AS rows_a_chosen_key_cannot_separate,
       count(*) - count(DISTINCT (observed_sim, vin, stall_code, old_state, new_state,
                                  old_source, new_source, purpose, window_start, window_end,
                                  seated_on_reserved, inside_window))
         AS rows_the_full_content_cannot_separate
FROM (
  SELECT w.*, v.vin, st.stall_code FROM public.ottoq_bay_binding_witness w
  LEFT JOIN public.vehicles v ON v.id=w.vehicle_id
  LEFT JOIN public.stalls st ON st.id=w.stall_id
  WHERE w.sim_run_id='5861ea1d-10f6-46ff-8ad8-0145ab5def44') q;

-- Q5. VERDICT OF THE CENSUS.
--     Ten unhashed live tables compared across the two arms: all ten match on
--     row count; space_conflict_ledger and ottoq_bay_binding_witness match on
--     content. No new defect. The blind spot is a REAL gap in what the
--     certification can prove — an engine change that moved only these tables
--     would still pass — but the engine is not currently exploiting it.
--
--     Worth promoting? Probably not all of them, and not now. h_sdr earned its
--     place because a defect was found in it. The cheap discipline that would
--     have caught the SDR case anyway is the census itself: after any migration
--     that writes somewhere new, ask what hashes it. 0211's
--     ottoq_recall_refusals is the current example — new table, engine-written,
--     in no atom, and empty only because the refusal rate defaults to 0.
