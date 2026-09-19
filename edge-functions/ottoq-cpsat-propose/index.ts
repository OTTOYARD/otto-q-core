// ottoq-cpsat-propose: internal bridge from the Nemotron agent handoff to the
// deterministic CP-SAT proposer. The Python service proposes only. Every row
// still passes through ottoq_proposer_submit_batch and the SQL safety kernel.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeSolverDirective } from "../_shared/agent_solver_chain.ts";
import {
  assignmentRequest,
  FALLBACK_ASSIGNMENT_ENGINE,
  PRIMARY_ASSIGNMENT_ENGINE,
  rejectionFeedback,
} from "../_shared/cpsat_agent_chain.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});

async function queueCuOptFallback(sb: any, simRunId: string, handoff: Record<string, unknown>, reason: string) {
  const fallbackHandoff = {
    ...handoff,
    primary_engine: PRIMARY_ASSIGNMENT_ENGINE,
    fallback_engine: FALLBACK_ASSIGNMENT_ENGINE,
    fallback_reason: reason.slice(0, 600),
  };
  const { data, error } = await sb.rpc("ottoq_agent_solver_refresh", {
    p_sim_run_id: simRunId,
    p_agent_handoff: fallbackHandoff,
  });
  if (error) throw new Error(`cuOpt fallback refused: ${error.message}`);
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const intelligenceUrl = Deno.env.get("OTTOQ_INTEL_URL");
  const intelligenceToken = Deno.env.get("OTTOQ_INTEL_TOKEN");
  if (!supabaseUrl || !serviceKey) {
    return json({ ok: false, error: "Supabase service configuration is unavailable" }, 500);
  }
  if (req.headers.get("authorization") !== `Bearer ${serviceKey}`) {
    return json({ ok: false, error: "internal service role required" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const simRunId = typeof body?.sim_run_id === "string" ? body.sim_run_id : "";
  const handoff = body?.agent_handoff && typeof body.agent_handoff === "object"
    ? body.agent_handoff as Record<string, unknown>
    : {};
  const chainId = typeof handoff.chain_id === "string" ? handoff.chain_id : "";
  if (!simRunId || !chainId) return json({ ok: false, error: "sim_run_id and agent_handoff.chain_id are required" }, 400);

  const sb = createClient(supabaseUrl, serviceKey);
  try {
    if (!intelligenceUrl || !intelligenceToken) {
      throw new Error("CP-SAT service is not configured");
    }
    const { data: run, error: runError } = await sb.from("ottoq_sim_runs")
      .select("sim_run_id,depot_id,status,sim_clock_current,tick_count")
      .eq("sim_run_id", simRunId).maybeSingle();
    if (runError || !run) throw new Error(runError?.message ?? "run not found");
    if (run.status !== "running") return json({ ok: true, skipped: "run is not active", chain_id: chainId });

    const [frameResult, classResult, feedbackResult] = await Promise.all([
      sb.rpc("ottoq_build_decision_frame", { p_depot_id: run.depot_id, p_sim_run_id: simRunId }),
      sb.from("ottoq_vehicle_classes")
        .select("vehicle_class_code,battery_capacity_kwh,max_charge_rate_kw,charge_kinds,energy_curve,battery_chemistry")
        .eq("status", "active").order("vehicle_class_code"),
      sb.from("ottoq_external_proposals")
        .select("entity_id,proposal,disposition_reason,status,created_at")
        .eq("sim_run_id", simRunId).eq("source", "forward_lex")
        .in("status", ["refused", "expired"])
        .order("created_at", { ascending: false }).limit(24),
    ]);
    if (frameResult.error || !frameResult.data) throw new Error(`decision frame: ${frameResult.error?.message ?? "missing"}`);
    if (classResult.error) throw new Error(`class table: ${classResult.error.message}`);

    const directive = normalizeSolverDirective(handoff.solver);
    const simClock = new Date(run.sim_clock_current ?? Date.now());
    const requestBody = assignmentRequest({
      simRunId,
      depotId: run.depot_id,
      frame: frameResult.data,
      classRows: classResult.data ?? [],
      directive,
      feedback: rejectionFeedback((feedbackResult.data ?? []) as Array<Record<string, unknown>>),
      hourOfDay: Number.isNaN(simClock.getUTCHours()) ? 12 : simClock.getUTCHours(),
    });

    const response = await fetch(`${intelligenceUrl.replace(/\/$/, "")}/assign`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${intelligenceToken}` },
      body: JSON.stringify(requestBody),
      // The solver host may be intentionally stopped between development sessions.
      // Fail over promptly instead of leaving the agent chain waiting on TCP timeout.
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error(`intelligence /assign returned ${response.status}: ${(await response.text()).slice(0, 400)}`);
    const result = await response.json();
    if (!result || !Array.isArray(result.rows) || !result.fire || typeof result.fire !== "object") {
      throw new Error("intelligence /assign returned an invalid proposer envelope");
    }

    const fire = {
      ...result.fire,
      agent_chain_id: chainId,
      agent_model: handoff.agent_model ?? "unknown",
      agent_objective: directive.objective,
      agent_objective_why: directive.why,
      pipeline: result.pipeline ?? null,
    };
    const { data: receipt, error: submitError } = await sb.rpc("ottoq_proposer_submit_batch", {
      p_sim_run_id: simRunId,
      p_depot_id: run.depot_id,
      p_source: "forward_lex",
      p_rows: result.rows,
      p_fire: fire,
      p_ttl_seconds: 60,
    });
    if (submitError) throw new Error(`proposal batch: ${submitError.message}`);
    if (["refused", "error"].includes(String(receipt?.status))) {
      throw new Error(`proposal batch ${receipt.status}: ${receipt.error ?? "no detail"}`);
    }
    return json({ ok: true, chain_id: chainId, engine: PRIMARY_ASSIGNMENT_ENGINE, receipt, pipeline: result.pipeline });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "CP-SAT bridge failed";
    try {
      const requestId = await queueCuOptFallback(sb, simRunId, handoff, reason);
      return json({ ok: true, chain_id: chainId, engine: FALLBACK_ASSIGNMENT_ENGINE,
        fallback: true, fallback_reason: reason, request_id: requestId });
    } catch (fallbackError) {
      return json({ ok: false, chain_id: chainId, primary_error: reason,
        fallback_error: fallbackError instanceof Error ? fallbackError.message : "cuOpt fallback failed" }, 502);
    }
  }
});
