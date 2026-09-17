import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  assignmentPairCost,
  normalizeSolverDirective,
} from "../edge-functions/_shared/agent_solver_chain.ts";
import {
  assignmentRequest,
  rejectionFeedback,
} from "../edge-functions/_shared/cpsat_agent_chain.ts";

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
  assert.match(source, /ottoq-cpsat-propose/);
  assert.match(source, /const response = await fetch\(solverUrl/);
  assert.match(source, /status: receipt\.fallback === true \? "fallback" : "completed"/);
  assert.match(source, /apikey: serviceKey/);
  assert.match(source, /ottoq_agent_chain_claim/);
});

test("agent retries the remaining NVIDIA keys when a legacy endpoint is gone", () => {
  const source = readFileSync(
    new URL("../edge-functions/ottoq-orchestrator-agent/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(source, /for \(const candidate of keys\)/);
  assert.match(source, /if \(!r\.ok\)[\s\S]*continue;/);
  assert.match(source, /Authorization: `Bearer \$\{candidate\.value\}`/);
});

test("CP-SAT request bounds agent influence and retries", () => {
  const request = assignmentRequest({
    simRunId: "11111111-1111-1111-1111-111111111111",
    depotId: "22222222-2222-2222-2222-222222222222",
    frame: { vehicles: [], stalls: [] },
    classRows: [],
    directive: { objective: "throughput_first", why: "return wave" },
    feedback: [],
    hourOfDay: 29,
  });
  assert.equal(request.directive.objective, "throughput_first");
  assert.equal(request.max_retries, 2);
  assert.equal(request.hour_of_day, 23);
  assert.equal(request.site.dcfc_cooldown_min, 18);
});

test("rejection feedback is pair-specific and deduplicated", () => {
  const feedback = rejectionFeedback([
    { entity_id: "vehicle-1", proposal: { stall_id: "stall-1" }, disposition_reason: "stall_occupied" },
    { entity_id: "vehicle-1", proposal: { stall_id: "stall-1" }, disposition_reason: "stall_occupied" },
    { entity_id: "vehicle-2", proposal: { abstain: true } },
  ]);
  assert.deepEqual(feedback, [{
    entity_id: "vehicle-1", stall_id: "stall-1", reason: "stall_occupied", rule_codes: [],
  }]);
});

test("CP-SAT bridge is internal and falls back to cuOpt only on failure", () => {
  const source = readFileSync(
    new URL("../edge-functions/ottoq-cpsat-propose/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(source, /internal service role required/);
  assert.match(source, /AbortSignal\.timeout\(5_000\)/);
  assert.match(source, /ottoq_proposer_submit_batch/);
  assert.match(source, /queueCuOptFallback/);
  assert.match(source, /p_source: "forward_lex"/);
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
