import assert from "node:assert/strict";
import test from "node:test";

import { ruleNineDirective } from "../edge-functions/_shared/agent_rule_nine.ts";

// Real directive texts from ottoq_decisions (orchestrator_agent passes), read 2026-10-13. Of the 7,566 distinct directive
// texts on record, 127 match a SQL superset of the lint's patterns; with numbers masked they are the 15 templates below
// (10 refused, 5 passed). The 114 that set a charge target of 80% are refused; the 13 that say "do not hold vehicles or
// shorten charges" pass. CLAUDE.md rule 9: every car charges
// to its owner's target (100% unless the owner set less), and no service it needs is skipped or deferred.
const REFUSED = [
  "Waymo-AV-026 (arrived_at_gate, 24% SoC): DCFC blocked by pack_temp_high. Assign to L2 stall; monitor temp decay. If temp clears within 30 min, move to DCFC for rapid charge to 80% ready floor.",
  "Zoox-002 (en_route_to_depot, 76% SoC, due in 20 min): DCFC blocked by pack_temp_high. Pre-assign L2 stall on arrival; if temp clears, escalate to DCFC for rapid top-up to 80% ready floor.",
  "Zoox-AV-075 (49% SoC, arrived_at_gate, standard priority, deadline -35m) — address open fault (severity rank 1), sensor calibration (89%), and tread (2.5mm); charge to 80%+ for readiness",
  "Tesla-AV-062 (49% SoC, arrived_at_gate, critical priority, deadline -111m) — no DCFC block reported; prioritize immediate DCFC charge to 80%+; vehicle 111 minutes overdue for deployment",
  "Service backlog: 15 vehicles waiting for service (max 24.2 min). General tech pool overloaded (3 busy of 10 total). Consider adding tech capacity or deferring non-critical services.",
  "Waymo-AV-007 (49% SoC, arrived_at_gate, critical priority, deadline -137m) — prioritize fault resolution (severity rank 4) and charge to 80%+; vehicle 137 minutes overdue for deployment",
  "Waymo-AV-026 (charging_l2, 32% SoC, due in 106 min): DCFC blocked by pack_temp_high. Monitor temp decay; if clears within 30 min, move to DCFC for rapid charge to 80% ready floor.",
  "Waymo-AV-030 (49% SoC, arrived_at_gate, standard priority, deadline -170m) — DCFC blocked by pack_temp_high; prioritize thermal cooldown then immediate DCFC charge to 80%+; vehicle 170 minutes overdue for deployment",
  "Waymo-AV-037 (78% SoC, staged_awaiting_service, soh_derate) cannot DCFC; route to L2 for top-up to 80% ready floor. 138 min to deploy — no rush.",
  "Waymo-AV-037 (79% SoC, charging_l2, soh_derate blocking DCFC): continue L2 charging to 80% ready floor. 134 min to deploy — no rush.",
  "Zoox-AV-087 (49% SoC, arrived_at_gate, standard priority, deadline -78m) — DCFC blocked by pack_temp_high, sensor 89%; prioritize thermal cooldown then immediate DCFC charge to 80%+; vehicle 78 minutes overdue for deployment",
  // shapes the corpus has not shown yet, written the way an operator would read them
  "Cap charging at 90% until the evening wave clears.",
  "Stop charging the Zoox cars at 85% to free DCFC.",
  "End sessions once cars reach 80% so the line moves.",
  "Skip the exterior wash on Waymo-AV-012 to release it sooner.",
  "Charge the boot cohort only to 70% before the morning push.",
];

const PASSED = [
  "10 attention vehicles overdue for deploy (11–246 min). All below 80% SoC ready floor. DCFC blocked: 9 pack_temp_high (wait clears), 7 cell_balance_overdue (needs service), 6 soh_derate (permanent).",
  "10 vehicles below 80% ready floor (p10=80%, min=13%). 30 charge atoms pending, 19 in EV queue. 0 DCFC + 0 L2 free — all chargers occupied.",
  "10 cars under 45% SoC placed on L2 by kernel (low_on_l2=10). With 30 free L2 and 46 arriving in 60 min, move critical low-SoC cars to DCFC to prevent L2 blocking.",
  "32 vehicles waiting for 0 free chargers (L2: 0/30, DCFC: 0/10). Per planner lesson 'more_cars_than_chargers', refusals are capacity findings, not planner faults. Do not hold vehicles or shorten charges.",
  "35 vehicles wait for 0 free chargers; planner's next offer is a capacity finding, not a fault. Do not hold vehicles or shorten charge.",
  "Charging capacity fully utilized: 32 vehicles waiting for 0 free chargers (L2: 0/30 free, DCFC: 0/10 free). Per planner lesson 'more_cars_than_chargers', refusals for stall_occupied/reserved are capacity findings, not planner faults. Do not hold vehicles or shorten charges.",
  "Planner lesson: more_cars_than_chargers — 52 cars wait for 0 free chargers. Refusals for stall_occupied/stall_reserved are capacity findings, not planner faults. Do not hold vehicles or shorten charges.",
  "Service backlog: 34 vehicles waiting (p50 wait 21 min, max 76 min). 0 free chargers (L2: 0/30, DCFC: 0/10). Planner lesson: more_cars_than_chargers — refusals for stall_occupied/stall_reserved are capacity findings, not planner faults. Do not hold vehicles or shorten charges.",
  "11 vehicles below 80% ready floor (p10=83%, min=13%). 29 charge atoms pending, 19 in EV queue. 10 DCFC + 30 L2 free. Release vehicles to charge immediately — no holding.",
  "Waymo-AV-035 is charging at 13% on NASH-L2-STALL-04 after 485 minutes in line.",
  "Charge every car to 100%; never stop a charge at 80%.",
  "Zoox-AV-075 needs sensor calibration (89%) before it leaves.",
];

test("rule 9: a directive that sets a charge target under 100% or defers a service is refused, with the words it matched", () => {
  for (const text of REFUSED) {
    const v = ruleNineDirective(text);
    assert.equal(v.ok, false, `passed but should be refused: ${text}`);
    assert.match(v.reason, /^rule_9_(charge_target|service):/);
    assert.ok(v.matched.length > 0 && text.toLowerCase().includes(v.matched.toLowerCase()), v.matched);
  }
});

test("rule 9: a directive that describes state, or restates the rule, passes", () => {
  for (const text of PASSED) {
    const v = ruleNineDirective(text);
    assert.equal(v.ok, true, `refused but should pass: ${text} (${v.ok ? "" : v.matched})`);
  }
});

test("rule 9: the verdict does not depend on a previous call (no regex state leaks between calls)", () => {
  for (let i = 0; i < 3; i++) {
    assert.equal(ruleNineDirective(REFUSED[0]).ok, false);
    assert.equal(ruleNineDirective(PASSED[0]).ok, true);
  }
  assert.equal(ruleNineDirective("").ok, true);
  assert.equal(ruleNineDirective(undefined).ok, true);
});

// v30: the agent states the target in its prompt and runs every directive through the lint before applying it
import { readFileSync } from "node:fs";
const agent = readFileSync(new URL("../edge-functions/ottoq-orchestrator-agent/index.ts", import.meta.url), "utf8");

test("v30: the agent imports the lint and refuses a failing directive before it is applied", () => {
  assert.match(agent, /import \{ ruleNineDirective \} from "\.\.\/_shared\/agent_rule_nine\.ts";/);
  const branch = agent.slice(agent.indexOf('a?.type === "directive"'));
  const lint = branch.indexOf("ruleNineDirective(a.text)");
  const refuse = branch.indexOf("rejected.push({ type: \"directive\"");
  const apply = branch.indexOf("applied.push({ type: \"directive\"");
  assert.ok(lint > 0 && refuse > lint && apply > refuse, "lint, then refuse, then apply");
});

test("v30: the prompt states the charge target and what the board's 80% figure is", () => {
  assert.match(agent, /CHARGE TARGET: every car charges to its owner's target, 100% unless the owner set less/);
  assert.match(agent, /any 80% figure on the board rank who is served first; they are never a charge target/);
});
