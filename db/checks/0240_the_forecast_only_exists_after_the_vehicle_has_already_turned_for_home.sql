-- ===========================================================================
-- 0240  THE RETURN FORECAST ONLY EXISTS AFTER THE VEHICLE HAS ALREADY TURNED
--       FOR HOME -- AND THREE OF ITS FOUR WRITERS DO NOT TOUCH ITS PROVENANCE
--
-- Measured 2026-09-14 17:35-17:40 UTC against the two twin runs that were used
-- to demonstrate 0314-0319, WHILE round 43 was certifying those same
-- migrations. Read-only throughout; nothing here was applied.
--
--   run a5bd449f-9362-4f83-838b-8c97470dd01c   27 ticks, 61 dispatches
--   run 622e9556-7ea1-4624-b18c-e1b7715ca2db   34 ticks, 12 dispatches
--
-- These are MY OWN runs, produced to show that "the ETA stops being a
-- constant." It does. What this file records is everything that sentence was
-- still hiding, found by asking the dispatch rows a question the packet counts
-- could not answer.
--
-- ---------------------------------------------------------------------------
-- WHAT I REPORTED, AND WHAT THE SAME RUNS ALSO SAY
--
-- Reported: 98.2% of packets positioned, ETAs from 1 distinct value to 62.
-- Both true, both about TELEMETRY PACKETS. The dispatch rows -- the place the
-- forecast is actually stored and read from -- say three more things.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- §A  DEFECT 1. EVERY `active` DISPATCH HAS NO ETA AT ALL.
--
--     An `active` dispatch is a vehicle OUT WORKING. A `returning` dispatch has
--     already been told to come home. The forecast exists only for the second.
-- ---------------------------------------------------------------------------
SELECT d.status, count(*) AS n,
       count(*) FILTER (WHERE d.return_eta_minutes IS NULL) AS eta_null,
       count(DISTINCT d.return_eta_minutes) AS distinct_eta,
       min(d.return_eta_minutes) AS lo, max(d.return_eta_minutes) AS hi
  FROM public.ottoq_vehicle_dispatches d
 WHERE d.sim_run_id IN ('a5bd449f-9362-4f83-838b-8c97470dd01c',
                        '622e9556-7ea1-4624-b18c-e1b7715ca2db')
 GROUP BY 1 ORDER BY 1;
-- MEASURED:
--   active     36 rows   36 eta_null   0 distinct         -- ALL of them
--   returning  20 rows    0 eta_null  20 distinct  15.6 .. 48.8
--   completed  17 rows    0 eta_null   7 distinct   1.6 .. 30
--
-- 36 of 36. Not a sampling artefact, not a race: the write that sets
-- return_eta_minutes lives in the branch that ALSO flips status to 'returning'
-- (twin.ottoq_sim_advance_deployed_telemetry L323), so by construction the
-- number cannot exist before the decision it is supposed to inform.
--
-- THIS IS THE FORWARD-PREDICTION REQUIREMENT, MISSED. The brief is explicit --
-- CLAUDE.md 2.7 asks `decide(asset, work, site) -> { recall_time, ... }`, a
-- decision about WHEN TO RECALL. A forecast produced at the moment of recall
-- cannot inform the recall. What exists today is an arrival estimate for
-- vehicles already inbound; what 2.7 asks for is a return-time forecast for
-- vehicles still working. The machinery is all present -- ottoq_trip_geometry
-- takes (vehicle, run, clock) and needs only an OPEN dispatch, which an active
-- one is -- so this is a wiring gap, not a modelling one.

-- ---------------------------------------------------------------------------
-- §B  DEFECT 2. THE PROVENANCE LABEL DESCRIBES AN EARLIER WRITE.
--
--     0318 is titled "the engine stopped guessing and the label kept saying
--     guess". It fixed the labelling inside ONE writer. There are FOUR.
-- ---------------------------------------------------------------------------
SELECT COALESCE(d.eta_source,'(null)') AS eta_source, count(*) AS n,
       count(DISTINCT d.return_eta_minutes) AS distinct_eta,
       min(d.return_eta_minutes) AS lo, max(d.return_eta_minutes) AS hi
  FROM public.ottoq_vehicle_dispatches d
 WHERE d.sim_run_id = 'a5bd449f-9362-4f83-838b-8c97470dd01c'
 GROUP BY 1 ORDER BY 1;
-- MEASURED:
--   (null)                              38   1 distinct   30 .. 30   (+22 NULL)
--   policy_constant:return_eta_minutes  21  17 distinct  1.6 .. 48.8
--   twin_eta_delay_card:congestion       1   0 distinct   NULL
--   twin_eta_delay_card:heavy_traffic    1   0 distinct   NULL
--
-- READ THE SECOND ROW AGAIN. Twenty-one rows are labelled as coming from a
-- POLICY CONSTANT, and they hold SEVENTEEN DISTINCT VALUES between 1.6 and 48.8
-- minutes. A constant does not take seventeen values.
--
-- The writers, all four, with what each does to the two provenance columns:
--
--   twin.ottoq_sim_advance_deployed_telemetry  L323  value + eta_source + eta_refreshed_at
--   twin.ottoq_sim_auto_dispatch_tick          L139  value ONLY
--   public.ottoq_ingest_vehicle_signal         L53   value ONLY
--   twin.ottoq_sim_prime_deployment            L104  value ONLY (INSERT, dial = 30)
--
-- So the sequence that produces the 21 rows is: the deployed-telemetry writer
-- stamps the honest label at the return flip (the computation refused there,
-- so 'policy_constant' was CORRECT when written), and then
-- ottoq_sim_auto_dispatch_tick overwrites return_eta_minutes on later ticks
-- with a genuinely computed value and leaves eta_source alone. The label is not
-- lying about its own write; it is describing a write that has been superseded.
-- That is worse than a wrong label, because the code that wrote it is correct
-- when read in isolation -- which is exactly why 0318 did not catch it.
--
-- And the 38 `(null)`-source rows holding exactly 30: ottoq_sim_prime_deployment,
-- the t=0 fixture. Defensible as a fixture; not defensible as unlabelled, since
-- a reader cannot distinguish "the fixture put 30 here" from "the computation
-- returned 30".
--
-- VERIFY THE CLAIM STRUCTURALLY, not just from these two runs: exactly one
-- function in the database writes eta_source at all.
SELECT 'writers of eta_source' AS check,
       COALESCE(string_agg(n.nspname||'.'||p.proname, ', '),'(none)') AS fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~ 'eta_source';
-- MEASURED: twin.ottoq_sim_advance_deployed_telemetry. One, of four writers.

-- ---------------------------------------------------------------------------
-- §C  DEFECT 3. ONE PAIR OF PROVENANCE COLUMNS SERVES TWO DIFFERENT QUANTITIES.
--
--     The delay-card branch (same function, the `status = 'active'` block)
--     applies a modelled traffic delay by moving scheduled_return_at -- an
--     INSTANT -- and stamps eta_refreshed_at + eta_source while doing it. It
--     never touches return_eta_minutes, a DURATION.
--
--     So on those rows eta_source is describing a different column from the one
--     any reader would naturally pair it with, and the 2 rows above show the
--     signature: a source and a refresh stamp sitting beside a NULL ETA.
--
--     This is the G54 class (two things, one name) rather than a simple bug.
--     Note it cuts BOTH ways: the delay card is the ONLY mechanism in the twin
--     that models traffic shifting an arrival, which is precisely the behaviour
--     Chase asked for -- and it is invisible to anyone reading
--     return_eta_minutes, because it does not write there.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- §D  WHAT WAS CHECKED AND FOUND NOT TO BE A DEFECT, recorded because each was
--     one step from being written up as one.
--
--  i. "Position and the ETA are two sources of truth." FALSE.
--     twin.ottoq_sim_emit_telemetry does not call ottoq_trip_geometry, which
--     looked like an independent derivation -- but it delegates to
--     public.ottoq_vehicle_position, which does. One source, two projections.
--     Checked before it was alleged; see db/checks/0239 sec B.
--
-- ii. "A slipped ETA loses the stall, because reservation_expires_at is sized
--     from the ETA and ottoq_gc_stale_reservations compares it to now() -- the
--     WALL clock -- while the twin runs a sim clock 13 days in the past."
--     The clock-domain mismatch in that function is REAL. The harm is not:
--     ottoq_gc_stale_reservations has ZERO callers and appears in no cron job.
--     It is dead code, and a live defect was nearly reported from it.
--     ottoq_reserve_stall itself is clock-consistent -- it stamps p_now + ttl
--     and compares against p_now, both the caller's clock.
--     Left alone here; worth a COMMENT the day anything calls it.
-- ---------------------------------------------------------------------------
SELECT 'ottoq_gc_stale_reservations callers' AS check,
       COALESCE((SELECT string_agg(n.nspname||'.'||p.proname, ', ')
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname IN ('public','twin','ottoq')
                    AND p.prosrc ~ 'ottoq_gc_stale_reservations'
                    AND p.proname <> 'ottoq_gc_stale_reservations'), '(none)') AS fn_callers,
       COALESCE((SELECT string_agg(jobname, ', ') FROM cron.job
                  WHERE command ~ 'gc_stale_reservations'), '(none)') AS cron_jobs;
-- MEASURED: (none) / (none).

-- ---------------------------------------------------------------------------
-- §E  THE ORDER OF THE FIX, AND WHY NONE OF IT IS IN ROUND 43
--
--     All three defects change what the engine writes, so all three force a
--     recertification. Round 43 is certifying 0313-0319 right now and any
--     migration applied during it moves the recert floor past every pair
--     already banked. Drafted now, applied after the round lands.
--
--     1. ONE refresh path. A single function that recomputes the ETA, writes
--        the value, the stamp and the source TOGETHER, and is the only thing
--        allowed to write return_eta_minutes. Three writers stop writing the
--        column directly and call it instead. This closes defect 2 by
--        construction rather than by adding a third label to a fourth site --
--        0318 already showed that labelling site-by-site does not converge.
--
--     2. Refresh on `active`, not only at the flip. Same function, called each
--        tick for every open dispatch. That is defect 1, and it is what makes a
--        recall decision able to read a forecast instead of producing one.
--
--     3. Separate provenance for the instant from provenance for the duration,
--        closing defect 3 -- or, better, have the delay card go through the one
--        refresh path in (1) so the two quantities stay consistent by
--        construction.
--
--     AND THE THING TO MEASURE BEFORE BUILDING (2): whether recomputing every
--     tick for every open dispatch is affordable. A 12-tick flagship pair runs
--     125 s today; ottoq_computed_eta_minutes does an aggregate over
--     ottoq_telemetry_packets per call, and G21/G29 are this repo's record of
--     what a per-row re-derivation costs when nobody measured first.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- §F  THE AFFORDABILITY MEASUREMENT §E ASKED FOR, TAKEN BEFORE BUILDING
--
--     EXPLAIN (ANALYZE, BUFFERS) over one tick's worth of refresh -- every open
--     dispatch in run a5bd449f, calling ottoq_computed_eta_minutes once each:
--
--         rows 44        Execution Time 187.772 ms
--         Buffers: shared hit=4972 read=260     (~113 buffers per call)
--
--     4.3 ms per vehicle per refresh. At flagship scale (~100 deployed) that is
--     ~430 ms per tick, so a 48-tick pair over two arms gains roughly 41 s on a
--     ~500 s baseline -- about 8%. Affordable. Measured, not assumed, because
--     G21 and G29 are this repo's record of what happens when a per-row
--     re-derivation ships without anyone timing it first.
--
--     AND THE CHEAPER FIX IS ALSO THE MORE CORRECT ONE, which is rare enough to
--     state plainly. The dominant term is
--
--         SELECT COALESCE(avg(tp.speed_kmh), 35.2) FROM ottoq_telemetry_packets
--          WHERE vehicle_id = ... AND sim_run_id = ... AND sim_clock_at <= ...
--            AND speed_kmh > 0
--
--     an UNBOUNDED aggregate over the vehicle's whole history in the run, whose
--     cost grows with tick count. db/checks/0239 sec E already flagged it on
--     correctness grounds: a lifetime average is the most heavily damped
--     estimator available, and a vehicle that slows to a crawl in its last ten
--     minutes barely moves it -- which is exactly the behaviour the ETA is
--     supposed to express. Replacing it with a WINDOWED average over the most
--     recent N packets is
--
--       - more responsive: recent traffic actually moves the number;
--       - bounded: N rows instead of a growing scan;
--       - already indexed: idx_telem_vehicle_time is (vehicle_id, sim_clock_at
--         DESC), so the window is an index scan with a LIMIT.
--
--     N becomes a dial, catalogued like every other (0302/0304/0305), and its
--     value is a question for measurement, not for taste: how much does the ETA
--     actually move as N varies, on a fixed seed. That measurement belongs in
--     the same window as the fix, and its result is reported with the run ID.

-- ---------------------------------------------------------------------------
-- §G  HOW MUCH A WINDOWED SPEED ACTUALLY MOVES THE ETA -- the measurement §F
--     said the window size is a question for data, not taste
--
--     Read-only over run a5bd449f's telemetry: per vehicle, the lifetime
--     avg(speed_kmh) the ETA uses today, against the average of that vehicle's
--     most recent N packets. 60 vehicles with >= 5 moving packets, 23.0 packets
--     each on average.
--
--       estimator      mean km/h    mean |move| vs lifetime    max |move|
--       lifetime         34.43              --                    --
--       last 10          34.41             6.6%                   --
--       last 5           33.62            11.0%                   --
--       last 3           32.34            16.4%                 56.6%
--
--     TWO THINGS TO READ OUT OF THAT, and the second is the one that decides it.
--
--     First, responsiveness. A 3-packet window moves a vehicle's speed -- and
--     therefore its ETA, which is distance/speed -- by 16.4% on average and by
--     more than HALF in the worst case. The lifetime average moves by
--     definition 0%. That difference is the entire requirement: an ETA that
--     shifts when a vehicle hits traffic.
--
--     Second, and this is why N=3 is safe rather than merely lively: the FLEET
--     MEAN barely moves (34.43 -> 32.34). The window lets individual vehicles
--     deviate without re-scaling the fleet's average speed -- exactly the
--     property ottoq_congestion_factor was built to preserve (0.75 on four peak
--     hours and 1.05 on the other twenty, averaging to 1.0). Two independent
--     parts of the timing model would then share one discipline: re-time
--     arrivals, do not re-scale the fleet.
--
--     RECOMMENDATION: N = 3, as a catalogued dial (0302/0304/0305 make the
--     catalogue the allow-list, so a new dial is registered or it is refused).
--
--     AND THE LIMIT OF THIS MEASUREMENT, stated rather than glossed: it is ONE
--     run and 60 vehicles, and it measures the SPREAD of a windowed estimator,
--     not whether the windowed number is closer to the truth. The twin has no
--     ground-truth arrival time to score against -- scheduled_return_at is
--     written by the same machinery, which would be circular, exactly the
--     circularity 0009 recorded when it found 116 of 116 rows arriving at
--     dispatch + 30 min and noted there was no training signal. What can
--     honestly be claimed is that a windowed estimator RESPONDS and a lifetime
--     one does not, and that the fix is also the cheaper one (§F). Claiming it
--     is more ACCURATE needs an arrival ledger that does not derive from the
--     ETA, and that is its own piece of work.
--
--     NOT BUILT HERE, and not in the same window as 0321. 0321 already changes
--     what the ETA is for ~36 rows per run; changing the estimator in the same
--     recert would make a moved canon unattributable between the two. Separate
--     file, after round 44.
