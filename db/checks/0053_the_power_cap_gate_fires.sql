-- 0053 — PROOF THAT THE POWER-CAP GATE FIRES (2026-08-31, verifies migration 0132)
-- ============================================================================================
-- A gate that never refuses anything is indistinguishable from the dead accounting it replaced,
-- so 0132 is not accepted on "it applied cleanly". This is the falsifiable test.
--
-- FIRST ATTEMPT, AND WHY IT PROVED NOTHING. The plan was: run arm A with a 40 kW cap injected as
-- an ottoq_energy_commands setpoint, arm B with only the 2500 kW physical cap, and compare.
-- Both arms returned IDENTICAL counts (48 refusals / 671 enacted / 885 decisions), which is the
-- signature of a test with no control rather than a working one. Cause: the engine issues its
-- OWN charge_cap_kw commands during a run (6 per run here, up to 1325 kW), and
-- ottoq_active_charge_cap_kw takes the latest by issued_at -- so the 02:00 injection was
-- superseded within a tick and both arms ran at the same ~1271 kW effective cap. The injection
-- never bound. Recorded because the failure mode is reusable: anything injected at run start on
-- a channel the engine also writes will be overwritten by the engine.
--
-- THE TEST THAT DISCRIMINATES. Same seed (424242), same scenario, same 6 ticks, same depot; the
-- ONLY difference is the kill switch, scoped to one run via ottoq_policy_params:
--     arm gate_on   (policy absent -> default 1)   run 32e87a36
--     arm gate_off  (enforce_site_charge_cap = 0)  run 550f7d60
-- RESULT:
--     arm        refused_site_power   enacted   decisions
--     gate_on            48             671        885
--     gate_off            0             676        885
-- Three things this establishes, each of which could have come out otherwise:
--   1. THE GATE FIRES. 48 refusals under the engine's own live cap (~1271 kW effective), all
--      carrying outcome_status='deferred_site_power_cap'. Before 0132 the count was
--      structurally zero -- no code path could refuse a charge for power.
--   2. THE REFUSALS ARE ATTRIBUTABLE TO THE GATE. With the switch off, on an otherwise identical
--      run, the count is exactly 0. The refusals are not incidental to some other change.
--   3. THE AUDIT TRAIL IS INTACT. decisions_total is 885 in BOTH arms: a refusal replaces an
--      enactment, it does not skip the decision record. Nothing disappears from the ledger.
-- Note the asymmetry worth understanding: 48 refusals cost only 5 enactments (671 vs 676). A
-- refused vehicle re-enters the cursor on the next tick and is mostly served slightly later, so
-- the cap DELAYS work rather than denying it -- the correct behaviour for a power constraint,
-- and the reason peak_site_kw can now be moved without throughput collapsing.
--
-- STILL OUTSTANDING (deliberately, not overlooked):
--   * The six-column determinism matrix must be re-run: 0132 is behaviour-changing and the
--     certification in db/checks/0050 predates it. Batched with the 0051 energy fix and the
--     remaining 0052 gaps so the ladder is paid once, not per change.
--   * The cap the gate enforces is still the engine's own MPC setpoint tightened by the physical
--     limit. Whether ~1271 kW is the RIGHT cap for this depot is a separate question from
--     whether the cap is enforced, which is all this proves.
--
-- Re-runnable evidence for the two recorded runs.
WITH arms(arm, run) AS (VALUES
  ('gate_on',  '32e87a36'), ('gate_off', '550f7d60')
)
SELECT a.arm, a.run,
       count(*) FILTER (WHERE d.outcome_status='deferred_site_power_cap') AS refused_site_power,
       count(*) FILTER (WHERE d.outcome_status='enacted')                 AS enacted,
       count(*)                                                           AS decisions_total
FROM arms a
LEFT JOIN public.ottoq_decisions d ON left(d.sim_run_id::text,8) = a.run
GROUP BY a.arm, a.run ORDER BY a.arm DESC;
