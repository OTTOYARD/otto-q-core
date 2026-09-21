-- 0269  THE SITE'S TOTAL LOAD WAS ALWAYS A STORED COLUMN. NO RULE IN THE ENGINE
--       TAKES IT AS A SUBJECT, AND THE ONE THAT NAMES THE CAP METERS THE WRONG
--       QUANTITY.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- The measurement behind `0374` and its correction `0375`. G89, which BUILD_QUEUE
-- filed as "two independently legal decisions summed to 239 kW over the depot's
-- declared service maximum", re-measured before anything was built.
--
-- ══ 1. THE FINDING HOLDS, AND THE MECHANISM IS AN INCOMPLETE METER ═══════════
--
-- G89 reconstructed the sum by hand. It did not need to: **`grid_import_kw` IS the
-- site total.** Across all 8,050 snapshots on this depot it equals
-- `GREATEST(ev - bess_output + building + lighting - solar, 0)` in **8,050 of 8,050**,
-- worst residual **0.10 kW**. The excursion is therefore not an inference, it is a
-- reading: **2,738.80 kW** on run `5b37ee46` at 2026-09-19 06:56:09 UTC, against
-- `depots.service_max_kw` **2,500**.
--
-- The mechanism, which is the part worth keeping:
--
--   EN.001.grid_capacity_ceiling   is the ONE rule naming `service_max_kw`
--     its load term    ottoq_depot_current_demand_kw
--       which is       twin.ottoq_sim_compute_charger_load_kw
--       which is       SUM(ocpp_sessions.last_meter_value->>'power_kw')
--       and nothing else -- no BESS, no base load
--
-- So the rule asks *"EV_now + EV_requested <= service_max_kw"*. A true question,
-- correctly answered, **about a quantity that is not the site's load.** At the
-- excursion: EV **1,691.8** (under its own 1,800 nameplate, so EN.001 passed and was
-- right to) + BESS **charging at 968** (`bess_output_kw = -968`; `bess_dispatch`
-- evaluates exactly one rule, EN.003.bess_limits, which checks the battery's own
-- envelope) + base **79** = **2,738.8**. Each decision legal under the only rule
-- that judges it. **No rule anywhere takes the sum as its subject.**

SELECT s.sim_run_id, s.timestamp, s.grid_import_kw, s.total_ev_charging_kw,
       s.bess_output_kw, s.building_load_kw, s.lighting_load_kw, s.solar_generation_kw,
       d.service_max_kw, d.dcfc_max_concurrent_kw,
       round(s.total_ev_charging_kw - s.bess_output_kw
             + s.building_load_kw + s.lighting_load_kw - s.solar_generation_kw, 1) AS reconstructed
  FROM public.site_energy_snapshots s
  JOIN public.depots d ON d.id = s.depot_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
   AND s.grid_import_kw > d.service_max_kw;

-- The identity that lets `0374` read the stored total instead of summing the parts
-- itself. It matters that this is asserted rather than assumed: `db/checks/0264` is
-- the night's lesson that a census of ours disagreeing with the engine's own reading
-- is a defect in the census, and the way not to repeat it is to have only one meter.

SELECT count(*) AS snaps,
       count(*) FILTER (WHERE abs(s.grid_import_kw
               - GREATEST(s.total_ev_charging_kw - s.bess_output_kw
                          + s.building_load_kw + s.lighting_load_kw
                          - s.solar_generation_kw, 0)) <= 0.5)        AS reconstructs,
       round(max(abs(s.grid_import_kw
               - GREATEST(s.total_ev_charging_kw - s.bess_output_kw
                          + s.building_load_kw + s.lighting_load_kw
                          - s.solar_generation_kw, 0))), 2)           AS worst_residual_kw
  FROM public.site_energy_snapshots s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';

-- ══ 2. THE RATE IS 1 IN 8,050 AND THE DISTRIBUTION IS WHY THAT IS NOT COMFORT ═
--
-- The honest rate first, because it is the number that would be quoted against us:
-- **1 of 8,050 snapshots over the contract, in 1 of 9 runs, worst excess 238.8 kW.**
-- Read alone that says the site essentially never exceeds its service contract, and
-- it would be fair to ask why this is a finding at all.
--
-- The distribution is the answer:
--
--   0-300 kW      6,229        1,202-1,494       34
--   301-600         883        1,515-1,714       15
--   600-893         777        **1,800-2,700      0**
--   900-1,198       111        2,739              1
--
-- **Buckets 7, 8 and 9 are empty.** The site has never once operated between 1,714
-- and 2,739 kW. It does not climb toward the cap and occasionally tip over it; it
-- sits comfortably below and then takes a single ~1,000 kW step clean over. A
-- megawatt discontinuity in a metered load is not how demand builds -- it is the
-- signature of a second decision ADDING, and ~1,000 kW is the BESS charge magnitude
-- (min `bess_output_kw` here is -1,200).
--
-- **So the rarity is the rarity of the coincidence, not evidence of anything
-- preventing it.** Nothing prevents it. This is the difference between a system that
-- rides a limit and one that is blind to it, and only the second kind produces an
-- empty middle. A 1-in-8,050 event that opens the utility's breaker is an unguarded
-- tail, not an acceptable residual.

SELECT width_bucket(s.grid_import_kw, 0, 3000, 10) AS bucket,
       round(min(s.grid_import_kw), 0) AS lo,
       round(max(s.grid_import_kw), 0) AS hi,
       count(*) AS snaps
  FROM public.site_energy_snapshots s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 1;

-- ══ 3. WHY THE LEDGER HAD TO BE EVIDENCE, DEMONSTRATED RATHER THAN ARGUED ════
--
-- `site_energy_snapshots` is registered `class='engine'` -- correct for it, 1,139
-- snapshots per run is working data -- so **every excursion this depot has ever had
-- is deleted by the next demo run.** The one above survives only because no run has
-- started since. "How often has this site exceeded its service contract" was a
-- question no surviving table could answer: exactly the 0231 fragility that `0340`
-- closed for model calls and `0364` for proposal outcomes, third instance, same
-- shape -- append-only, `class='evidence'`, **no FK to `ottoq_sim_runs`**.
--
-- `0374` backfilled the surviving evidence for that reason, at `source_kind
-- ='backfill'` so it can never be mistaken for live capture: **16 readings, 1
-- excursion and 15 high_water**, the second tier existing so a purge cannot erase
-- how close the site ran and leave the next excursion looking as isolated as this
-- one did.

SELECT * FROM public.ottoq_site_power_ledger;

-- ══ 4. AND I SHIPPED A COLUMN THAT SAYS THROTTLE THE VEHICLES ═══════════════
--
-- `0374` exposed `usual_dominant_component`, and its own COMMENT claimed it answered
-- *"what pushed us over, which is the first question and the one that decides
-- whether enforcement should refuse a vehicle or defer a battery."* **It does not.**
-- It computes the largest single load, and on the only excursion in evidence the two
-- questions disagree:
--
--   dominant_component                    = **ev_charging**  (1,691.8, the biggest)
--   total with the BESS charge deferred   = **1,770.8 kW**   (729 kW UNDER the cap)
--
-- A reader following that column throttles vehicles when deferring the battery
-- clears the excursion outright. Corrected by `0375`, which renames it to
-- `largest_component` and adds the pair that actually decides:
-- `excursions_bess_deferral_clears` and `excursions_needing_ev_action`, asserted in
-- its P3 to partition the excursions. Measured now: **1, 1, and 0.**
--
-- **AND BOTH REMOVALS CLEAR THE CAP THERE, WHICH IS WHY ARITHMETIC CANNOT PICK.**
-- Dropping the EV load would also clear it. The discriminator is not magnitude, it
-- is that a battery's charge timing is schedulable arbitrage that can move to any
-- cheaper hour, while a vehicle mid-charge is a service commitment with a
-- required-ready-time attached. That is a judgement about the product, not a fact
-- about the numbers, and `0375` states it in the view's comment rather than
-- computing it into a column that would look like arithmetic.
--
-- Two process notes, both earned in twenty minutes:
--   * **The defect was found by reading the instrument's own output once, right
--     after applying it.** Nothing else would have caught it -- the column was
--     internally consistent and correctly computed. It was the NAME and the comment
--     that were wrong, which is the class of defect no assertion catches.
--   * **Same shape as `0371` on `0367`.** Both are the instrument being wrong rather
--     than the finding, and both were mine, filed the same night.

SELECT l.severity_tier, l.total_import_kw, l.cap_kw, l.excess_kw,
       l.ev_charging_kw, l.bess_charging_kw, l.base_load_kw,
       l.dominant_component,
       round(l.total_import_kw - l.bess_charging_kw, 1)              AS total_if_bess_deferred,
       (l.total_import_kw - l.bess_charging_kw) <= l.cap_kw          AS bess_deferral_clears,
       (l.total_import_kw - l.ev_charging_kw)   <= l.cap_kw          AS ev_removal_also_clears,
       l.source_kind
  FROM public.ottoq_site_power_excursion_ledger l
 WHERE l.severity_tier = 'excursion'
 ORDER BY l.excess_kw DESC;

-- ══ 5. WHAT IS STILL CHASE'S, AND WHY THIS IS THE CP-SAT ARGUMENT ═══════════
--
-- **MEASURED ONLY.** `0374` changes no assignment, refuses nothing, and does not
-- touch EN.001. Widening EN.001's meter to the full site total would change which
-- actions are feasible, and per CLAUDE.md 2.9a the L1 shield defines the feasible
-- set -- so that is a change to the problem definition, and per the blind-spot
-- promotion doctrine it lands MEASURED first and ENFORCED only after a round shows
-- what it would have refused. `0370` is the precedent from earlier the same night
-- and `0374` is deliberately its twin in shape.
--
-- **The enforcement choice is genuinely open, and probably is not "refuse".**
-- EN.001's own other branch already names the remedy: `engage_bess_or_defer`. At the
-- excursion the battery WAS the load. The cheap fix is an energy-policy decision
-- about arbitrage against demand charges, not a safety veto, and the ledger is what
-- makes that an informed trade rather than a guess.
--
-- **AND IT IS THE FIRST MEASURED INSTANCE OF THE CONSTRUCT cuOpt CANNOT EXPRESS.**
-- A shared site power cap across concurrent activities is a cumulative resource --
-- one of the four load-bearing constructs of CLAUDE.md 2.3 that R-12 established are
-- absent from cuOpt 26.08, alongside disjunctive machine, sequence-dependent gap and
-- any scheduling solver family. Until tonight that was a vendor-documentation
-- argument. It is now an observed excursion on a real run: two legal decisions, no
-- shared constraint between them, 238.8 kW over a utility service contract. **That
-- belongs in the CP-SAT case, and it is stronger than the doc citation because it is
-- our own run.**

SELECT r.rule_code, r.severity, count(e.*) AS evaluations,
       count(*) FILTER (WHERE NOT e.passed) AS failures
  FROM public.ottoq_rules r
  LEFT JOIN public.ottoq_rule_evaluations e ON e.rule_code = r.rule_code
  LEFT JOIN public.ottoq_sim_runs sr ON sr.sim_run_id = e.sim_run_id
                                    AND sr.depot_id = '11111111-1111-1111-1111-111111111111'
 WHERE r.rule_code IN ('EN.001.grid_capacity_ceiling','EN.003.bess_limits','EN.005.grid_event_hardstop')
 GROUP BY 1,2 ORDER BY 1;
