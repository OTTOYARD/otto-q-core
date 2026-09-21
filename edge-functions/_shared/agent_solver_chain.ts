export const ASSIGNMENT_OBJECTIVES = [
  "readiness_first",
  "throughput_first",
  "energy_balanced",
] as const;

export type AssignmentObjective = (typeof ASSIGNMENT_OBJECTIVES)[number];

export type SolverDirective = {
  objective: AssignmentObjective;
  why: string;
};

const OBJECTIVE_SET = new Set<string>(ASSIGNMENT_OBJECTIVES);

function finiteNumber(value: unknown, fallback: number): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

export function normalizeSolverDirective(value: unknown): SolverDirective {
  const candidate = value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
  const objective = typeof candidate.objective === "string" &&
      OBJECTIVE_SET.has(candidate.objective)
    ? candidate.objective as AssignmentObjective
    : "readiness_first";
  const why = typeof candidate.why === "string" && candidate.why.trim()
    ? candidate.why.trim().slice(0, 400)
    : "defaulted by the deterministic harness";
  return { objective, why };
}

/**
 * Bounded agent influence over the assignment LP.
 *
 * The directive changes ranking only. Compatibility and one-vehicle/one-stall
 * constraints remain structural in the LP, and the deterministic L1 shield
 * still decides whether any returned assignment can be enacted.
 *
 * ONE-VEHICLE/ONE-STALL IS TEMPORAL, AND READING IT AS INSTANTANEOUS IS HOW G109 WAS
 * MIS-FILED (retracted in db/checks/0304 §4b). `solvers/cpsat/model.py` enforces it as
 *
 *     for pid, ivs in per_point_intervals.items():
 *         if ivs:
 *             m.AddNoOverlap(ivs)      # a point serves one asset
 *
 * -- AddNoOverlap over that point's intervals. So TWO proposals naming the SAME stall in one
 * batch are correct output whenever their [planned_start_min, planned_end_min) windows are
 * disjoint: it is one stall serving two vehicles in sequence. Run f13fc580 emitted exactly
 * that (0 -> 5 and 23 -> 41 on stall 609910b1) and it was briefly filed as a violated
 * constraint by someone who compared stall_ids without opening the payload. Before calling a
 * shared stall_id a conflict, READ THE WINDOWS.
 *
 * What IS true, and is the open finding, is downstream of this file: the `assign_stall`
 * proposal envelope carries no time dimension, so the disposer -- keying on stall_id alone --
 * enacts one slot of such a plan and refuses the other with `stall_reserved`. The solver is
 * more capable than the interface it is given. Do not "fix" that in the disposer.
 */
export function assignmentPairCost(
  vehicle: Record<string, unknown>,
  stall: Record<string, unknown>,
  directive: SolverDirective,
): number {
  const soc = finiteNumber(vehicle.current_soc, 100);
  const kw = Math.min(
    finiteNumber(stall.connector_max_kw, 50),
    finiteNumber(vehicle.inlet_max_kw, 250),
  );
  const y = finiteNumber(stall.relative_y, 200);
  const dcfc = stall.stall_type === "dcfc";

  if (directive.objective === "throughput_first") {
    return Math.round((1000 - kw * 4 + y / 10 + soc / 5) * 10) / 10;
  }
  if (directive.objective === "energy_balanced") {
    const dcfcConservation = dcfc && soc >= 45 ? 180 : 0;
    return Math.round((soc + dcfcConservation + y / 20) * 10) / 10;
  }

  let cost = soc + (dcfc ? 0 : 35);
  if (dcfc && soc > 60) cost += 60;
  cost += Math.round(y / 20);
  return cost;
}
