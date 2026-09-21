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
  assert.match(source, /ottoq_agent_chain_claim/);
  // This used to assert /EdgeRuntime\.waitUntil/ and had been RED since 591305d pulled the
  // live function into the repo -- the deployed lineage never fired the handoff and forgot
  // it, it awaits the reply so the audit row can record completion/fallback/failure instead
  // of claiming an unobserved request queued. Nothing noticed, because verify.yml runs
  // pytest and three scripts and has never run `node --test` (db/checks/0306). The
  // assertion now names the behaviour the code actually has.
  assert.doesNotMatch(source, /EdgeRuntime\.waitUntil/);
  assert.match(source, /const response = await fetch\(solverUrl/);
});

test("the solver handoff never names an engine that did not run (0301/v18)", () => {
  const source = readFileSync(
    new URL("../edge-functions/ottoq-orchestrator-agent/index.ts", import.meta.url),
    "utf8",
  );
  // 0301: `engine: receipt.engine ?? "cp_sat_forward_lex"` turned ottoq-cpsat-propose's
  // decline -- {ok:true, skipped:"run is not active", engine:null} -- into a row reading
  // status "completed", engine cp_sat_forward_lex, and it was read for an hour as proof the
  // chain had reached CP-SAT. `??` falls through on null as well as undefined, which is why
  // the bridge setting engine:null was not enough on its own.
  assert.match(source, /engine: receipt\.engine \?\? null/);
  // Comments are stripped first: the v18 header QUOTES the defective line so a reader knows
  // what changed, and a naive negative match would fail on the explanation rather than on
  // the code. Only executable lines are searched for the resurrected default.
  const code = source.split("\n").filter((line) => !line.trim().startsWith("//")).join("\n");
  assert.doesNotMatch(code, /receipt\.engine \?\? "cp_sat_forward_lex"/);
  assert.match(source, /status: "skipped"/);
  assert.match(source, /solver_ran: receipt\.solver_ran === true/);
  // The verb and outcome_status both hang off this list; a skip must not be in it.
  assert.match(source, /solverAccepted = \["completed", "fallback"\]/);
});

test("one-vehicle/one-stall is documented as TEMPORAL, not instantaneous (G109)", () => {
  const source = readFileSync(
    new URL("../edge-functions/_shared/agent_solver_chain.ts", import.meta.url),
    "utf8",
  );
  // G109 was mis-filed by reading two proposals that shared a stall_id as a violated
  // constraint, without opening their windows (0 -> 5 and 23 -> 41: disjoint). The comment
  // that was briefly deleted for being false was true. Keep the disambiguation in the file.
  assert.match(source, /one-vehicle\/one-stall/);
  assert.match(source, /AddNoOverlap/);
  assert.match(source, /READ THE WINDOWS/);
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

test("agent delegation reserves one bounded beat before greedy dispatch", () => {
  const migration = readFileSync(
    new URL("../db/migrations/0331_the_agent_hands_one_solver_request_to_the_kernel.sql", import.meta.url),
    "utf8",
  );
  const fix = readFileSync(
    new URL("../db/migrations/0337_the_agent_chain_gets_first_refusal_before_greedy_dispatch.sql", import.meta.url),
    "utf8",
  );
  assert.match(migration, /ottoq_cuopt_first_refusal_arm\(v_run,v_tick\)/);
  assert.match(fix, /ottoq_cuopt_first_refusal_arm\(v_run,v_tick\)/);
  assert.match(
    fix,
    /strpos\(d,'ottoq_cuopt_first_refusal_arm\(v_run,v_tick\)'\) > strpos\(d,'ottoq-orchestrator-agent'\)/,
  );
});

test("one in-flight agent owns a bounded multi-beat solver window", () => {
  const source = readFileSync(
    new URL("../db/migrations/0338_one_inflight_agent_gets_a_bounded_solver_window.sql", import.meta.url),
    "utf8",
  );
  assert.match(source, /agent_run_in_flight/);
  assert.match(source, /agent_chain_inflight_timeout_s/);
  assert.match(source, /cuopt_first_refusal_max_defers'', 6::numeric/);
  assert.match(source, /resolved_action_context='orchestrator_agent'/);
});
