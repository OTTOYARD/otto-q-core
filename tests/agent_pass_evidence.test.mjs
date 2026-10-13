import assert from "node:assert/strict";
import test from "node:test";

import {
  boardText,
  classifyPass,
  leversOf,
  readWake,
  sha256Hex,
  standingObjective,
} from "../edge-functions/_shared/agent_pass_evidence.ts";

// edge function v29 (0703, 0705): one agent pass as an honest evidence row, and the wake gate's verdict as the edge
// function reads it. The sha256 vectors are hashlib's, and tests/test_agent_scouts_wake_sql.py proves the database's
// public.ottoq_sha256_utf8 gives the same digest for the same text, so a board hashed here is the board hashed there.

test("sha256Hex is the standard digest of the UTF-8 bytes", async () => {
  assert.equal(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  assert.equal(await sha256Hex('{"tick": 7,\n "x": "é"}'),
    "638c7474224bf7ba5fd7995e88acba008645281b421f4d34d6f1617605149d0b");
});

test("boardText is the text the model reads (indent 1), so the hash and the prompt cannot disagree", () => {
  assert.equal(boardText({ tick: 7, a: [1] }), '{\n "tick": 7,\n "a": [\n  1\n ]\n}');
});

const none = { applied: [], queued: [], rejected: [], chargeOrderReceipt: null, solverHandoff: null, objective: null };

test("an order the kernel took is a changed state; an order it refused as its own is an echo", () => {
  const taken = leversOf({ ...none, chargeOrderReceipt: { ok: true, status: "partial" } });
  assert.equal(taken.order_taken, true);
  assert.equal(classifyPass({ consulted: true, answered: true, levers: taken }), "changed_state");

  const echo = leversOf({ ...none, chargeOrderReceipt: { ok: true, status: "refused", projection: { reason: "same_as_kernel" } } });
  assert.equal(echo.order_taken, false);
  assert.equal(classifyPass({ consulted: true, answered: true, levers: echo }), "echo");

  // a refusal for losing the futures is not an echo: the agent proposed something different and it lost
  const lost = leversOf({ ...none, chargeOrderReceipt: { ok: true, status: "refused", projection: { reason: "not_enough_futures_won" } } });
  assert.equal(classifyPass({ consulted: true, answered: true, levers: lost }), "no_effect");
});

test("directives and approval requests alone are advisory, never a changed state", () => {
  const l = leversOf({ ...none, applied: [{ type: "directive", text: "x" }], queued: [{ kind: "approval" }] });
  assert.equal(l.directives_issued, 1);
  assert.equal(l.ops_queued, 1);
  assert.equal(classifyPass({ consulted: true, answered: true, levers: l }), "advisory");
});

test("a dial or an ops action applied is a changed state, whatever else happened", () => {
  const l = leversOf({ ...none, applied: [{ type: "directive" }, { type: "set_policy", key: "k" }],
    chargeOrderReceipt: { ok: true, status: "refused", projection: { reason: "same_as_kernel" } } });
  assert.equal(classifyPass({ consulted: true, answered: true, levers: l }), "changed_state");
});

test("a solver handoff that ran is not a changed state by itself, and its real proposals are counted", () => {
  const l = leversOf({ ...none, solverHandoff: { status: "completed", assign: { rows: 13, real_rows: 0 } } });
  assert.equal(l.solver_status, "completed");
  assert.equal(l.solver_proposals_out, 0);
  assert.equal(classifyPass({ consulted: true, answered: true, levers: l }), "no_effect");
});

test("precedence: failed, then not consulted, then no answer", () => {
  const l = leversOf({ ...none, chargeOrderReceipt: { ok: true, status: "accepted" } });
  assert.equal(classifyPass({ consulted: true, answered: true, failed: true, levers: l }), "failed");
  assert.equal(classifyPass({ consulted: false, answered: false, levers: l }), "solver_only");
  assert.equal(classifyPass({ consulted: true, answered: false, levers: l }), "fallback");
});

test("a missing, failing or unreadable wake gate always wakes", () => {
  assert.equal(readWake(null, { message: "function does not exist" }).wake, true);
  assert.deepEqual(readWake(null, { message: "x" }).reasons, ["wake_rpc_error"]);
  assert.equal(readWake({ nonsense: 1 }, null).wake, true);
  assert.equal(readWake(null, null).wake, true);
  const quiet = readWake({ wake: false, would_wake: false, reasons: [], standing_objective: "throughput_first" }, null);
  assert.equal(quiet.wake, false);
  assert.equal(standingObjective(quiet), "throughput_first");
});

test("a solver-only pass never runs on an objective the solver does not know", () => {
  assert.equal(standingObjective({ wake: false, standing_objective: "maximize_everything" }), "readiness_first");
  assert.equal(standingObjective({ wake: false }), "readiness_first");
});
