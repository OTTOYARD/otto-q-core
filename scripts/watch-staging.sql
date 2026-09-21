-- ---------------------------------------------------------------------------
-- watch-staging.sql -- the staging & orchestration spec, as a test. Run id in,
-- one row per requirement out.
--
-- WHY THIS EXISTS. scripts/watch-run.sql proves the chain MOVES. It does not
-- ask whether the chain moves WELL, and the difference is the whole product:
-- a depot where every vehicle eventually gets served and a depot where no
-- vehicle waits needlessly look identical at the hop level.
--
-- THE SPEC THIS TESTS, given 2026-09-14:
--   1. short-term staging AND long-term / perimeter holding, as distinct places
--   2. know which stalls are booked and do not send vehicles to them
--   3. when every service / wash / charge stall is booked, stage temporarily
--   4. anything flagged mid-workflow goes to perimeter / long-term holding
--   5. when a stall frees, TELL the waiting vehicle to proceed
--   6. never lose track of a vehicle that is waiting or needs an assignment
--   7. it matters most where supply is scarce -- few chargers, many vehicles
--
-- READ THE note COLUMN. Every line says what its number does NOT mean.
--
-- NOTE: unquoted identifiers fold to lower case in Postgres, so the CTE R and a
-- table alias r are THE SAME NAME. The run CTE is R and every alias avoids r.
--
-- USAGE  psql ... -v run="'<sim_run_id>'" -f scripts/watch-staging.sql
-- ---------------------------------------------------------------------------
WITH R AS (SELECT :run::uuid AS id),
D AS (SELECT sr.depot_id AS depot, sr.sim_clock_current AS simnow
        FROM public.ottoq_sim_runs sr, R WHERE sr.sim_run_id=R.id)
SELECT * FROM (

  -- 1. HOLDING CLASSES ------------------------------------------------------
  SELECT 1 AS req, 'holding classes: short-term vs perimeter' AS requirement,
    (SELECT count(*) FILTER (WHERE stall_type::text='staging')::text||' staging / '||
            count(*) FILTER (WHERE stall_type::text='parking')::text||' parking / '||
            count(*) FILTER (WHERE stall_type::text='safety')::text||' safety'
       FROM public.stalls s, D WHERE s.depot_id=D.depot) AS n,
    'parking = long-term/perimeter, safety = quarantine. Both are DECLARED in the '||
    'stall_type enum. A zero here is the spec gap, not a data error.' AS note

  -- 2. BOOKED-STALL AWARENESS ----------------------------------------------
  UNION ALL SELECT 2, 'does it avoid stalls already taken',
    (SELECT COALESCE(count(*) FILTER (WHERE reason_code='target_occupied')||' of '||
            count(*) FILTER (WHERE payload ? 'stall_id')||' aimed at an occupied stall','(no commands)')
       FROM public.ottoq_vehicle_commands c, R WHERE c.sim_run_id=R.id),
    'THE SPEC SAYS DO NOT SEND THEM THERE. A refusal means the net caught it, not '||
    'that the kernel avoided it. Baseline to beat: 116 of 347 = 33% (run 34ffb2d9).'

  -- 3. SATURATION -> STAGE --------------------------------------------------
  UNION ALL SELECT 3, 'all stalls booked -> hold in staging',
    (SELECT COALESCE(count(*)||' overflow events, max '||
            COALESCE(max((payload->>'overflow')::int),0)||' held at once','(never fired)')
       FROM public.ottoq_events e, R
      WHERE e.sim_run_id=R.id AND e.event_type='twin.staging_overflow'),
    (SELECT COALESCE('caps at the time: svc '||min((payload->>'svc_cap')::int)||
            ', wash '||min((payload->>'wash_cap')::int)||
            ', patience '||min((payload->>'patience_min')::numeric)||' min','-')
       FROM public.ottoq_events e, R
      WHERE e.sim_run_id=R.id AND e.event_type='twin.staging_overflow')

  -- 4. FLAGGED -> ESCALATED -------------------------------------------------
  UNION ALL SELECT 4, 'flagged mid-workflow -> escalated out',
    (SELECT COALESCE(sum((payload->>'escalated')::int)::text,'0')||' escalated, '||
            COALESCE(sum((payload->>'gate_held')::int)::text,'0')||' gate-held'
       FROM public.ottoq_events e, R
      WHERE e.sim_run_id=R.id AND e.event_type='twin.staging_overflow'),
    'ESCALATED IS A DECISION, NOT A DESTINATION. With 0 parking and 0 safety stalls '||
    'an escalated vehicle goes to the same staging pool as a vehicle waiting 5 min.'

  -- 5. RELEASE -> PROCEED ---------------------------------------------------
  UNION ALL SELECT 5, 'a stall frees -> the waiting vehicle is told',
    (SELECT count(*)::text||' bookings released/done'
       FROM public.ottoq_stall_bookings b, R
      WHERE b.sim_run_id=R.id AND b.state::text IN ('released','done')),
    (SELECT count(*)::text||' stall-bearing commands issued after them -- this pairing is '||
            'COUNTS ONLY, not a causal link: it does not prove any one release produced '||
            'any one command'
       FROM public.ottoq_vehicle_commands c, R
      WHERE c.sim_run_id=R.id AND c.payload ? 'stall_id')

  -- 6. NOBODY LOST ----------------------------------------------------------
  UNION ALL SELECT 6, 'no vehicle waiting without an assignment',
    (SELECT count(*)::text FROM public.vehicles v, D
      WHERE v.home_depot_id=D.depot
        AND v.current_state::text IN ('arrived_at_gate','staged_awaiting_service')
        AND v.current_stall_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands c, R
                         WHERE c.vehicle_id=v.id AND c.sim_run_id=R.id AND c.status='issued')),
    'vehicles parked in a waiting state with NO stall and NO outstanding command. '||
    'This is the "lost" count and it must be 0. Read it only while the run is LIVE: '||
    'after teardown every vehicle is legitimately stall-less.'

  -- 7. THE QUEUE ITSELF ------------------------------------------------------
  --    MEASURE THE WAIT AGAINST THE SIM CLOCK, NOT now(). The twin's clock runs
  --    ahead of wall time, so now() - last_state_change returns a NEGATIVE wait
  --    and reads as "nobody is waiting" when the queue is in fact hours deep.
  --    Caught on run 2235ce6e: this line said -58 real-min while a vehicle had
  --    been at the gate for 330 SIM-minutes.
  UNION ALL SELECT 7, 'queue depth and the longest wait',
    (SELECT count(*)::text||' waiting' FROM public.vehicles v, D
      WHERE v.home_depot_id=D.depot
        AND v.current_state::text IN ('arrived_at_gate','staged_awaiting_service')),
    (SELECT COALESCE('longest wait '||
            max(round(EXTRACT(epoch FROM (D.simnow - v.last_state_change))/60.0))::text||
            ' SIM-min; '||count(*) FILTER (WHERE EXISTS (
                SELECT 1 FROM public.ottoq_visit_needs nd, R
                 WHERE nd.vehicle_id=v.id AND nd.sim_run_id=R.id
                   AND nd.status IN ('open','in_progress')))::text||' of them have an OPEN NEED',
            'nobody waiting')
       FROM public.vehicles v, D
      WHERE v.home_depot_id=D.depot
        AND v.current_state::text IN ('arrived_at_gate','staged_awaiting_service'))

  -- 8. SCARCITY ---------------------------------------------------------------
  UNION ALL SELECT 8, 'supply vs demand at this depot',
    (SELECT count(*) FILTER (WHERE stall_type::text='dcfc')::text||' dcfc + '||
            count(*) FILTER (WHERE stall_type::text='l2')::text||' l2 for '||
            (SELECT count(*) FROM public.vehicles v, D d2 WHERE v.home_depot_id=d2.depot)::text||' vehicles'
       FROM public.stalls s, D WHERE s.depot_id=D.depot),
    'the spec cares most about the scarce case: many vehicles, few plugs, no L2. '||
    'A depot with plenty of L2 never enters that regime and cannot test it.'

) x ORDER BY req;
