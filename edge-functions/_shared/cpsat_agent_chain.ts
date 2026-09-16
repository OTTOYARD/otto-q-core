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

export function assignmentRequest(input: {
  simRunId: string;
  depotId: string;
  frame: Record<string, unknown>;
  classRows: Array<Record<string, unknown>>;
  directive: SolverDirective;
  feedback: RejectionFeedback[];
  hourOfDay: number;
}) {
  return {
    sim_run_id: input.simRunId,
    depot_id: input.depotId,
    frame: input.frame,
    class_rows: input.classRows,
    site: {
      power_cap_kw_hard: 2500,
      power_soft_target_kw: 1620,
      dcfc_cooldown_min: 18,
      move_duration_min: 4,
      path_capacity: 2,
      cold_start_below_c: 5,
      cold_start_penalty_min: 12,
      onpeak_window_min: [0, 0],
    },
    directive: input.directive,
    feedback: input.feedback,
    max_assets: 8,
    det_budget_s: 0.25,
    max_retries: 2,
    hour_of_day: Math.max(0, Math.min(23, Math.trunc(input.hourOfDay))),
  };
}
