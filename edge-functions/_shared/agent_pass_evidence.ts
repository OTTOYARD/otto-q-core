/**
 * One agent pass, recorded as evidence (edge function v29, migration 0703), and the wake gate's verdict (0705).
 *
 * WHY. Until v29 no agent decision could be replayed: the board the model read was never stored, the prompt was never
 * hashed, the token use was discarded and every pass that issued a directive or reached the solver read 'enacted'.
 * Since 2026-10-08, 766 of 766 agent ledger rows read 'enacted' against 14 passes that changed engine state (the study
 * of 2026-10-13). This module turns a pass into one honest row of public.ottoq_agent_pass_evidence:
 *
 *   changed_state  a lever moved the depot: the kernel took the charge order (accepted/partial), or a dial or ops
 *                  action was applied
 *   echo           the charge order was the kernel's own (refused, projection.reason same_as_kernel) and nothing moved
 *   advisory       directives or approval requests only
 *   no_effect      the model answered and nothing it asked for took effect
 *   solver_only    the model was not consulted (0705: no wake event); the solver ran on the standing objective
 *   fallback       the model was consulted and did not answer
 *   failed         the pass broke before its decision was written
 *
 * Pure apart from crypto.subtle, so `node --test tests/*.test.mjs` drives it.
 */

export type OutcomeClass =
  | "changed_state" | "echo" | "advisory" | "no_effect" | "solver_only" | "fallback" | "failed";

export type Levers = {
  order_submitted: boolean;
  order_status: string | null;
  order_reason: string | null;
  order_taken: boolean;
  dials_applied: number;
  ops_applied: number;
  ops_queued: number;
  directives_issued: number;
  rejected: number;
  solver_status: string | null;
  solver_proposals_out: number | null;
  objective: string | null;
};

type Action = { type?: string } & Record<string, unknown>;

/** The hex sha256 of a string's UTF-8 bytes -- the same digest public.ottoq_sha256_utf8 computes in the database. */
export async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The board exactly as the model receives it. One function, so the hash and the prompt can never disagree. */
export function boardText(board: unknown): string {
  return JSON.stringify(board, null, 1);
}

function proposalsOut(handoff: Record<string, unknown> | null | undefined): number | null {
  const assign = (handoff as any)?.assign;
  // ottoq-cpsat-propose answers assign: { rows, real_rows } -- real_rows are the proposals it stood behind (not abstentions)
  for (const k of ["real_rows", "proposals_out", "submitted"]) {
    const v = assign?.[k];
    if (typeof v === "number" && Number.isFinite(v)) return v;
    if (Array.isArray(v)) return v.length;
  }
  return null;
}

/** What each lever did on this pass, read from what the kernel and the setters actually answered. */
export function leversOf(input: {
  applied: Action[];
  queued: unknown[];
  rejected: unknown[];
  chargeOrderReceipt: Record<string, unknown> | null;
  solverHandoff: Record<string, unknown> | null;
  objective: string | null;
}): Levers {
  const r = input.chargeOrderReceipt as any;
  const status = typeof r?.status === "string" ? r.status : null;
  const reason = typeof r?.projection?.reason === "string" ? r.projection.reason
    : typeof r?.reason === "string" ? r.reason : null;
  return {
    order_submitted: r != null && r.skipped == null,
    order_status: status,
    order_reason: reason,
    order_taken: r?.ok === true && (status === "accepted" || status === "partial"),
    dials_applied: input.applied.filter((a) => a?.type === "set_policy").length,
    ops_applied: input.applied.filter((a) => a?.type === "ops_action").length,
    ops_queued: input.queued.length,
    directives_issued: input.applied.filter((a) => a?.type === "directive").length,
    rejected: input.rejected.length,
    solver_status: typeof input.solverHandoff?.status === "string" ? String(input.solverHandoff.status) : null,
    solver_proposals_out: proposalsOut(input.solverHandoff),
    objective: input.objective,
  };
}

/** The one honest class of a pass. Precedence: what failed, then what was not asked, then what moved the depot. */
export function classifyPass(o: { consulted: boolean; answered: boolean; failed?: boolean; levers: Levers }): OutcomeClass {
  if (o.failed) return "failed";
  if (!o.consulted) return "solver_only";
  if (!o.answered) return "fallback";
  const l = o.levers;
  if (l.order_taken || l.dials_applied > 0 || l.ops_applied > 0) return "changed_state";
  if (l.order_status === "refused" && l.order_reason === "same_as_kernel") return "echo";
  if (l.directives_issued > 0 || l.ops_queued > 0) return "advisory";
  return "no_effect";
}

/** The wake gate's verdict as edge v29 reads it. A missing or failing gate always wakes: it can cost a model call,
 *  never skip one. */
export type Wake = {
  wake: boolean;
  would_wake?: boolean;
  gate?: string;
  reasons?: string[];
  fingerprint?: Record<string, unknown>;
  standing_objective?: string;
  error?: string;
};

export function readWake(data: unknown, error: { message?: string } | null | undefined): Wake {
  if (error) return { wake: true, would_wake: true, reasons: ["wake_rpc_error"], error: String(error.message ?? error).slice(0, 300) };
  const w = data as any;
  if (!w || typeof w !== "object" || typeof w.wake !== "boolean") {
    return { wake: true, would_wake: true, reasons: ["wake_unreadable"] };
  }
  return w as Wake;
}

export const STANDING_OBJECTIVES = new Set(["readiness_first", "throughput_first", "energy_balanced"]);

/** The objective a solver-only pass runs on: the one the agent last chose, else readiness_first. */
export function standingObjective(w: Wake): string {
  return w.standing_objective && STANDING_OBJECTIVES.has(w.standing_objective) ? w.standing_objective : "readiness_first";
}
