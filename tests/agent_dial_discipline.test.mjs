import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_REVERSAL_DWELL_MIN,
  INERT_KEYS,
  INERT_OPS,
  KNOBS,
  OPS_ACTION_DIAL,
  WORK_SIDE_KEYS,
  admitDialChange,
  clampDial,
  currentDialValue,
  moveDirection,
  opsActionDirection,
  reversalDwellMin,
  reversalHold,
} from "../edge-functions/_shared/agent_dial_discipline.ts";

// db/checks/0352: the work side's demand is visible to the agent and never an actuator.
test("deploy_peak_fraction is work-side demand, not a knob", () => {
  assert.equal(KNOBS.deploy_peak_fraction, undefined);
  assert.ok(WORK_SIDE_KEYS.has("deploy_peak_fraction"));
  for (const key of WORK_SIDE_KEYS) assert.equal(KNOBS[key], undefined, `${key} is in both sets`);
});

test("every ops action moves a real knob", () => {
  for (const [action, spec] of Object.entries(OPS_ACTION_DIAL)) {
    assert.ok(KNOBS[spec.key], `${action} moves ${spec.key}, which is not a knob`);
  }
});

test("fractional dials are never rounded (the v15 bug stays dead)", () => {
  const c = clampDial("energy_demand_factor_peak", 0.65, 0.6);
  assert.equal(c.value, 0.65);
  assert.equal(c.limiter, "none");
});

test("the drift limiter bounds a move to 30% of the value in force", () => {
  const c = clampDial("energy_demand_factor_peak", 0.9, 0.5);
  assert.equal(c.value, 0.65);
  assert.equal(c.limiter, "drift");
});

test("the range clamp is reported, and integer dials round", () => {
  assert.deepEqual(clampDial("energy_demand_factor_expensive", 0.1, null),
    { value: 0.2, limiter: "range", requested: 0.1 });
  // an integer-valued dial rounds (v20 has no integer dial beyond the binary switch, so a local table)
  assert.equal(clampDial("h", 44.6, 40, { h: { lo: 10, hi: 90, int: true } }).value, 45);
});

test("a binary switch is not drift-pinned at 0", () => {
  assert.equal(clampDial("energy_reserve_shave", 1, 0).value, 1);
});

test("clampDial refuses a key that is not an actuator", () => {
  assert.throws(() => clampDial("deploy_peak_fraction", 0.5, 0.45), /not an agent actuator/);
});

// v18 read board.policy, which carried three of the six dials: the drift limiter never ran on
// deploy_surge_catchup or forecast_horizon_min because their "current" was undefined.
test("the current value comes from grounding, then policy, else null", () => {
  const legacy = { policy: { energy_demand_factor_peak: 0.5 } };
  assert.equal(currentDialValue(legacy, "deploy_surge_catchup"), null);
  assert.equal(currentDialValue(legacy, "energy_demand_factor_peak"), 0.5);
  const grounded = {
    policy: { energy_demand_factor_peak: 0.5 },
    grounding: { actuators: { energy_demand_factor_peak: { value: 0.85 }, deploy_surge_catchup: { value: 0.35 } } },
  };
  assert.equal(currentDialValue(grounded, "energy_demand_factor_peak"), 0.85);
  assert.equal(currentDialValue(grounded, "deploy_surge_catchup"), 0.35);
  assert.equal(currentDialValue(null, "deploy_surge_catchup"), null);
});

test("with a grounded current value the drift limiter runs", () => {
  const board = { grounding: { actuators: { energy_demand_factor_peak: { value: 0.4 } } } };
  const c = clampDial("energy_demand_factor_peak", 0.9, currentDialValue(board, "energy_demand_factor_peak"));
  assert.equal(c.value, 0.4 * 1.3);
  assert.equal(c.limiter, "drift");
});

// v20 (G175): two dials the agent used to be offered have no reader anywhere in the engine.
test("the dials nothing reads are not knobs, and say why", () => {
  assert.deepEqual(Object.keys(KNOBS).sort(),
    ["energy_demand_factor_expensive", "energy_demand_factor_peak", "energy_reserve_shave"]);
  for (const k of ["deploy_surge_catchup", "forecast_horizon_min"]) {
    assert.equal(KNOBS[k], undefined);
    assert.match(INERT_KEYS[k], /^inert_dial: no engine function reads /);
    assert.throws(() => clampDial(k, 0.5, 0.35), /not an agent actuator/);
  }
  for (const k of Object.keys(INERT_KEYS)) assert.equal(KNOBS[k], undefined);
});

test("the ops actions that only moved an inert dial are not whitelisted", () => {
  assert.deepEqual(Object.keys(OPS_ACTION_DIAL), ["enable_energy_reserve"]);
  for (const a of ["raise_deploy_surge", "extend_forecast_horizon"]) {
    assert.equal(OPS_ACTION_DIAL[a], undefined);
    assert.match(INERT_OPS[a], /^inert_ops_action: /);
  }
});

test("the dwell is read from the board, defaults, and ignores nonsense", () => {
  assert.equal(reversalDwellMin(undefined), DEFAULT_REVERSAL_DWELL_MIN);
  assert.equal(reversalDwellMin({ grounding: { stability: { reversal_dwell_min: 45 } } }), 45);
  assert.equal(reversalDwellMin({ grounding: { stability: { reversal_dwell_min: 0 } } }), 0);
  assert.equal(reversalDwellMin({ grounding: { stability: { reversal_dwell_min: -5 } } }), DEFAULT_REVERSAL_DWELL_MIN);
  assert.equal(reversalDwellMin({ grounding: { stability: { reversal_dwell_min: "x" } } }), DEFAULT_REVERSAL_DWELL_MIN);
});

// 0352 §2: 96 of 106 writes asked for 0.35-0.45 and were clamped to the 0.50 floor, over and over.
test("a request clamped onto the value in force is no_change, and says why", () => {
  const actuator = { value: 0.2, agent_min: 0.2, agent_max: 0.8 };
  const c = clampDial("energy_demand_factor_expensive", 0.1, 0.2);
  const hold = admitDialChange("energy_demand_factor_expensive", c.value, c, actuator, 0.2, 30);
  assert.equal(hold?.reason, "no_change");
  assert.match(hold.detail, /\[0\.2, 0\.8\]/);
});

test("a plain resend is no_change", () => {
  const c = clampDial("energy_demand_factor_peak", 0.85, 0.85);
  assert.equal(admitDialChange("energy_demand_factor_peak", c.value, c, { value: 0.85 }, 0.85, 30)?.reason, "no_change");
});

// 0352 §3: 71% and 68% of energy-dial changes reversed the previous change.
test("reversing the agent's own recent change is held; continuing it is not", () => {
  const actuator = { value: 0.85, last_change: { direction: "down", min_ago: 4, from: 0.9, to: 0.85 } };
  const up = clampDial("energy_demand_factor_peak", 0.9, 0.85);
  const down = clampDial("energy_demand_factor_peak", 0.8, 0.85);
  assert.equal(admitDialChange("energy_demand_factor_peak", up.value, up, actuator, 0.85, 30)?.reason,
    "reversal_within_dwell");
  assert.equal(admitDialChange("energy_demand_factor_peak", down.value, down, actuator, 0.85, 30), null);
});

test("a reversal is admitted once the dwell has passed, or when the dwell is 0", () => {
  const old = { value: 0.85, last_change: { direction: "down", min_ago: 31 } };
  const fresh = { value: 0.85, last_change: { direction: "down", min_ago: 1 } };
  const up = clampDial("energy_demand_factor_peak", 0.9, 0.85);
  assert.equal(admitDialChange("energy_demand_factor_peak", up.value, up, old, 0.85, 30), null);
  assert.equal(admitDialChange("energy_demand_factor_peak", up.value, up, fresh, 0.85, 0), null);
});

test("no last change, or an unreadable one, never holds", () => {
  const up = clampDial("energy_demand_factor_peak", 0.9, 0.85);
  assert.equal(admitDialChange("energy_demand_factor_peak", up.value, up, { value: 0.85, last_change: null }, 0.85, 30), null);
  assert.equal(admitDialChange("energy_demand_factor_peak", up.value, up,
    { value: 0.85, last_change: { direction: "sideways", min_ago: 1 } }, 0.85, 30), null);
  assert.equal(reversalHold("energy_demand_factor_peak", "unknown", { last_change: { direction: "down", min_ago: 1 } }, 30), null);
});

test("ops actions carry their direction; the reserve switch only turns on", () => {
  assert.equal(opsActionDirection("enable_energy_reserve", { value: 0 }, 1), "up");
  assert.equal(opsActionDirection("enable_energy_reserve", {}, 0), "up");
  // v20: no longer whitelisted, so no direction to hold on
  assert.equal(opsActionDirection("raise_deploy_surge", {}, 0.35), "unknown");
  assert.equal(opsActionDirection("extend_forecast_horizon", { value: 20 }, 45), "unknown");
  assert.equal(opsActionDirection("drain_the_bess", {}, 1), "unknown");
  assert.equal(moveDirection(0.5, null), "unknown");
});

test("an ops action that would undo a recent set_policy change is held", () => {
  const actuator = { value: 0, last_change: { direction: "down", min_ago: 10, from: 1, to: 0 } };
  const hold = reversalHold("energy_reserve_shave", opsActionDirection("enable_energy_reserve", {}, 0), actuator, 30);
  assert.equal(hold?.reason, "reversal_within_dwell");
});

// A 30-minute dwell against a request stream that flips every ~4 sim-minutes (the 0352 shape): the
// first change is admitted, the flips inside the window are held, the dial is left to work.
test("an oscillating request stream is damped to one change per dwell window", () => {
  let value = 0.8;
  let lastChange = null;
  let admitted = 0, held = 0;
  const requests = [0.7, 0.8, 0.7, 0.8, 0.7, 0.8, 0.7, 0.8, 0.7, 0.8];
  requests.forEach((req, i) => {
    const t = i * 4;
    const actuator = { value, last_change: lastChange && { ...lastChange, min_ago: t - lastChange.t } };
    const c = clampDial("energy_demand_factor_peak", req, value);
    const hold = admitDialChange("energy_demand_factor_peak", c.value, c, actuator, value, 30);
    if (hold) { held++; return; }
    admitted++;
    lastChange = { direction: c.value > value ? "up" : "down", from: value, to: c.value, t };
    value = c.value;
  });
  assert.equal(admitted + held, requests.length);
  assert.ok(admitted <= 3, `admitted ${admitted} changes in 40 sim-minutes`);
  assert.ok(held >= 7);
});
