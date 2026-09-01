-- 0060: the verdict never looked at the end state
--
-- Round 6. Started as routine matrix-reading and turned into an instrument finding.
--
-- ============================================================================
-- 1. WHAT THE MATRIX SHOWS (r9, 6 of 12 pairs landed at the time of writing)
-- ============================================================================
--
--   scenario   seed/ticks   pairs   fp        h_cmd     h_dec     h_evt     h_bkg
--   busy_day   171717/12t     3     823cd34d  f87f71de  fe36c5fb  d08ececc  b94ca1f8
--   busy_day   314159/12t     3     b2701577  f247a07e  2019771f  56b98454  7f1abbed
--
-- All six pairs equal=true, and -- this is the part that is new -- every hash is identical
-- ACROSS pairs, not merely within them. Six independent arms of 171717/12t and six of
-- 314159/12t agree byte for byte on the world fingerprint and all four decision streams.
-- That is inter-pair reproducibility, which is a strictly stronger claim than the 0131
-- green bar (which only ever asserted the two arms of one pair agree).
--
-- Remaining: c1-c3 (171717/24t) and d1-d3 (424242/24t) run through 01:46.
--
-- A note on labels: 0058 called canon 823cd34d "normal_day 171717/12t". It is also the
-- busy_day 171717/12t fingerprint. Not an error in either place -- `fp` is the BOOT world
-- image, and boot is a function of (depot, seed) alone, because ottoq_tick_invariance_reset_fleet
-- takes exactly those two arguments. The scenario changes what happens next, and it plainly
-- does: at the same seed, normal_day and busy_day share fp 823cd34d and differ in all four
-- streams (e605d4c6/f24724eb/2c80aa69/a88de84f vs f87f71de/fe36c5fb/d08ececc/b94ca1f8).
-- The scenario library is live, not decorative. But `fp` alone does not identify a column.
--
-- ============================================================================
-- 2. THE FINDING: a captured value that is never compared
-- ============================================================================
--
-- ottoq_determinism_pair computes, per arm:
--     fp, boot, endst, h_cmd, h_dec, h_evt, h_bkg, ticks
-- and its verdict is:
--     fp AND h_cmd AND h_dec AND h_evt AND h_bkg AND ticks
--
-- `endst` -- the end-of-run world image -- is captured on both arms, stored in the verdict
-- json, written to both run rows, and never looked at. Any divergence in world state that
-- the four streams do not cover passes silently.
--
-- It is not hypothetical. endst differed in 9 of the 9 most recent pairs. All 9 PASSED.
--
--   pair    scenario/seed        boot equal   endst equal
--   23:17   normal_day 171717    true         FALSE
--   23:25   normal_day 171717    true         FALSE
--   23:33   busy_day   424242    true         FALSE
--   23:41   busy_day   424242    true         FALSE
--   23:56   busy_day   171717    true         FALSE
--   00:04   busy_day   171717    true         FALSE
--   00:12   busy_day   171717    true         FALSE
--   00:20   busy_day   314159    true         FALSE
--   00:28   busy_day   314159    true         FALSE
--
-- ============================================================================
-- 3. METHOD NOTE -- an unpaired diff lies, and it lied to me first
-- ============================================================================
--
-- First probe of ottoq_vehicle_dispatches.return_evidence used EXCEPT ALL on the raw
-- multiset. It reported 82 of 116 rows differing and produced this pair of samples:
--
--   arm A   {"soc": 81.899..., "inbound": 58, "reserve": 15, "wait_ticks": 1, ...}
--   arm B   {"soc": 84.754..., "inbound": 37, "reserve": 20, "wait_ticks": 0, ...}
--
-- Read at face value that is a catastrophic finding: the recall decision seeing a different
-- world at the same sim clock. It is also entirely false. EXCEPT ALL returns unmatched
-- multiset members in arbitrary order, so those two rows are DIFFERENT VEHICLES. Re-run
-- paired on vehicle_id, across all 116 dispatches and all 35 evidence keys:
--
--   soc, soc_at_decision, inbound, reserve, wait_ticks, free_chargers, burn_guard,
--   deploy_floor, currently_deployed, desired_deployed, eta_min, eta_source, lead_min,
--   live_return_at, planned_return_at, plan_minus_live_min, reserve_margin, reserved_by_bias,
--   worst_dtc_rank, strata, stratum, slot, soil, boot_prime, hour_local, hour_cst, reason,
--   decided_at, arrives_in_min, target_absent_from_loop, eta_minutes_is_a_parameter,
--   rider_flag_kind, rider_flag_raised_at, why            -> 0 differences, every one
--   appointment                                           -> 82 of 82 differ
--
-- and inside `appointment`, of its ten keys -- charger_class, command_type, has_charge,
-- plan_total_min, projected_ready_at, secured, stall_id, stall_type, ttl_s, correlation_id --
-- only correlation_id differs. It is a per-run random uuid.
--
-- Rule, joining "probe the columns the check hashes, not the row" (0057):
--   PAIR THE ROWS BEFORE YOU BELIEVE THE DIFF. An unpaired multiset diff cannot tell a
--   changed value from a reordered one, and it will hand you a sample pair that reads
--   like a five-alarm defect.
--
-- ============================================================================
-- 4. ROOT CAUSE: three identity fields, no behavioural divergence anywhere
-- ============================================================================
--
-- Same method applied to ottoq_stall_bookings, 1064 rows per arm, column by column:
--
--   DIFF: booking_id, decision_id, leg_id, sim_run_id, visit_id, why
--   same: during, purpose, stall_id, vehicle_id, state, need_code, need_atom, need_source,
--         release_reason, released_at, source, booked_by, booked_at, booked_at_sim,
--         leg_source, decision_link
--
-- booking_id/decision_id/leg_id/sim_run_id are already stripped by the fingerprint.
-- The two that are not:
--   visit_id -- a per-run FK the strip list forgot.
--   why      -- renders a leg id into prose: "leg fc215503 (inspect, matched caller)" in
--               arm A against "leg 780826fe (inspect, matched caller)" in arm B. 406 of
--               1064 rows. Every other word identical.
--
-- So the entire 9-for-9 endst divergence is three uuid-bearing fields. Not one behavioural
-- column, in either table, in any pair, differs. The instrument was failing, not the engine.
--
-- ============================================================================
-- 5. THE FIX (0139) AND ITS PROOF, MEASURED BEFORE THE MIGRATION WAS WRITTEN
-- ============================================================================
--
-- Strip visit_id; scrub uuids and bare 8-hex id prefixes out of why; drop
-- appointment.correlation_id from return_evidence. Then put endst in the verdict.
--
-- Proven read-only against the stored 00:12 arms (952421ec / f3451a24):

WITH scrub AS (
  SELECT sim_run_id,
         md5((to_jsonb(t) - 'booking_id' - 'sim_run_id' - 'decision_id' - 'leg_id' - 'visit_id'
              - 'booked_at' - 'created_at' - 'updated_at' - 'why')
             || jsonb_build_object('why',
                  regexp_replace(
                    regexp_replace(t.why, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', 'g'),
                    '\m[0-9a-f]{8}\M', '<id8>', 'g'))
            ::text) AS h
    FROM public.ottoq_stall_bookings t
   WHERE sim_run_id IN ('952421ec-5e75-4342-be42-5d2c14d5972d','f3451a24-4dad-4d42-a385-4a9d366708d2'))
SELECT sim_run_id, count(*) AS n, md5(string_agg(h,'' ORDER BY h)) AS rollup
FROM scrub GROUP BY sim_run_id;
--   952421ec  1064  78ccd4b3621aad83037735f06eb63553
--   f3451a24  1064  78ccd4b3621aad83037735f06eb63553      <- equal

WITH scrub AS (
  SELECT sim_run_id,
         md5(((to_jsonb(t) - 'dispatch_id' - 'sim_run_id' - 'created_at' - 'return_evidence')
              || jsonb_build_object('return_evidence',
                   t.return_evidence #- '{appointment,correlation_id}'))::text) AS h
    FROM public.ottoq_vehicle_dispatches t
   WHERE sim_run_id IN ('952421ec-5e75-4342-be42-5d2c14d5972d','f3451a24-4dad-4d42-a385-4a9d366708d2'))
SELECT sim_run_id, count(*) AS n, md5(string_agg(h,'' ORDER BY h)) AS rollup
FROM scrub GROUP BY sim_run_id;
--   952421ec  116  8682d29edaaa0d7534019d3f32fa569d
--   f3451a24  116  8682d29edaaa0d7534019d3f32fa569d       <- equal

-- The 8-hex rule is the one piece of this that could over-reach: it could collapse a fact
-- that happens to look like an id. Checked against the leg table -- every token it matches
-- in these two arms is a real leg-id prefix, none is anything else:

SELECT count(*) AS tokens_matched,
       count(DISTINCT tok) AS distinct_tokens,
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.ottoq_itinerary_legs l WHERE l.leg_id::text LIKE tok||'%')
       ) AS not_a_leg_prefix
FROM (
  SELECT (regexp_matches(why, '\m[0-9a-f]{8}\M', 'g'))[1] AS tok
  FROM public.ottoq_stall_bookings
  WHERE sim_run_id IN ('952421ec-5e75-4342-be42-5d2c14d5972d','f3451a24-4dad-4d42-a385-4a9d366708d2')
) x;
--   812 matched, 512 distinct, 0 not a leg prefix

-- ============================================================================
-- 6. WHY THIS IS A CHECK THAT CAN FAIL
-- ============================================================================
--
-- Before 0139, endst differs on every pair -- so promoting it without the scrub would
-- fail every pair. After the scrub it agrees on the pairs we have measured. The check
-- therefore sits where a check belongs: it distinguishes. 0139 also asserts the scrubber
-- in both directions -- that it collapses two leg ids and two uuids, and that it does NOT
-- collapse "inspect" against "charge" or NASH-STG-B012 against NASH-STG-B011.
--
-- Note the verdict uses jsonb equality, not IS NOT DISTINCT FROM: if the image is ever
-- missing, v_equal goes NULL and the pair is recorded 'failed'. Absent evidence is not
-- passing evidence.
--
-- ============================================================================
-- 7. WHAT IS STILL OPEN
-- ============================================================================
--
--   * db/checks/0050's CORRECTION banner STANDS. peak_site_kw is still not reproducible;
--     0138 shipped peak_site_kw_demand as the reproducible number and left the billed
--     figure labelled not_reproducible. Nothing here changes that, and 0051 stays open.
--   * The normal_day 171717/12t intermittent deviation (task #47) has 2 consecutive passes.
--     Two is not evidence against a 1-in-4 rate. The r9 matrix is busy_day only; normal_day
--     needs its own repeat series before that can be called closed.
--   * c1-c3 and d1-d3 land by 01:46 and are the re-certification of 171717/24t and
--     424242/24t on the post-0136 canon. Until they land those two columns are reading
--     STALE and are not counted.
