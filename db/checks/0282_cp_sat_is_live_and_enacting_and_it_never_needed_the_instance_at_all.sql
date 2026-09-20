-- 0282  CP-SAT IS LIVE, PROPOSING INTO THE TWIN, AND THE KERNEL HAS ENACTED ITS PLANS
--       WITH REAL BOOKINGS. THE EC2 INSTANCE WAS NEVER ON THE CRITICAL PATH FOR THAT --
--       AND THE CREDENTIAL I SPENT A DAY TREATING AS MISSING WAS ALREADY SET.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live demo
-- run `1efeb1cd-f9b6-4515-8e61-2e5a04121112` (busy_day, seed 101959, started 19:30:00 UTC
-- = 2:30 PM CT). Every count below is `class='engine'` unless stated and purges with the
-- run; `ottoq_proposer_fire_log` and `ottoq_proposal_disposition_ledger` are the durable
-- witnesses.
--
-- ══ 1. THE HEADLINE ════════════════════════════════════════════════════════
--
--   CP-SAT fires on this run                        **93**  (ticks 44 -> 196)
--   fires that planned something                     **3**
--   proposals submitted through the batch door       **3**
--   ENACTED by the deterministic kernel              **2**   (each with a real booking)
--   refused by the kernel                            **1**   (`stall_reserved`)
--   OR-Tools version                        **9.15.6755**, the pin
--   both lexicographic passes                      OPTIMAL, `reproducible: true`
--
-- The two enactments carry `disposition_reason='enacted_by_kernel'` AND a matching row in
-- `ottoq_stall_bookings` on the proposed (vehicle, stall) pair. That is the whole
-- propose/dispose contract exercised end to end: an external, non-deterministic-in-
-- principle proposer plans, the shield and the decide path dispose, and the calendar --
-- with its EXCLUDE constraint -- is what records the result. Assignment plus
-- verification, not a status flip.
--
-- ══ 2. WHAT I HAD WRONG, AND IT WAS THE EXPENSIVE ONE ══════════════════════
--
-- I spent this session treating CP-SAT as blocked on rebuilding a Docker image on an EC2
-- box, and reported it to Chase as blocked on him. **`.github/workflows/proposer-loop.yml`
-- already runs the CP-SAT model against the live engine on a `*/5` cron on `main`, and its
-- `OTTOQ_DATABASE_URL` secret has been set the whole time.** Fifty scheduled runs, all
-- green. The route needs no instance, no HTTP hop, and nothing from Chase.
--
-- **Why fifty green runs produced nothing, and why "green" was the disguise.** Every one
-- finished in ~23 seconds -- install plus an `--idle-ok` exit -- because GitHub was firing
-- the schedule roughly every three hours rather than every five minutes (17:44, 14:47,
-- 11:25, 06:08, 01:02 on 09-20), and the depot was idle at each of those moments. The
-- workflow's own header predicted exactly this: *"A cron that fires at an idle depot finds
-- nothing to propose into."* `--idle-ok` is correct -- a red job every five minutes
-- teaches everyone to ignore red jobs -- but it means the difference between "the proposer
-- works" and "the proposer has never had a frame" is invisible in the conclusion column.
-- Dispatching the same workflow by hand against a live run produced the 93 fires above on
-- the first attempt.
--
-- **The lesson is the one 0250 taught in a different costume:** I read a capability's
-- status from the wrong surface. There, an unscoped stall census; here, a green check mark
-- that reports whether a job exited cleanly, not whether it did anything.

SELECT status, count(*) AS fires, sum(n_planned) AS planned, sum(n_submitted) AS submitted,
       min(tick_seq) AS first_tick, max(tick_seq) AS last_tick,
       min(fired_at)::timestamp(0) AS first_at, max(fired_at)::timestamp(0) AS last_at
  FROM public.ottoq_proposer_fire_log
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
 GROUP BY 1 ORDER BY fires DESC;

-- the enactment proof: status AND a booking on the proposed pair, not status alone.
SELECT p.status, p.disposition_reason, p.created_at::timestamp(0) AS made,
       (SELECT count(*) FROM public.ottoq_stall_bookings b
         WHERE b.vehicle_id = p.entity_id::uuid
           AND b.stall_id   = (p.proposal->>'stall_id')::uuid
           AND b.sim_run_id = p.sim_run_id) AS bookings_on_that_pair
  FROM public.ottoq_external_proposals p
 WHERE p.sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
   AND p.source = 'forward_lex'
 ORDER BY p.created_at;

-- ══ 3. THE PRODUCT FINDING: CP-SAT IS IDLE ON 90 OF 93 FIRES, FOR TWO
--       REASONS THAT ARE BOTH CORRECT ═══════════════════════════════════════
--
--   82 of 93 (88%)  every vehicle in a serviceable state was already HELD
--    8 of 93 ( 9%)  not one of the 40 charge stalls was offerable that tick
--    3 of 93 ( 3%)  planned and submitted
--
-- **Neither is a defect, and that is what makes it a finding rather than a bug.**
--
-- On reason (a), measured on the frame at 01:24 sim-clock: 33 vehicles sat in a
-- "serviceable" state and **all 33 were `charging_l2` (25) or `charging_dcfc` (8)**, so
-- every one answered `holds_charge_place` -- it is already plugged in and does not want a
-- stall assignment. `arrived_at_gate` and `staged_awaiting_service` were both **zero**.
-- The candidate population for a stall-assignment proposer was empty, and the proposer
-- said so rather than inventing work.
--
-- On reason (b), the three-gate availability rule from CLAUDE.md Part 3 is what closes it,
-- and the fire notes quote all three gates by name -- e.g. *"40 charge-capable stall(s) and
-- not one is offerable this tick (1 charger_occupied, 34 occupied, 5 reserved)"*. The
-- pointer, the calendar and the OCPP charger state each contribute, exactly as 0372 and
-- 0250 established.
--
-- **So the honest sentence about CP-SAT's contribution on one depot is a sentence about
-- OCCUPANCY, not about the solver.** With 30 of 40 charge stalls in use and the rest
-- reserved or faulted, the inside-a-site scheduling problem CLAUDE.md 2.5 hands CP-SAT is
-- a problem with almost no free variables for most of a night run. That is the
-- capacity-wall question Chase actually wants answered -- how many vehicles this depot can
-- stage, sort and orchestrate at once -- and it now has an instrument pointed at it.
--
-- **What is NOT established.** One run, one seed, one scenario, one 9-minute window. 3
-- plans is not a rate. Whether CP-SAT beats the local decide path on any KPI is untouched
-- here: that needs C5's A/B pair with the L1 shield held constant (`db/checks/0146`), and
-- nothing in this file is a comparison.

SELECT CASE
         WHEN status = 'submitted' THEN 'C planned and submitted'
         WHEN fire->>'note' = 'no plannable vehicles in frame'
           THEN 'A every serviceable vehicle already held'
         WHEN COALESCE(fire->>'error','') LIKE '%not one is offerable%'
           THEN 'B zero offerable charge stalls'
         ELSE 'D ' || COALESCE(fire->>'note', fire->>'error', '(none)') END AS why,
       count(*) AS n,
       min((fire->>'n_in_serviceable_state')::int) AS serviceable_min,
       max((fire->>'n_in_serviceable_state')::int) AS serviceable_max,
       min((fire->>'n_vehicles_held')::int)        AS held_min,
       max((fire->>'n_vehicles_held')::int)        AS held_max
  FROM public.ottoq_proposer_fire_log
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
 GROUP BY 1 ORDER BY n DESC;

-- ══ 4. THE DEFECT THIS FOUND ON THE WAY, FIXED BY `0389` ═══════════════════
--
-- The `site` descriptor CP-SAT plans against was a constant in two files, and the engine's
-- own cap is a third number neither read. `solvers/cpsat/model.py:773-774` spends
-- `power_cap_kw_hard` as a CP-SAT **cumulative capacity** and as a `NewIntVar` bound, so it
-- is the constraint, not documentation:
--
--   the two constants                    2500 kW hard / 1620 kW soft
--   `ottoq_active_charge_cap_kw`, live    795 -> 659.5 -> 595.3 kW, three consecutive reads
--
-- cuOpt reads the live cap before it proposes (`ottoq-cuopt-propose` does the RPC); CP-SAT
-- never did. So the two proposers were handed different worlds, and CP-SAT's was up to
-- 4.2x more permissive than the one the decide path enforces. **No violation is claimed:**
-- the observed plans peaked at 19 kW, three orders of magnitude under either number, so the
-- defect is that nothing prevented it. `0389` derives the descriptor and tightens only --
-- with no live cap in force it returns 2500/1620 exactly, which is why adopting it on a
-- live run was safe.
--
-- **And the fix had a second defect inside it that only the live path could expose.**
-- OR-Tools 9.15.6755 refuses a non-integral bound outright -- `Domain(arg0: int, arg1:
-- int)`, invoked with `0, 659.5`. The constants were integral, so the descriptor's first
-- form would have crashed the solver on the first tick that tightened the cap and on no
-- tick before it. Caught by asking the pinned solver rather than reasoning about it, and
-- now floored in SQL with assertions on both sides. Same shape as `0384`: a new mechanism's
-- worst input is the one its predecessor could never produce.

SELECT * FROM public.ottoq_assert_site_descriptor(
  '11111111-1111-1111-1111-111111111111',
  (SELECT sr.sim_run_id FROM public.ottoq_sim_runs sr
    WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
      AND sr.status = 'running' AND COALESCE(sr.run_by,'') <> 'cert_harness'
    ORDER BY sr.started_at DESC LIMIT 1));

-- ══ 5. THE ONE THING STILL OUTSIDE THE BACKEND, NAMED EXACTLY ══════════════
--
-- The **edge-function** route -- Nemotron analyses the frame, hands off to a solver, the
-- kernel disposes -- is fully built and fully deployed, and it is the one route that does
-- need the EC2 instance. It has fallen back to cuOpt on every chain: 9 of 9 on this run,
-- `failed: 0`, `reachable: true`. The instance is UP. It is serving a build that predates
-- `app/optimizers/assignment_cpsat.py`, so `/assign` answers 2xx with a pre-CP-SAT body and
-- the edge function correctly refuses it.
--
-- **The engine now says this itself, in the instance's own words.** The old message,
-- *"intelligence /assign returned an invalid proposer envelope"*, is true and nearly
-- useless -- it is exactly what a healthy box running an old image looks like, and that
-- ambiguity is what cost the day. The handler now reads `/health` on that path, and the
-- fire record at 19:46:34 reads:
--
--   intelligence /assign returned an invalid proposer envelope; /health does not list
--   cp_sat_forward_lex -- THE RUNNING IMAGE PREDATES CP-SAT. Redeploy the service
--   (ottoq-intelligence deploy workflow). /health said:
--   {"ok":true,"service":"ottoq-intelligence","optimizers":["energy_mpc"]}
--
-- That is a container rebuild, not code: `ottoq-intelligence` `main` already carries the
-- optimizer, the Dockerfile already clones `otto-q-core` at a pinned ref so the image is
-- self-contained, and `.github/workflows/deploy.yml` already asserts on that optimizer
-- list rather than on a 200. It needs three repository secrets (`EC2_HOST`, `EC2_USER`,
-- `EC2_SSH_KEY`) that only Chase can add -- a private key is not something an agent can
-- mint -- after which it is one dispatch.
--
-- **State it as what it is: CP-SAT does not wait on that.** The CI seat proposes and
-- enacts today. What the instance unlocks is the *agent chain's* solver seat -- Nemotron
-- choosing an objective and CP-SAT solving under it -- which is a different and additive
-- capability, not the difference between CP-SAT working and not.

SELECT left(detail->'agent_handoff'->>'fallback_reason', 300) AS reason,
       count(*) AS chains, max(called_at)::timestamp(0) AS last_at
  FROM public.cuopt_invocation_log
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
   AND detail->'agent_handoff' ? 'fallback_reason'
 GROUP BY 1 ORDER BY chains DESC;

-- ══ 6. ONE MORE THING I GOT WRONG TONIGHT, RECORDED BECAUSE IT NEARLY
--       PURGED 1.1M ROWS FOR NOTHING ══════════════════════════════════════
--
-- `ottoq_start_demo_run` exceeds the Management API's 120-second ceiling, so the run was
-- started detached through a one-shot `pg_cron` job. My starter declared the result
-- `uuid`; the function returns **`jsonb`**. Every attempt therefore purged 1,132,768 rows,
-- built the run, and then raised `22P02` on the assignment -- rolling the whole thing back,
-- twice, and logging `FAILED` with the complete successful receipt embedded in the error
-- text. Nothing was lost, because the purge rolled back with it. The tell was that the
-- error message contained a perfectly good `sim_run_id`: a function that "failed" while
-- handing back its own success is a caller-side type error, not an engine fault.

-- Three failures at 19:27, 19:28 and 19:29, each carrying a complete successful receipt
-- (`"sim_run_id": "11192ad5-..."` / `"6d4a2a0a-..."` / `"b6628880-..."`, each
-- `"rows_purged": 1132768`), then at 19:30:
--
--   started 1efeb1cd-f9b6-4515-8e61-2e5a04121112 purged=1132768
--
-- **`public.claude_run_starter_log` and `public.claude_start_demo_once` were dropped once
-- this file recorded them**, deliberately: CLAUDE.md C1 step 7 already carries ~100
-- unclassified scratch tables in `public` as an open finding, and leaving a 101st behind
-- while quoting that finding would be its own kind of failure. The receipt above is the
-- record; the table is not. The general point stands for any detached starter: declare the
-- return type from `pg_get_function_result`, not from what the name suggests it returns.
SELECT pg_get_function_result(oid) AS ottoq_start_demo_run_actually_returns
  FROM pg_proc WHERE proname = 'ottoq_start_demo_run';
