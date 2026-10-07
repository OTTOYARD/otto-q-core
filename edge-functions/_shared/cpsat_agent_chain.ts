import type { SolverDirective } from "./agent_solver_chain.ts";

export const PRIMARY_ASSIGNMENT_ENGINE = "cp_sat_forward_lex";
export const FALLBACK_ASSIGNMENT_ENGINE = "cuopt";

export type RejectionFeedback = {
  entity_id: string;
  stall_id: string;
  reason: string | null;
  rule_codes: string[];
};

export function rejectionFeedback(rows: Array<Record<string, unknown>>): RejectionFeedback[] {
  const seen = new Set<string>();
  const feedback: RejectionFeedback[] = [];
  for (const row of rows) {
    const proposal = row.proposal && typeof row.proposal === "object"
      ? row.proposal as Record<string, unknown>
      : {};
    const entityId = typeof row.entity_id === "string" ? row.entity_id : "";
    const stallId = typeof proposal.stall_id === "string" ? proposal.stall_id : "";
    if (!entityId || !stallId) continue;
    const key = `${entityId}:${stallId}`;
    if (seen.has(key)) continue;
    seen.add(key);
    feedback.push({
      entity_id: entityId,
      stall_id: stallId,
      reason: typeof row.disposition_reason === "string" ? row.disposition_reason : null,
      rule_codes: [],
    });
  }
  return feedback;
}

// THE STRUCTURAL FALLBACK, and it is a fallback now rather than the answer.
//
// These are the twin depot's STRUCTURAL limits: 2500 kW is depots.service_max_kw (the
// utility service) and 1620 is dcfc_max_concurrent_kw 1800 x (1 - dcfc_safety_margin_pct
// 10/100). They are correct as structural limits and wrong as the cap to plan against,
// because solvers/cpsat/model.py spends power_cap_kw_hard as a CP-SAT *cumulative
// capacity* while the cap the decide path enforces is ottoq_active_charge_cap_kw -- which
// read 795, 659.5 and 595.3 kW across three consecutive measurements on run 1efeb1cd.
//
// 0389's public.ottoq_build_site_descriptor derives the live answer and tightens only:
// with no cap in force it returns exactly these numbers. So this object is kept as the
// value to use when the RPC is unreachable -- a proposer that plans against the
// structural limit is worse than one that plans against the live cap, and far better
// than a chain that refuses to solve because one RPC failed.
export const STRUCTURAL_SITE = {
  power_cap_kw_hard: 2500,
  power_soft_target_kw: 1620,
  dcfc_cooldown_min: 18,
  move_duration_min: 4,
  path_capacity: 2,
  cold_start_below_c: 5,
  cold_start_penalty_min: 12,
  onpeak_window_min: [0, 0],
} as const;

export type SiteDescriptor = Record<string, unknown>;

/** The site descriptor 0389 derives, or the structural fallback with the reason why.
 *
 * NEVER THROWS. The site descriptor is an input to an advisory proposer; losing it must
 * degrade the plan's tightness, never take the agent chain down. The returned `source`
 * travels into the fire record so a reader can tell a live-cap plan from a fallback one
 * instead of having to assume.
 */
export async function resolveSite(
  sb: { rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }> },
  input: { depotId: string; simRunId: string; simClock: string | null },
): Promise<{ site: SiteDescriptor; source: string; detail: string | null }> {
  try {
    const { data, error } = await sb.rpc("ottoq_build_site_descriptor", {
      p_depot_id: input.depotId,
      p_sim_run_id: input.simRunId,
      p_sim_clock: input.simClock,
    });
    if (error) throw new Error(String((error as { message?: string }).message ?? error));
    const site = data as SiteDescriptor | null;
    // Read what came back, never what was asked for. A descriptor missing either power
    // key would reach OR-Tools as a KeyError inside the model build and report as a
    // solver fault rather than the data fault it is.
    for (const key of ["power_cap_kw_hard", "power_soft_target_kw"]) {
      const v = site?.[key];
      if (typeof v !== "number" || !Number.isInteger(v)) {
        // model.py: NewIntVar(0, hard) -- OR-Tools 9.15.6755 refuses a non-integral
        // bound outright (Domain(arg0: int, arg1: int)). 0389 floors in SQL; this is
        // the assertion that the flooring happened.
        throw new Error(`descriptor ${key}=${JSON.stringify(v)} is not an integer`);
      }
    }
    return { site: site as SiteDescriptor, source: "ottoq_build_site_descriptor", detail: null };
  } catch (err) {
    return {
      site: { ...STRUCTURAL_SITE },
      source: "structural_fallback",
      detail: err instanceof Error ? err.message.slice(0, 300) : "site descriptor unavailable",
    };
  }
}

// 0613. THE BATCH COMES FROM THE RUN, NOT FROM A CONSTANT.
//
// Measured on run fd6ed035 (busy_day): on all 46 ticks this proposer fired, about 34 cars waited
// for a charger and about one charger came free, and a fixed batch of 8 chosen by the solver's own
// urgency put 48 of 49 offers on chargers the kernel had just given to cars ahead in its line.
// public.ottoq_run_learning publishes the two numbers that fix it: max_assets = the free chargers
// (1..8) and priority = the kernel's charge queue in the order it seats cars.
export const DEFAULT_MAX_ASSETS = 8;
export const MAX_PRIORITY = 24;

export type LearningBatch = {
  maxAssets: number;
  priority: string[] | null;
  source: "run_learning" | "default";
  detail: string | null;
};

/** The batch ottoq_run_learning asks for, or the old fixed batch with the reason why.
 *
 * NEVER THROWS, and fails OPEN to exactly what the request was before 0613 (8 cars, the solver's
 * own order). The learning read is advice to an advisory proposer; losing it must cost the plan its
 * focus, never the chain its pass.
 */
export function learningBatch(learning: unknown): LearningBatch {
  const l = learning && typeof learning === "object" ? learning as Record<string, unknown> : null;
  if (!l || l.ok !== true) {
    const why = l && typeof l.error === "string" ? l.error : "learning read unavailable";
    return { maxAssets: DEFAULT_MAX_ASSETS, priority: null, source: "default", detail: why.slice(0, 200) };
  }
  const batch = l.batch && typeof l.batch === "object" ? l.batch as Record<string, unknown> : {};
  const n = Number(batch.max_assets);
  const maxAssets = Number.isInteger(n) && n >= 1 ? Math.min(n, DEFAULT_MAX_ASSETS) : DEFAULT_MAX_ASSETS;
  const priority = Array.isArray(batch.priority)
    ? batch.priority.filter((id): id is string => typeof id === "string" && id.length > 0).slice(0, MAX_PRIORITY)
    : null;
  return { maxAssets, priority, source: "run_learning", detail: null };
}

export function assignmentRequest(input: {
  simRunId: string;
  depotId: string;
  frame: Record<string, unknown>;
  classRows: Array<Record<string, unknown>>;
  directive: SolverDirective;
  feedback: RejectionFeedback[];
  hourOfDay: number;
  site?: SiteDescriptor;
  maxAssets?: number;
  priority?: string[] | null;
}) {
  const n = Number(input.maxAssets);
  return {
    sim_run_id: input.simRunId,
    depot_id: input.depotId,
    frame: input.frame,
    class_rows: input.classRows,
    site: input.site ?? { ...STRUCTURAL_SITE },
    directive: input.directive,
    feedback: input.feedback,
    max_assets: Number.isInteger(n) && n >= 1 ? Math.min(n, DEFAULT_MAX_ASSETS) : DEFAULT_MAX_ASSETS,
    // Sent only when the run supplied it. A service that predates 0613 ignores the key (pydantic's
    // default), so this request is safe against the image that is running before the redeploy.
    ...(Array.isArray(input.priority) ? { priority: input.priority.slice(0, MAX_PRIORITY) } : {}),
    det_budget_s: 0.25,
    max_retries: 2,
    hour_of_day: Math.max(0, Math.min(23, Math.trunc(input.hourOfDay))),
  };
}
