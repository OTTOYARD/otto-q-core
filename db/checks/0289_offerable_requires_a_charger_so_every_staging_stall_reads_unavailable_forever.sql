-- 0289  `offerable` REQUIRES AN OCPP CHARGER, SO ALL 113 STAGING STALLS, 3 WASH BAYS AND 2
--       SERVICE BAYS READ FALSE FOREVER — AND I ALMOST PUBLISHED "STAGING IS 100% OCCUPIED
--       FOR THE WHOLE RUN" FROM IT.
--
-- Read-only. MEASURED, NOT FIXED — the remedy changes the frame contract, which is
-- `forces_recert` territory and a design choice (§4). Scope: twin depot
-- 11111111-1111-1111-1111-111111111111 (rule 8), completed run
-- `c8f678fb-a04a-4c18-a937-9b93673f3fe9` (busy_day, seed 100020, 1,224 ticks, 00:35 -> 09:37
-- CT). Snapshots and bookings are `class='engine'` and purge with the run.
--
-- ══ 1. THE NEAR-MISS, FIRST, BECAUSE IT IS THE POINT ═══════════════════════
--
-- Following `0288`'s capacity thread I counted staging availability from the decision frame
-- and got: **113 staging stalls, `offerable` = 0, in every one of the run's 611 snapshots,
-- night and wave alike — mean 100.0% occupied.** That is a dramatic, quotable number and it
-- is **wrong**. It would have gone into a capacity claim about the one depot rule 8 exists to
-- characterise.
--
-- What stopped it was asking the question CLAUDE.md's three-gate rule demands — *which* gate
-- says no — rather than accepting a single field. Measured mid-wave at **07:00 CT, tick 910**:
--
--   staging stalls                                         113
--   **pointer-free** (status available, no vehicle, no reservation)   **76**
--   **calendar-free** (no held/active/done/interrupted booking spanning that clock)  **77**
--   **`offerable`**                                          **0**
--
-- 76 and 77 out of 113 cannot intersect in zero: by pigeonhole **at least 40** staging stalls
-- were free on BOTH real gates at that instant. So `offerable = 0` is not an occupancy.
--
-- ══ 2. THE CAUSE, AT THE SOURCE, IN ONE CLAUSE ═════════════════════════════
--
-- `public.ottoq_build_decision_frame(uuid, uuid)` builds it as:
--
--     'offerable', (s.current_vehicle_id IS NULL
--                   AND s.ocpp_charger_id IS NOT NULL
--                   AND c.station_state = 'Available' ...)
--
-- **`ocpp_charger_id IS NOT NULL` is the whole finding.** A staging stall has no charger —
-- the frame's own row reads `"ocpp_charger_id": null, "connector_type": "NonCharging"` — so
-- the conjunction is false before any gate is consulted. The same holds for the 3 wash bays
-- and 2 service bays. **`offerable` is a CHARGE-stall predicate**, false by construction for
-- 118 of the twin depot's 158 stalls.
--
-- ══ 3. AND THAT IS NOT A DEFECT IN `offerable` ═════════════════════════════
--
-- This is the part to get right rather than the satisfying part. `0265`/L-61 added the key for
-- *"the three facts the selector refuses on"*, and the selector it serves is the charge-stall
-- selector. Its own comment states the contract precisely and honestly:
--
--     --: VEHICLE-BLIND on purpose: the selector also accepts a stall reserved
--     --: for the proposal's OWN vehicle, which this object cannot know. So
--     --: offerable=false means no proposal can win it; offerable=true means a
--     --: proposal for a vehicle with no competing reservation can.
--
-- For a charge stall that is exactly right, and `0372` later added the charger-health gate to
-- it deliberately. **The defect is in the READER, not the field** — in anything that treats
-- `offerable` as general availability. Tonight that reader was me. `proposer/forward_proposer.py`
-- is not affected: it consults `offerable` only for charge-capable stalls, which is the
-- population the key describes.
--
-- **So the rule this earns, and it generalises past this field:** a boolean named for an
-- outcome (*offerable*) rather than for its domain (*charge-stall offerable*) will be read
-- outside its domain, and the reading will look like a measurement. CLAUDE.md's three-gate
-- rule already says to name which gate refused; this adds that you must first check the
-- predicate is **defined** for the population you are counting.

WITH snap AS (
  SELECT frame, sim_clock, tick_seq FROM public.ottoq_decision_snapshots
   WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
     AND sim_clock BETWEEN '2026-09-20 12:00:00+00' AND '2026-09-20 12:10:00+00'
   ORDER BY tick_seq LIMIT 1),
st AS (SELECT s FROM snap CROSS JOIN LATERAL jsonb_array_elements(frame->'stalls') s)
SELECT s->>'type' AS stall_type,
       count(*) AS stalls,
       count(*) FILTER (WHERE s->>'ocpp_charger_id' IS NOT NULL) AS have_a_charger,
       count(*) FILTER (WHERE s->>'status' = 'available'
                          AND s->>'vehicle_id' IS NULL
                          AND s->>'reserved_by' IS NULL) AS pointer_free,
       count(*) FILTER (WHERE (s->>'offerable')::boolean) AS offerable,
       'offerable requires ocpp_charger_id IS NOT NULL' AS why
  FROM st GROUP BY 1 ORDER BY stalls DESC;

-- the three gates side by side for staging, at one mid-wave instant
WITH staging AS (SELECT id FROM public.stalls
                  WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                    AND stall_type = 'staging'),
snap AS (SELECT frame, sim_clock, tick_seq FROM public.ottoq_decision_snapshots
          WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
            AND sim_clock BETWEEN '2026-09-20 12:00:00+00' AND '2026-09-20 12:10:00+00'
          ORDER BY tick_seq LIMIT 1),
st AS (SELECT s FROM snap CROSS JOIN LATERAL jsonb_array_elements(frame->'stalls') s
        WHERE s->>'type' = 'staging'),
claimed AS (
  SELECT count(DISTINCT b.stall_id) AS n
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
     AND b.stall_id IN (SELECT id FROM staging)
     AND b.state IN ('held','active','done','interrupted')
     AND b.during @> (SELECT sim_clock FROM snap))
SELECT to_char((SELECT sim_clock FROM snap) AT TIME ZONE 'America/Chicago', 'HH24:MI') AS ct,
       (SELECT tick_seq FROM snap) AS tick,
       (SELECT count(*) FROM st) AS staging_stalls,
       (SELECT count(*) FROM st WHERE s->>'status' = 'available'
                                  AND s->>'vehicle_id' IS NULL
                                  AND s->>'reserved_by' IS NULL) AS gate1_pointer_free,
       (SELECT count(*) FROM staging) - (SELECT n FROM claimed) AS gate2_calendar_free,
       'n/a (no charger)' AS gate3_charger,
       (SELECT count(*) FROM st WHERE (s->>'offerable')::boolean) AS offerable,
       GREATEST(0,
         (SELECT count(*) FROM st WHERE s->>'status' = 'available'
                                    AND s->>'vehicle_id' IS NULL
                                    AND s->>'reserved_by' IS NULL)
         + ((SELECT count(*) FROM staging) - (SELECT n FROM claimed))
         - (SELECT count(*) FROM staging)) AS free_on_both_at_least;

-- ══ 4. THE OPEN QUESTION THIS LEAVES, STATED AS A QUESTION ═════════════════
--
-- **792 `twin.staging_overflow` events fired on this run** — 422 in the night tail, 370 in the
-- wave, continuously from 00:42 to 09:37 CT — on a run where at least 40 staging stalls were
-- provably free on both real gates mid-wave. Against the prior run's 258, this is 3x.
--
-- **I am NOT claiming `offerable` causes the overflow.** The overflow producer may compute
-- availability from the pointers or the calendar directly and never read the frame at all;
-- `twin.staging_overflow` is a twin event, and the frame is a proposer input. Establishing the
-- link needs the producer read end to end, which is the next measurement and is not done here.
-- What IS established: **792 overflow events and ~40 free staging stalls coexist**, so at
-- least one of the two is not measuring what its name says, and the capacity conclusion
-- `0288` §3 draws from `p95_time_to_service` 39.6 min and `returns_unserved` 11 must not be
-- extended into a claim about *staging* capacity until that is resolved.
--
-- ══ 5. WHY NOT FIXED ══════════════════════════════════════════════════════
--
-- Three options, none of them small:
--
--   (a) **Rename the key** to say its domain (`charge_offerable`). Honest and cheap to reason
--       about, and it changes the frame's shape — `proposer/forward_proposer.py` pins
--       `OFFERABLE_KEY = "offerable"`, and the frame is digested into `frame_hash`, so it is a
--       `forces_recert TRUE` change that invalidates all nine canon columns.
--   (b) **Add a second fact** for non-charge stalls (`offerable_noncharge`, pointer AND
--       calendar, no charger term). Additive, same recert cost, and it gives any future reader
--       the thing they will otherwise fabricate from `offerable`.
--   (c) **Leave it and document** — which is what this file does, plus the general rule in §3.
--
-- **(b) is what I would build**, gated on someone actually needing staging availability in the
-- frame; today no consumer does, which is exactly why the field has been wrong for 118 stalls
-- without anything breaking. Recorded as **G99**.
