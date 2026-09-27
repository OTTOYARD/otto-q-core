/**
 * The orchestrator agent's dial discipline (edge function v19, db/migrations/0432, db/checks/0352).
 *
 * Pure functions only, so `node --test tests/*.test.mjs` can import this file directly. The database is
 * still the disposer: ottoq_policy_set clamps to the catalog envelope and now refuses an agent on any dial
 * whose catalog row says agent_writable = false. This file decides what the agent is allowed to ASK for,
 * and holds back the two moves 0352 measured as noise:
 *
 *   * a write to the value already in force. On run 0682752c 92 of 106 writes to one dial were resends of
 *     the clamped floor, each counted as a move and each reported "applied";
 *   * a reversal of the agent's own change inside a dwell window. 71% and 68% of changes on the two
 *     energy dials reversed the previous change, a mean step of 15% of range every 8-13 ticks -- one
 *     controller with no memory of its own last move.
 */

export type Knob = { lo: number; hi: number; int?: boolean };

/**
 * The agent's actuators. `int: true` marks a dial whose value is genuinely whole-numbered; everything
 * else is continuous and is never rounded (do not infer this from hi - lo -- that was the v15 bug).
 *
 * deploy_peak_fraction is deliberately ABSENT. It is the work side's demand -- how much of the fleet the
 * dispatcher deploys each hour -- and CLAUDE.md rule 6 allows no work-side features. See WORK_SIDE_KEYS.
 */
export const KNOBS: Readonly<Record<string, Knob>> = {
  energy_demand_factor_peak:      { lo: 0.3, hi: 0.9 },
  energy_demand_factor_expensive: { lo: 0.2, hi: 0.8 },
  energy_reserve_shave:           { lo: 0,   hi: 1,  int: true },   // binary switch
};

/**
 * v20 (G175, db/migrations/0438): dials the agent used to be offered that NOTHING READS. A comment-stripped
 * search of every function in the database, and of every code repo, finds deploy_surge_catchup and
 * forecast_horizon_min only in the setter that writes them (ottoq_apply_ops_action) and in this agent. On run
 * 7a42982a the agent drove the first from 0.455 to 1.0 and the second from 39 to 75, and neither changed
 * anything. They are REJECTED here with a reason the agent can read, never queued for a human: a human
 * approving a placebo is worse than the agent tuning one. 0438 also makes them agent_writable = false, so
 * the setter refuses them too.
 */
export const INERT_KEYS: Readonly<Record<string, string>> = {
  deploy_surge_catchup: "inert_dial: no engine function reads deploy_surge_catchup (G175, 0438)",
  forecast_horizon_min: "inert_dial: no engine function reads forecast_horizon_min (G175, 0438)",
};

/**
 * Keys the agent can SEE but may never write -- not even through the human approval queue, because a
 * proposal to change the demand the run is measured against is not a proposal a human should be asked
 * to rubber-stamp every few ticks. A write to one is rejected with a reason the agent can read.
 */
export const WORK_SIDE_KEYS: ReadonlySet<string> = new Set(["deploy_peak_fraction"]);

export const MAX_DRIFT = 0.30;
export const DEFAULT_REVERSAL_DWELL_MIN = 30;

export type Direction = "up" | "down" | "unknown";

export type ClampResult = { value: number; limiter: string; requested: number };

/**
 * Clamp a requested dial value: drift-limit (continuous dials only) -> hard range clamp -> round ONLY
 * if the dial is integer-valued. Returns the value plus how it was reached, so the audit row shows
 * whether the model's number survived. Unchanged from v16-v18 apart from living here.
 */
export function clampDial(
  key: string,
  requested: number,
  current: number | null | undefined,
  knobs: Readonly<Record<string, Knob>> = KNOBS,
): ClampResult {
  const cd = knobs[key];
  if (!cd) throw new Error(`clampDial: ${key} is not an agent actuator`);
  const isBinary = !!cd.int && (cd.hi - cd.lo) <= 1;
  let v = requested;
  let limiter = "none";

  // ±30% drift limiter on every continuous dial. Skipped for binary switches, where drift is
  // meaningless and a current of 0 would otherwise pin the dial at 0 forever.
  const cur = Number(current);
  if (!isBinary && current !== null && current !== undefined && Number.isFinite(cur) && cur > 0) {
    const dLo = cur * (1 - MAX_DRIFT), dHi = cur * (1 + MAX_DRIFT);
    const before = v;
    v = Math.min(dHi, Math.max(dLo, v));
    if (v !== before) limiter = "drift";
  }

  const beforeClamp = v;
  v = Math.min(cd.hi, Math.max(cd.lo, v));
  if (v !== beforeClamp) limiter = limiter === "drift" ? "drift+range" : "range";

  if (cd.int) v = Math.round(v);
  return { value: v, limiter, requested };
}

/** The shape `ottoq_agent_board_grounding` publishes per actuator (only the fields read here). */
export type ActuatorView = {
  value?: number | null;
  agent_min?: number | null;
  agent_max?: number | null;
  last_change?: {
    direction?: string | null;
    min_ago?: number | null;
    from?: number | null;
    to?: number | null;
    tick?: number | null;
  } | null;
};

type BoardLike = {
  policy?: Record<string, unknown> | null;
  grounding?: {
    actuators?: Record<string, ActuatorView | undefined> | null;
    stability?: { reversal_dwell_min?: unknown } | null;
  } | null;
} | null | undefined;

function finiteOrNull(x: unknown): number | null {
  if (x === null || x === undefined || x === "") return null;
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
}

/**
 * The value in force for a dial. The grounding block reads it with the engine's own resolution; the
 * legacy `policy` block carried only three dials, so deploy_surge_catchup and forecast_horizon_min had
 * NO current value in v18 and the drift limiter silently never ran on them.
 */
export function currentDialValue(board: BoardLike, key: string): number | null {
  const g = finiteOrNull(board?.grounding?.actuators?.[key]?.value);
  if (g !== null) return g;
  return finiteOrNull(board?.policy?.[key]);
}

/** The dwell the board publishes, else the default. A negative or non-numeric value falls back too. */
export function reversalDwellMin(board: BoardLike): number {
  const d = finiteOrNull(board?.grounding?.stability?.reversal_dwell_min);
  return d !== null && d >= 0 ? d : DEFAULT_REVERSAL_DWELL_MIN;
}

export function moveDirection(target: number, current: number | null | undefined): Direction {
  const cur = finiteOrNull(current);
  if (cur === null || !Number.isFinite(target)) return "unknown";
  if (target > cur) return "up";
  if (target < cur) return "down";
  return "unknown";
}

export type Hold = { reason: "no_change" | "reversal_within_dwell"; detail: string };

/**
 * A reversal of the agent's own last CHANGE to this dial, younger than the dwell, is held. Only the
 * last change counts -- resends are not changes -- which is why the grounding block publishes
 * `last_change` separately from `last_write`.
 */
export function reversalHold(
  key: string,
  direction: Direction,
  actuator: ActuatorView | null | undefined,
  dwellMin: number,
): Hold | null {
  if (!(dwellMin > 0) || direction === "unknown") return null;
  const lc = actuator?.last_change;
  if (!lc || (lc.direction !== "up" && lc.direction !== "down")) return null;
  const ago = finiteOrNull(lc.min_ago);
  if (ago === null || ago >= dwellMin) return null;
  if (lc.direction === direction) return null;
  return {
    reason: "reversal_within_dwell",
    detail: `${key} was moved ${lc.direction} ${ago} sim-min ago (${lc.from} -> ${lc.to}); ` +
      `a ${direction} move is held until ${dwellMin} sim-min have passed`,
  };
}

/**
 * Admit or hold a set_policy move AFTER clamping. `target` is the clamped value that would be sent.
 * Returns null to admit; otherwise the hold and its reason.
 */
export function admitDialChange(
  key: string,
  target: number,
  clamp: ClampResult,
  actuator: ActuatorView | null | undefined,
  current: number | null | undefined,
  dwellMin: number,
): Hold | null {
  const cur = finiteOrNull(current ?? actuator?.value);
  if (cur !== null && Math.abs(target - cur) <= 1e-9 * Math.max(1, Math.abs(cur))) {
    const why = clamp.limiter === "none"
      ? `${key} is already ${cur}`
      : `${key} is already ${cur}; the request ${clamp.requested} was limited to it (${clamp.limiter}) -- ` +
        `the envelope is [${actuator?.agent_min ?? "?"}, ${actuator?.agent_max ?? "?"}]`;
    return { reason: "no_change", detail: why };
  }
  return reversalHold(key, moveDirection(target, cur), actuator, dwellMin);
}

/** Which dial each whitelisted ops action moves, and in which direction by default. */
export const OPS_ACTION_DIAL: Readonly<Record<string, { key: string; direction: Direction }>> = {
  enable_energy_reserve:   { key: "energy_reserve_shave", direction: "up" },
};

/** v20 (G175): the ops actions whose only effect was to move an inert dial. Rejected, never queued. */
export const INERT_OPS: Readonly<Record<string, string>> = {
  raise_deploy_surge:      "inert_ops_action: raise_deploy_surge moves deploy_surge_catchup, which nothing reads (G175)",
  extend_forecast_horizon: "inert_ops_action: extend_forecast_horizon moves forecast_horizon_min, which nothing reads (G175)",
};

/**
 * The direction an ops action would move its dial. An explicit `args.value` below the value in force makes
 * a raise a DOWN move (the SQL honours the value); the reserve switch only ever turns on. Since v20 the only
 * whitelisted ops action is that switch, so the general branch is kept for the next dial that earns an ops
 * action rather than for any action in force today.
 */
export function opsActionDirection(action: string, args: unknown, current: number | null | undefined): Direction {
  const spec = OPS_ACTION_DIAL[action];
  if (!spec) return "unknown";
  if (action === "enable_energy_reserve") return "up";
  const v = finiteOrNull((args && typeof args === "object") ? (args as Record<string, unknown>).value : null);
  if (v === null) return spec.direction;
  const d = moveDirection(v, current);
  return d === "unknown" ? spec.direction : d;
}
