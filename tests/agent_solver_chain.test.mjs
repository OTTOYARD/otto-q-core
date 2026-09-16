import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  assignmentPairCost,
  normalizeSolverDirective,
} from "../edge-functions/_shared/agent_solver_chain.ts";

const lowSoc = { current_soc: 20, inlet_max_kw: 250 };
const midSoc = { current_soc: 50, inlet_max_kw: 250 };
const highSoc = { current_soc: 75, inlet_max_kw: 250 };
const dcfc = { stall_type: "dcfc", connector_max_kw: 150, relative_y: 20 };
const l2 = { stall_type: "l2", connector_max_kw: 19.2, relative_y: 20 };

test("unknown objectives fail closed to readiness_first", () => {
  assert.deepEqual(normalizeSolverDirective({ objective: "invented", why: "x" }), {
    objective: "readiness_first",
    why: "x",
  });
});

test("directive reason is bounded", () => {
  const directive = normalizeSolverDirective({
    objective: "throughput_first",
    why: "x".repeat(500),
  });
  assert.equal(directive.why.length, 400);
});

test("readiness objective conserves DCFC for the low SoC vehicle", () => {
  const d = normalizeSolverDirective({ objective: "readiness_first" });
  const lowDcfc = assignmentPairCost(lowSoc, dcfc, d);
  const highDcfc = assignmentPairCost(highSoc, dcfc, d);
  assert.ok(lowDcfc < highDcfc);
});

test("readiness objective ranks lower SoC ahead on the same stall type", () => {
  const d = normalizeSolverDirective({ objective: "readiness_first" });
  assert.ok(assignmentPairCost(lowSoc, l2, d) < assignmentPairCost(midSoc, l2, d));
});

test("throughput objective prefers the higher-power compatible stall", () => {
  const d = normalizeSolverDirective({ objective: "throughput_first" });
  assert.ok(assignmentPairCost(lowSoc, dcfc, d) < assignmentPairCost(lowSoc, l2, d));
});

test("energy objective conserves DCFC for a sufficiently charged vehicle", () => {
  const d = normalizeSolverDirective({ objective: "energy_balanced" });
  assert.ok(assignmentPairCost(highSoc, l2, d) < assignmentPairCost(highSoc, dcfc, d));
});

test("energy objective still ranks lower SoC ahead on the same stall type", () => {
  const d = normalizeSolverDirective({ objective: "energy_balanced" });
  assert.ok(assignmentPairCost(lowSoc, l2, d) < assignmentPairCost(highSoc, l2, d));
});

test("agent binds an explicit run before handing off to the solver", () => {
  const source = readFileSync(
    new URL("../edge-functions/ottoq-orchestrator-agent/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(source, /requestedRun/);
  assert.match(source, /eq\("sim_run_id", requestedRun\)/);
  assert.match(source, /ottoq_agent_solver_refresh/);
  assert.match(source, /ottoq_agent_chain_claim/);
});

test("migration routes the legacy cron solver through the agent chain", () => {
  const source = readFileSync(
    new URL("../db/migrations/0331_the_agent_hands_one_solver_request_to_the_kernel.sql", import.meta.url),
    "utf8",
  );
  assert.match(source, /delegated_to_agent_chain/);
  assert.match(source, /v_req := public\.ottoq_cuopt_refresh\(v_prun\)/);
  assert.match(source, /ottoq-orchestrator-agent/);
});

test("tick claim migration suppresses the legacy parallel agent trigger", () => {
  const source = readFileSync(
    new URL("../db/migrations/0332_one_agent_claim_per_run_tick.sql", import.meta.url),
    "utf8",
  );
  assert.match(source, /CREATE FUNCTION public\.ottoq_agent_chain_claim/);
  assert.match(source, /agent_chain_claim/);
  assert.match(source, /agent_solver_chain_enabled/);
});
