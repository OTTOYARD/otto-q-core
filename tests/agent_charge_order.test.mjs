import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  CHARGE_ORDER_MAX_CARS,
  CHARGE_ORDER_PROMPT,
  chargeOrderAccepted,
  chargeQueueOf,
  normalizeChargeOrder,
  normalizeKind,
  withChargeOrder,
} from "../edge-functions/_shared/agent_charge_order.ts";

// edge function v23 / db/migrations/0614: the agent's charge order, from the model's answer to what the door receives.

const A = "0a000000-0000-4000-8000-00000000000a";
const B = "0b000000-0000-4000-8000-00000000000b";
const C = "0c000000-0000-4000-8000-00000000000c";
const board = {
  tick: 120,
  charge_queue: {
    cars: [
      { vehicle_id: A, name: "Tesla-AV-041", soc: 30, kernel_pos: 1 },
      { vehicle_id: B, name: "Fleet-EV-002", soc: 62, kernel_pos: 2 },
      { vehicle_id: C, name: "Tesla-AV-042", soc: 88, kernel_pos: 3 },
    ],
  },
};

test("no charge line on the board: no order, and the prompt is the base one", () => {
  assert.equal(chargeQueueOf({ tick: 1 }), null);
  assert.equal(normalizeChargeOrder({ cars: [{ car: "Tesla-AV-041" }] }, { tick: 1 }), null);
  assert.equal(withChargeOrder("BASE", { tick: 1 }), "BASE");
  assert.equal(withChargeOrder("BASE", board), `BASE\n${CHARGE_ORDER_PROMPT}`);
});

test("names become vehicle ids from the same board, in the model's order", () => {
  const o = normalizeChargeOrder({
    cars: [{ car: "Tesla-AV-042", kind: "L2", why: "near target" },
           { name: "tesla-av-041", kind: "DCFC", why: "owes 52 kWh" },
           { vehicle_id: B.toUpperCase(), kind: "whatever" }],
    why: "fast charger to the car that owes most",
  }, board);
  assert.deepEqual(o.cars.map((c) => c.vehicle_id), [C, A, B]);
  assert.deepEqual(o.cars.map((c) => c.kind), ["l2", "dcfc", "either"]);
  assert.equal(o.cars[1].why, "owes 52 kWh");
  assert.equal(o.why, "fast charger to the car that owes most");
  assert.deepEqual(o.unmatched, []);
});

test("a bare array is an order too, and duplicates after the first are left out", () => {
  const o = normalizeChargeOrder(["Fleet-EV-002", { car: "Fleet-EV-002", kind: "dcfc" }, "Tesla-AV-041"], board);
  assert.deepEqual(o.cars.map((c) => c.vehicle_id), [B, A]);
  assert.equal(o.cars[0].kind, "either");
});

test("a name the board does not hold is sent on as written, so the door records the drop", () => {
  const o = normalizeChargeOrder({ cars: [{ car: "Ghost-999", kind: "dcfc" }, { car: "Tesla-AV-041" }] }, board);
  assert.deepEqual(o.cars.map((c) => c.vehicle_id), ["Ghost-999", A]);
  assert.deepEqual(o.unmatched, ["Ghost-999"]);
  // a uuid not among the 24 shown passes through: the door checks the whole line
  const far = "0f000000-0000-4000-8000-00000000000f";
  const o2 = normalizeChargeOrder({ cars: [{ vehicle_id: far }] }, board);
  assert.deepEqual(o2.cars.map((c) => c.vehicle_id), [far]);
  assert.deepEqual(o2.unmatched, []);
});

test("at most twelve cars go to the door", () => {
  const many = Array.from({ length: 20 }, (_, i) => ({ vehicle_id: `0${String(i).padStart(7, "0")}-0000-4000-8000-000000000000` }));
  const o = normalizeChargeOrder({ cars: many }, board);
  assert.equal(o.cars.length, CHARGE_ORDER_MAX_CARS);
});

test("an answer with no order, or an unreadable one, is no order", () => {
  assert.equal(normalizeChargeOrder(undefined, board), null);
  assert.equal(normalizeChargeOrder("first A then B", board), null);
  assert.equal(normalizeChargeOrder({ why: "kernel order is right" }, board), null);
  assert.deepEqual(normalizeChargeOrder({ cars: [] }, board).cars, []);
});

test("kinds: the spellings a model uses", () => {
  for (const k of ["dcfc", "DCFC", "dc", "DC fast", "fast"]) assert.equal(normalizeKind(k), "dcfc", k);
  for (const k of ["l2", "L2", "Level 2", "level_2", "AC"]) assert.equal(normalizeKind(k), "l2", k);
  for (const k of ["either", "", null, undefined, "any", 3]) assert.equal(normalizeKind(k), "either", String(k));
});

test("an accepted or partial receipt counts as enacted; a skip, a rejection or an error does not", () => {
  assert.equal(chargeOrderAccepted({ ok: true, status: "accepted" }), true);
  assert.equal(chargeOrderAccepted({ ok: true, status: "partial" }), true);
  assert.equal(chargeOrderAccepted({ ok: true, status: "rejected" }), false);
  assert.equal(chargeOrderAccepted({ ok: false, skipped: "agent_charge_order is 0 for this run" }), false);
  assert.equal(chargeOrderAccepted(null), false);
});

test("the prompt states what the kernel enforces, and rule 9 in the agent's own words", () => {
  assert.match(CHARGE_ORDER_PROMPT, /immediate-dispatch cars go first and any car waiting pin_wait_min or longer goes next, whatever you send/);
  assert.match(CHARGE_ORDER_PROMPT, /No charger is left idle for your order: a car still takes the other kind when no other car waits for it/);
  assert.match(CHARGE_ORDER_PROMPT, /Every car charges to its full target on whichever charger it takes/);
  // 0617: the order the kernel keeps under a live order, as the prompt states it
  assert.match(CHARGE_ORDER_PROMPT, /then the cars you did not name, in the kernel's order; and last the cars you named for a kind that is not free, which wait for that kind/);
  assert.match(CHARGE_ORDER_PROMPT, /never how much charge a car gets, and never whether it charges/);
  assert.match(CHARGE_ORDER_PROMPT, /Never hold a car back, never end a charge early, never lower a target/);
  assert.match(CHARGE_ORDER_PROMPT, /"charge_order":\{"cars":\[\{"car":/);
});

test("v25 / 0620: the prompt says the kernel rolls the line forward over sampled futures, and when to order", () => {
  assert.match(CHARGE_ORDER_PROMPT, /THE KERNEL CHECKS IT FIRST: it rolls the whole line forward from now twice — your order for its ttl and then its own, against its own order throughout/);
  assert.match(CHARGE_ORDER_PROMPT, /with the cars coming home joining the line when they arrive and every charge timed by the learned clock/);
  assert.match(CHARGE_ORDER_PROMPT, /It takes your order only when it beats its own in the expected future AND in at least win_frac of all the futures \(10 of 12\)/);
  assert.match(CHARGE_ORDER_PROMPT, /more cars ready by their due time; then fewer minutes late; then fewer minutes in the depot summed over every car/);
  assert.match(CHARGE_ORDER_PROMPT, /charge_queue\.contention: waiting against free_now and freeing_15_min, arriving_60_min, and pressure/);
  assert.match(CHARGE_ORDER_PROMPT, /charge_queue\.arriving: the cars coming home/);
  assert.match(CHARGE_ORDER_PROMPT, /WHEN TO ORDER: when contention\.pressure is tight or congested\. When it is none, every car waiting plugs in now whatever you send: leave out charge_order/);
  assert.match(CHARGE_ORDER_PROMPT, /same_as_kernel means your order changed nothing: do not resend it/);
  assert.match(CHARGE_ORDER_PROMPT, /worse_in_expected_future, no_better_in_expected_future or not_enough_futures_won mean it lost/);
  assert.match(CHARGE_ORDER_PROMPT, /will miss its due time unless it takes the next fast charger to free: name it dcfc, earliest due first/);
  assert.match(CHARGE_ORDER_PROMPT, /Mind the cars coming home \(arriving\): a low battery put on an L2 holds it for hours/);
  assert.match(CHARGE_ORDER_PROMPT, /never send the same order again/);
  // 0618's wording is gone: the check is no longer one projection of the line waiting now
  assert.doesNotMatch(CHARGE_ORDER_PROMPT, /it projects the whole line from now in its own order and in yours/);
  assert.doesNotMatch(CHARGE_ORDER_PROMPT, /at most 10% later on average/);
  // the old rules that sent overdue top-offs and low batteries to the scarcest charger stay gone
  assert.doesNotMatch(CHARGE_ORDER_PROMPT, /a car whose due_in_min is shorter than its min_on_l2 needs a fast charger/);
  assert.doesNotMatch(CHARGE_ORDER_PROMPT, /The contract first: cars with over_limit_min above 0/);
});

test("0618/0620: a refused order is not an enacted action", () => {
  assert.equal(chargeOrderAccepted({ ok: true, status: "refused", projection: { take: false, reason: "line_ready_later" } }), false);
  assert.equal(chargeOrderAccepted({ ok: true, status: "refused", projection: { take: false, reason: "same_as_kernel" } }), false);
});

const orchestrator = readFileSync(new URL("../edge-functions/ottoq-orchestrator-agent/index.ts", import.meta.url), "utf8");
const code = orchestrator.split("\n").filter((line) => !line.trim().startsWith("//")).join("\n");

test("v23: the order is recorded before the solver handoff, under the pass's chain id", () => {
  const record = code.indexOf('sb.rpc("ottoq_agent_charge_order_record"');
  const handoff = code.indexOf("const response = await fetch(solverUrl");
  const chain = code.indexOf("const chainId = crypto.randomUUID();");
  assert.ok(record > 0 && handoff > 0 && chain > 0);
  assert.ok(chain < record && record < handoff, "chain id, then the order, then the handoff");
  assert.match(code, /p_chain_id: chainId/);
  assert.match(code, /charge_order: chargeOrderReceipt/);
  assert.match(code, /charge_order: chargeOrder \}/);
});

test("v23-v25: the model call goes through the retry module, with the fallback model, and the row says v25", () => {
  assert.match(code, /await callModelWithRetry\(/);
  assert.match(code, /models: \[MODEL, FALLBACK_MODEL\]/);
  assert.match(code, /const FALLBACK_MODEL = "nvidia\/nemotron-3-super-120b-a12b";/);
  assert.match(code, /model_attempts: call\.attempts/);
  assert.match(code, /agent_version: "v25"/);
  assert.doesNotMatch(code, /agent_version: "v2[234]"/);
  // the single-try key loop is gone
  assert.doesNotMatch(code, /for \(const candidate of keys\)/);
  // an accepted order is an enacted action
  assert.match(code, /applied\.length > 0 \|\| solverAccepted \|\| orderAccepted \? "enacted" : "noop_no_candidate"/);
  // the ledger capture reads the first parenthesised error of a fallback rationale; keep it first
  assert.match(code, /rationale: `fallback: model unavailable or unparseable \(\$\{raw \? raw\.slice\(0,40\) : "no key"\}\)/);
});
