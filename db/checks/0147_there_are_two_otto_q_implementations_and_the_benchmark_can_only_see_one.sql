-- =====================================================================
-- 0147 — There are two OTTO-Q implementations, and the benchmark can
--        only see one of them.
--
-- Finding id: G30
-- Opened:     2026-09-08 22:12 UTC (5:12 PM CT)
-- Trigger:    Chase asked whether the "Otto-twin repo" was being
--             referenced. It was not. Reading it produced this.
-- Status:     OPEN — decision required from Chase (see §6)
--
-- ---------------------------------------------------------------------
-- 1. WHAT WAS FOUND
-- ---------------------------------------------------------------------
-- The repo OTTOYARD/ottoyarddepot-sim (43 MB, private, last pushed
-- 2026-09-03) contains a second, independent OTTO-Q implementation:
--
--     src/lib/ottoq/*.ts   7,685 lines of TypeScript
--     channels · contracts · coverage · advisors · shield · pipeline
--     commands · commandBus · energyController · executors · worldBoot
--
-- It also contains docs/OTTOQ-TWIN-BOUNDARY.md (dated 2026-07-28,
-- "Status: target architecture, not yet built") which states the
-- intended relationship between the two, and which contains this
-- sentence -- the reason this check exists:
--
--     "Rename `otto_q` -> `twin_internal`. As it stands the A/B harness
--      compares a stand-in against baselines and labels the winner
--      'OTTO-Q', so it is measuring the wrong thing. Real OTTO-Q must
--      enter the benchmark as an external participant, or the
--      comparison proves nothing."
--
-- That is a direct hit on the A/B rig currently being built here
-- (0145, 0146, migration 0230). It must be answered before that rig
-- publishes a number, not after.
--
-- ---------------------------------------------------------------------
-- 2. THE MEASUREMENTS (all read-only, 2026-09-08 22:0x UTC)
-- ---------------------------------------------------------------------
-- 2a. The database has run exactly one policy, ever.
SELECT 'a_policy_census' AS check, policy, count(*) AS runs, max(started_at) AS latest
FROM public.ottoq_sim_runs GROUP BY policy ORDER BY 3 DESC;
-- Observed: otto_q = 845 runs. No other value. No fifo run, no greedy
-- run has ever been recorded. This is 0145's finding reached by a
-- second, independent route: the A/B substrate is unexercised.

-- 2b. The TypeScript stack cannot write to the database.
--     (measured in the repo, not here -- recorded for the record)
--       grep -rE "\.(rpc|insert|update|upsert|delete)\(" src/lib/ottoq/*.ts
--       -> 0 matches, excluding tests.
--     Its executors (src/lib/ottoq/executors.ts) delegate to
--     `twinMotionDriver` and `SiteEnergyController` -- both browser-side
--     objects. Its decisions terminate in one browser tab's memory.
--     They produce no run id, no decision row, no SDR, no event.

-- 2c. There is still no inbound command path. The July doc named this
--     gap; it is open six weeks later, unchanged.
--     NOTE ON THIS PREDICATE. The first version of it asked whether
--     the function BODY mentioned a command payload
--     (prosrc ~* 'jsonb.*command'). That returned true -- and was
--     wrong. It matched the RETURN envelope,
--     jsonb_build_object(...,'vehicle_commands_confirmed',...), not an
--     input. A test that can be satisfied by the answer instead of the
--     question is not a test. The evidence is the argument list, so
--     that is what is asserted:
SELECT 'c_ingest' AS check,
       p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       -- an ingest path must accept a payload; a payload must be json.
       EXISTS (SELECT 1 FROM unnest(p.proargtypes) AS t(oid)
               WHERE t.oid IN ('json'::regtype, 'jsonb'::regtype,
                               'json[]'::regtype, 'jsonb[]'::regtype))
         AS takes_a_payload
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'ottoq_api_twin_apply_commands';
-- Observed: args = (p_sim_run_id uuid, p_clock timestamptz),
-- takes_a_payload = false. Its body calls ottoq_sim_confirm_commands
-- and returns a count. Nothing can instruct the twin from outside.
-- Nothing in ottoyarddepot-sim calls it, either.

-- ---------------------------------------------------------------------
-- 3. WHY THE JULY DOC'S VERDICT IS NO LONGER THE RIGHT ONE
-- ---------------------------------------------------------------------
-- The doc's own comparison table awarded the TypeScript stack five
-- capabilities the SQL path lacked: channel contract, integrity /
-- provenance, L1 safety shield, command contract + acks, explainability.
-- That table was true on 2026-07-28. It is false today. Every one of
-- those capabilities now exists server-side:
SELECT 'd_capability' AS check, cap, obj,
  CASE WHEN EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                    WHERE c.relname=obj AND n.nspname IN ('public','twin','ottoq')) THEN 'relation'
       WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE p.proname=obj AND n.nspname IN ('public','twin','ottoq')) THEN 'function'
       ELSE 'ABSENT' END AS present
FROM (VALUES
  ('L1 safety shield',        'ottoq_rules'),
  ('command contract',        'ottoq_vehicle_commands'),
  ('command ack',             'ottoq_ack_vehicle_command'),
  ('explainability',          'ottoq_decisions'),
  ('provenance',              'ottoq_vehicles_state_change'),
  ('channel: fleet_condition','ottoq_twin_fleet_condition'),
  ('channel: labor',          'ottoq_twin_labor_window'),
  ('channel: offsite',        'ottoq_twin_offsite_window'),
  ('channel: wear',           'ottoq_twin_wear_window'),
  ('channel: run_context',    'ottoq_twin_run_context'),
  ('recall ledger',           'ottoq_recall_decisions'),
  ('SDR terminus',            'ottoq_service_detail_records'),
  -- negative control: the probe must be able to say ABSENT at all.
  ('CONTROL: must be absent', 'ottoq_this_object_does_not_exist')
) AS t(cap, obj) ORDER BY 2;
-- Observed 2026-09-08: 12 of 12 present, control ABSENT.
--
-- Divergence, stated as dates rather than opinion:
--   src/lib/ottoq  last commit 2026-08-13  (26 days ago)
--   the SQL path   migrations 0154..0230 since, plus 30 certification
--                  rounds, plus G2..G29.
-- The two implementations have not been reconciled in six weeks. The
-- doc assumed the TypeScript one would win the merge. The build went
-- the other way, and nobody wrote that down.

-- ---------------------------------------------------------------------
-- 4. WHAT IS ACTUALLY TRUE OF EACH, TODAY
-- ---------------------------------------------------------------------
--                        | SQL path (`otto_q`)      | TS stack
--   ---------------------+--------------------------+------------------
--   moves the world      | yes, 845 runs            | no, never
--   leaves a run id      | yes                      | no
--   L1 shield            | yes, 52 rules, logged    | yes, in-process
--   provenance           | yes (0228)               | in-bundle only
--   command ack cycle    | yes, server-side         | in-memory
--   certified determinism| yes, 14 atoms, 30 rounds | never tested
--   reads the 5 feeds    | no -- reads tables direct| yes, over RPC
--   refusable instruction| no -- writes world state | yes, by design
--
-- The last two rows are the ones the TypeScript stack still wins, and
-- they are not cosmetic. They are the whole content of the July doc's
-- Rule 1 and Rule 2: OTTO-Q must not write world state, and the twin
-- must be able to refuse. The SQL path violates Rule 1 structurally --
-- it *is* the twin's tick -- and therefore cannot demonstrate Rule 2.
--
-- So neither implementation is the product. One can act but cannot be
-- refused; the other can be refused but cannot act.

-- ---------------------------------------------------------------------
-- 5. CONSEQUENCE FOR THE A/B RIG NOW BEING BUILT
-- ---------------------------------------------------------------------
-- This is the second methodological trap found before publishing, and
-- it is larger than the first.
--
--   0146 (the shield asymmetry): the baselines do not pay the safety
--        cost the contestant pays, so a naive comparison flatters them.
--
--   0147 (this): the contestant labelled `otto_q` is the twin's own
--        internal scheduler. Running it against fifo and greedy -- also
--        twin-internal -- and publishing the winner as "OTTO-Q" is an
--        internal comparison wearing a product's name.
--
-- Neither invalidates the determinism certification. That work
-- certified that the twin's decide path is reproducible, which is true,
-- valuable, and independently useful. It invalidates only the sentence
-- "OTTO-Q beat the baselines by X%", which has not been written yet.
-- The rig catches this before the number exists, which is the point of
-- building the rig before the claim.

-- ---------------------------------------------------------------------
-- 6. THE DECISION THIS FORCES (Chase's, not mine)
-- ---------------------------------------------------------------------
-- Three coherent answers. They are mutually exclusive.
--
-- (A) CONVERGE ON SQL. Accept that the server-side path became the
--     product. Rename the ledger policy `otto_q` -> `twin_internal`
--     for the *baseline* sense, and stand up a genuine second policy
--     that consumes the five published feeds instead of reading tables
--     directly. Cost: build the feed-consuming decide path. Benefit:
--     everything certified stays certified; one implementation.
--     Retires: 7,685 lines of TypeScript to reference status.
--
-- (B) CONVERGE ON TYPESCRIPT. Build the missing command ingest
--     (`ottoq_api_twin_apply_commands` grows a payload parameter and a
--     refusal vocabulary), move the TS stack out of the browser into a
--     service, and let it enter the benchmark as an external
--     participant exactly as the July doc intended. Cost: the ingest
--     path, the service, and re-certifying determinism across a network
--     boundary -- the 14-atom pair currently runs in one transaction and
--     could not span a service call unchanged. Benefit: Rules 1 and 2
--     become real, which is what makes a physical-depot claim honest.
--
-- (C) BOTH, DELIBERATELY. SQL path = the certified deterministic core
--     and the benchmark baseline. TS stack = the external participant.
--     This is the only answer under which the A/B comparison means what
--     its label says, and it is the most work.
--
-- Recommendation: (C), sequenced as (A)-then-(B) -- i.e. relabel now,
-- ship the ingest path next, and hold every comparative number until
-- an external participant exists to make the comparison honest.
--
-- ---------------------------------------------------------------------
-- 7. WHAT SHIPS IMMEDIATELY REGARDLESS OF THE DECISION
-- ---------------------------------------------------------------------
-- Two things are true under all three answers and do not wait:
--
--   i.  The label. `otto_q` in ottoq_sim_runs.policy is the twin's
--       internal decide path. It should say so. This is 0146's third
--       preference ("relabel the baselines honestly regardless")
--       arriving from a different direction at the same conclusion.
--
--   ii. The freeze. No comparative number -- no "%
--       better than FIFO", no policy ranking -- leaves this repo until
--       either (B) lands or the label is unambiguous. Absolute,
--       single-policy numbers (peak kW, turns, p95) are unaffected;
--       they are properties of a run, not of a contest.
--
-- ---------------------------------------------------------------------
-- 8. WHAT THIS CHECK DOES NOT CLAIM
-- ---------------------------------------------------------------------
-- - It does not claim the TypeScript stack is better. It has never been
--   run against a certified world and has no determinism evidence.
-- - It does not claim the SQL path is wrong. It is the only thing that
--   has ever moved a vehicle, and it is certified to 14 atoms.
-- - It does not claim the July doc is wrong. It was right on its date
--   and its Rules 1 and 2 remain the correct architecture. Its
--   capability table is what expired.
-- - It does not claim ottoyarddepot-sim holds simulation *data*. It does
--   not. The only large committed file is unreal/layoutSeed.json
--   (133 KB of depot geometry). Every sim run, event, and booking lives
--   in this database. The repo holds the renderer, the control API, and
--   the second implementation.
-- =====================================================================
