-- 0262  THE ATTRIBUTION: FIFTY-FOUR OF THE SEVENTY-EIGHT REROUTES ON THIS RUN
--       COULD NOT HAVE HAPPENED BEFORE 0368, AND NO ENGINE CHANGE WAS NEEDED TO
--       PROVE IT.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed 777777, speed 8.0).
--
-- 0368 records `stall_type_source` in the ESCALATION outcome only, so the cases
-- where its inference SUCCEEDED are invisible in the payload -- the measurement gap
-- was noticed and the obvious fix (write the key on the rerouted outcome too) was
-- rejected: it changes the command payload, which is one of the fourteen atoms, so
-- it would force a recert to answer a question that a query can answer for free.
--
-- The reconstruction: a rerouted command carries `reroute_after` naming the refused
-- command it replaces. Join back to that command, read whether ITS payload carried
-- `stall_type`, and look up the type of the stall it was actually sent to. When the
-- refused command had no `stall_type` and its target was `staging`, the pre-0368
-- code would have searched `dcfc` -- `COALESCE(payload->>'stall_type', CASE
-- command_type WHEN 'stage' THEN 'staging' ELSE 'dcfc' END)` -- and there are ten
-- DCFC stalls on this site against 113 staging.

WITH new AS (
  SELECT c.command_id,
         c.payload->>'stall_type'                    AS new_type,
         NULLIF(c.payload->>'reroute_after','')::uuid AS prev_cmd
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND c.payload ? 'reroute_after'
)
SELECT n.new_type                                              AS rerouted_to_type,
       (p.payload->>'stall_type' IS NULL)                      AS refused_cmd_had_no_type,
       (SELECT s.stall_type::text FROM public.stalls s
         WHERE s.id = NULLIF(p.payload->>'stall_id','')::uuid)  AS refused_cmd_target_type,
       --: what the pre-0368 walk would have searched for
       CASE WHEN p.payload->>'stall_type' IS NOT NULL THEN p.payload->>'stall_type'
            WHEN p.command_type = 'stage' THEN 'staging'
            ELSE 'dcfc' END                                    AS pre_0368_would_search,
       count(*)                                                AS n
  FROM new n
  JOIN public.ottoq_vehicle_commands p ON p.command_id = n.prev_cmd
 GROUP BY 1,2,3,4 ORDER BY 5 DESC;

-- Measured at tick 620 (the run was live, so these grow; the SHAPE is the finding,
-- and at tick 645 it read refused 211 / reroutable 114 / rerouted 90 = 78.9%):
--
--   rerouted_to  refused had no type  real target  pre-0368 would search    n
--   staging      TRUE                 staging      dcfc                    54   <- impossible before
--   staging      FALSE                staging      staging                 15
--   l2           FALSE                l2           l2                       8
--   dcfc         FALSE                dcfc         dcfc                     1
--
-- **Fifty-four of the seventy-eight reroutes at that reading are cases where the refused command
-- carried no `stall_type`, its real target was a staging stall, and the walk
-- correctly searched staging. Before 0368 every one of those fifty-four would have
-- hunted ten DCFC stalls, found nothing, and escalated `no_capacity`.** That is the
-- mechanism behind the loop's success rate moving from 2 of 7 (29%) to 61 of 83
-- (73.5%) on the reroutable class, and it is attributable rather than inferred.
--
-- The other 24 are the cases that already worked: the command named its own
-- `stall_type` and 0368 changed nothing about them, which is what a narrow fix
-- should look like.
--
-- WHAT THIS DOES NOT SAY. It does not separate 0368's contribution from 0369's. A
-- reroute needs BOTH a correct search type and a stall the pointer will grant, and
-- 0369 is what freed the pointer (21 unbacked orphans released, 15 calendar-backed
-- plans left intact). The honest decomposition: 0368 is necessary for these 54 --
-- without it the walk never looks at staging at all -- and 0369 is what made the
-- staging pool non-empty when it did look. Neither alone produces the number.
--
-- AND THE ORDER OF DISCOVERY IS THE POINT, not an anecdote. 0367 had to land first
-- or nothing downstream was visible: while the reclaimer was dark every refusal
-- read as `no_capacity` and the depot looked full. 0368 became findable only once
-- the depot had stalls to offer, and 0369 and 0370 became findable only once
-- 0368 stopped the walk looking in the wrong place. Four migrations, each one the
-- instrument that exposed the next.

SELECT r.sim_run_id, r.status, r.tick_count,
       count(*) FILTER (WHERE c.status = 'refused')                        AS refused_all,
       count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code IN ('target_occupied','resource_faulted')
                          AND c.command_type IN ('proceed_to_stall','begin_charge','stage'))
                                                                          AS reroutable,
       count(*) FILTER (WHERE c.payload ? 'reroute_after')                 AS reroute_commands_issued,
       count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted') AS refusals_rerouted,
       count(*) FILTER (WHERE c.payload->'reaction'->>'reason' = 'no_capacity') AS escalated_no_capacity,
       round(100.0 * count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted')
             / NULLIF(count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code IN ('target_occupied','resource_faulted')
                          AND c.command_type IN ('proceed_to_stall','begin_charge','stage')), 0), 1)
                                                                          AS reroute_success_pct
  FROM public.ottoq_sim_runs r
  LEFT JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY r.sim_run_id, r.status, r.tick_count, r.started_at
 ORDER BY r.started_at DESC;

-- THE TWO COUNTS TRACK, MEASURED: at tick 645 both read **90**. `reroute_commands_issued` counts the NEW commands
-- carrying `reroute_after`; `refusals_rerouted` counts the refused commands whose
-- reaction says `rerouted`. They should track each other one-to-one and a
-- divergence is worth chasing: a new command with no matching reaction means the
-- reroute emitted and the outcome stamp did not land, which would make every
-- success rate in this file an under-count.
