// ottoq-cpsat-propose: internal bridge from the Nemotron agent handoff to the
// deterministic CP-SAT proposer. The Python service proposes only. Every row
// still passes through ottoq_proposer_submit_batch and the SQL safety kernel.
//
// == 0301: TWO CHANGES, BOTH EARNED BY RUN 71942fbf =========================
//
// (1) THE FIVE-SECOND ABORT WAS ABORTING A SOLVER THAT WAS ANSWERING.
//     Measured on run 71942fbf: of 176 agent handoffs, 175 fell back to cuOpt with
//     fallback_reason "Signal timed out." and exactly 1 completed. AbortSignal.timeout(5_000)
//     wrapped the /assign fetch, and 5 s does not cover a cold uvicorn plus an OR-Tools import
//     plus up to three CP-SAT solves (max_retries 2 means the service may fire three times per
//     request) on a 2-vCPU burstable t3.medium. The bound is now 20 s, which is the timeout this
//     codebase already uses for every other external solver hop (`net.http_post
//     timeout_milliseconds := 20000` in ottoq_cuopt_refresh), and it is instrumented rather than
//     guessed: every attempt now records its real latency, so the next person tightens this
//     number from evidence instead of taste.
//
// (2) THE LEDGER COULD NOT TELL THIS PATH FROM THE CI RUNNER, AND THAT MADE A REAL NUMBER LIE.
//     `ottoq_intelligence_ledger` reported "cpsat_service: 3,124 calls, 0 proposals" and NOT ONE
//     of those rows was a call: all have endpoint IS NULL and http_status IS NULL, because
//     ottoq_capture_decision_model_call maps any decision carrying l2_engine='forward_lex' to
//     provider cpsat_service. The real CP-SAT proposals came from PATH A --
//     bridge/proposer_bridge.py under proposer-loop.yml's */5 cron, connecting straight to
//     Postgres as system:db:postgres. This path is the service role and had produced zero.
//     So this function writes its OWN row per attempt with `endpoint` set, making
//     `endpoint IS NOT NULL` the predicate that separates the two.
//
//     `p_source` stays 'forward_lex' and MUST: ottoq_proposer_precedence ranks it rank 0 with
//     holds_tick=true, so renaming it would strip CP-SAT's right of first refusal.
//
// == 0613: THE SOLVER LEARNS INSIDE THE RUN ==================================
//
// Measured on run fd6ed035 (busy_day): 49 real offers, none used, 48 refused. On every tick a
// pass landed about 34 cars waited and about one charger came free; the request asked for 8 cars
// chosen by the solver's own urgency, while the kernel seats cars in its own order, so the offers
// went to cars behind the head of the line. And the rejection feedback read the last 24 refused
// rows, which 436 abstentions crowded out. So each pass now reads public.ottoq_run_learning and
// asks the solver to plan as many cars as there are free chargers (max_assets), taken in the
// kernel's order (priority); the feedback reads refused offers that named a charger; and the fire
// record carries what the pass knew. A service that predates the priority field ignores it, and a
// failed learning read leaves the request exactly as it was (learningBatch fails open).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeSolverDirective } from "../_shared/agent_solver_chain.ts";
import {
  assignmentRequest,
  FALLBACK_ASSIGNMENT_ENGINE,
  learningBatch,
  PRIMARY_ASSIGNMENT_ENGINE,
  rejectionFeedback,
  resolveSite,
} from "../_shared/cpsat_agent_chain.ts";

const ASSIGN_TIMEOUT_MS = 20_000;
const ASSIGN_ENDPOINT_LABEL = "ottoq-intelligence/assign";

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
  const envIntelligenceUrl = Deno.env.get("OTTOQ_INTEL_URL");
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

  // 0398: THE ADDRESS OF A SERVICE THAT MOVES IS DATA, NOT A DEPLOY-TIME SECRET.
  //
  // OTTOQ_INTEL_URL is set once by hand and never moves. The box carried no Elastic IP, so its
  // public IPv4 changed when it was stopped 2026-09-21 02:52 and started at 03:29:21 -- and from
  // that moment the secret named an address nothing answers on. The service was healthy the whole
  // time: ZERO POST /assign lines in its own access log, /health answering on loopback in 14 ms
  // with cp_sat_forward_lex listed, at 0.14% CPU.
  //
  // So the base URL now comes from public.ottoq_service_endpoints, which anyone with SQL access can
  // correct in one statement and which records when it last changed and why. The env var stays as
  // the fallback, so a database without the migration behaves exactly as before.
  //
  // The split is deliberate and must not be blurred: THE URL IS DATA, THE TOKEN IS A SECRET. This
  // repo is public; nothing about a credential being awkward to rotate makes a table the right
  // place for it.
  let endpointSource = "env:OTTOQ_INTEL_URL";
  let intelligenceUrl = envIntelligenceUrl;
  try {
    const { data: dbUrl } = await sb.rpc("ottoq_service_endpoint", {
      p_service_key: "intelligence",
    });
    if (typeof dbUrl === "string" && /^https?:\/\/\S+$/.test(dbUrl)) {
      intelligenceUrl = dbUrl;
      endpointSource = "db:ottoq_service_endpoints";
    }
  } catch (_) {
    // Never fatal. A lookup failure must leave the caller exactly where it was before this
    // migration existed, which is the env var.
  }

  // NEVER THROWS and never changes control flow: an evidence write that can fail the chain it is
  // observing is worse than no evidence. The ledger is append-only and class='evidence', so these
  // rows outlive the run's purge; the caller's audit row in ottoq_decisions does not.
  let ledgerRun: { depotId: string | null; tick: number | null; simClock: string | null } =
    { depotId: null, tick: null, simClock: null };
  async function logAssignAttempt(fields: {
    outcome: string;
    httpStatus?: number | null;
    latencyMs?: number | null;
    proposalsOut?: number | null;
    detail?: Record<string, unknown>;
  }) {
    try {
      await sb.rpc("ottoq_log_model_call", {
        p_provider: "cpsat_service",
        p_role: "proposer",
        p_outcome: fields.outcome,
        p_sim_run_id: simRunId,
        p_depot_id: ledgerRun.depotId,
        p_tick_seq: ledgerRun.tick,
        p_sim_clock: ledgerRun.simClock,
        p_chain_id: chainId,
        p_model: PRIMARY_ASSIGNMENT_ENGINE,
        p_endpoint: ASSIGN_ENDPOINT_LABEL,
        p_http_status: fields.httpStatus ?? null,
        p_latency_ms: fields.latencyMs ?? null,
        p_proposals_out: fields.proposalsOut ?? null,
        p_rationale_present: false,
        p_detail: { path: "edge:ottoq-cpsat-propose", endpoint_source: endpointSource,
                    ...(fields.detail ?? {}) },
        p_source_kind: "live",
      });
    } catch (_) { /* deliberately swallowed -- see above */ }
  }

  try {
    if (!intelligenceUrl || !intelligenceToken) {
      throw new Error(`CP-SAT service is not configured (url source: ${endpointSource}, url ${intelligenceUrl ? "present" : "ABSENT"}, token ${intelligenceToken ? "present" : "ABSENT"})`);
    }
    const { data: run, error: runError } = await sb.from("ottoq_sim_runs")
      .select("sim_run_id,depot_id,status,sim_clock_current,tick_count")
      .eq("sim_run_id", simRunId).maybeSingle();
    if (runError || !run) throw new Error(runError?.message ?? "run not found");
    // THE SKIP IS NOT A SUCCESS, AND SAYING SO IS THIS FIELD'S WHOLE JOB. The caller used to read
    // this reply as status "completed" with engine cp_sat_forward_lex, because it defaulted an
    // absent engine to the primary engine. `engine: null` plus `skipped` makes the decline
    // unmistakable in the reply itself, whatever the caller does with it.
    if (run.status !== "running") {
      return json({ ok: true, skipped: "run is not active", engine: null,
                    solver_ran: false, chain_id: chainId });
    }
    ledgerRun = { depotId: run.depot_id, tick: run.tick_count ?? null, simClock: run.sim_clock_current ?? null };

    const [frameResult, classResult, feedbackResult, learningResult] = await Promise.all([
      sb.rpc("ottoq_build_decision_frame", { p_depot_id: run.depot_id, p_sim_run_id: simRunId }),
      sb.from("ottoq_vehicle_classes")
        .select("vehicle_class_code,battery_capacity_kwh,max_charge_rate_kw,charge_kinds,energy_curve,battery_chemistry")
        .eq("status", "active").order("vehicle_class_code"),
      // 0613: only offers that named a charger. An abstention has no pair to learn from, and 436
      // of them on fd6ed035 filled this window and left the solver almost no feedback at all.
      sb.from("ottoq_external_proposals")
        .select("entity_id,proposal,disposition_reason,status,created_at")
        .eq("sim_run_id", simRunId).eq("source", "forward_lex")
        .in("status", ["refused", "expired"])
        .not("proposal->>stall_id", "is", null)
        .order("created_at", { ascending: false }).limit(24),
      // 0613: what this run has taught the planners -- free chargers, the kernel's queue, the batch.
      sb.rpc("ottoq_run_learning", { p_sim_run_id: simRunId, p_lookback_ticks: 20, p_detail: true }),
    ]);
    if (frameResult.error || !frameResult.data) throw new Error(`decision frame: ${frameResult.error?.message ?? "missing"}`);
    if (classResult.error) throw new Error(`class table: ${classResult.error.message}`);

    const directive = normalizeSolverDirective(handoff.solver);
    const learning = learningResult.error ? null : learningResult.data as Record<string, unknown> | null;
    const batch = learningBatch(learningResult.error ? { ok: false, error: learningResult.error.message } : learning);
    const simClock = new Date(run.sim_clock_current ?? Date.now());
    // 0389: the site power cap CP-SAT plans against is derived from the engine, not a constant in
    // this file. resolveSite never throws -- it degrades to the structural limits and says so.
    const resolvedSite = await resolveSite(sb, {
      depotId: run.depot_id,
      simRunId,
      simClock: run.sim_clock_current ?? null,
    });
    const requestBody = assignmentRequest({
      simRunId,
      depotId: run.depot_id,
      frame: frameResult.data,
      classRows: classResult.data ?? [],
      directive,
      feedback: rejectionFeedback((feedbackResult.data ?? []) as Array<Record<string, unknown>>),
      hourOfDay: Number.isNaN(simClock.getUTCHours()) ? 12 : simClock.getUTCHours(),
      site: resolvedSite.site,
      maxAssets: batch.maxAssets,
      priority: batch.priority,
    });

    // THE ONE EXTERNAL HOP, TIMED. assignMs is wall-clock around the fetch and the body read, so
    // it is the number the timeout has to cover -- not a server-side figure the service reports
    // about itself.
    const tAssign = Date.now();
    let response: Response;
    try {
      response = await fetch(`${intelligenceUrl.replace(/\/$/, "")}/assign`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${intelligenceToken}` },
        body: JSON.stringify(requestBody),
        signal: AbortSignal.timeout(ASSIGN_TIMEOUT_MS),
      });
    } catch (fetchError) {
      // A timeout or a refused connection is now COUNTABLE rather than only narrated in the
      // caller's audit row. 175 of these on run 71942fbf were invisible to the ledger.
      const ms = Date.now() - tAssign;
      await logAssignAttempt({
        outcome: "errored",
        latencyMs: ms,
        detail: {
          transport_error: fetchError instanceof Error ? fetchError.message.slice(0, 300) : "fetch failed",
          timeout_ms: ASSIGN_TIMEOUT_MS,
          timed_out: ms >= ASSIGN_TIMEOUT_MS - 250,
        },
      });
      throw fetchError;
    }
    if (!response.ok) {
      const text = (await response.text()).slice(0, 400);
      await logAssignAttempt({
        outcome: "refused",
        httpStatus: response.status,
        latencyMs: Date.now() - tAssign,
        detail: { body: text },
      });
      throw new Error(`intelligence /assign returned ${response.status}: ${text}`);
    }
    const result = await response.json();
    const assignMs = Date.now() - tAssign;
    if (!result || !Array.isArray(result.rows) || !result.fire || typeof result.fire !== "object") {
      // NAME THE CAUSE, DO NOT JUST REPORT THE SYMPTOM. "invalid proposer envelope" is what a 2xx
      // from a STALE IMAGE looks like, and that ambiguity cost a day. The optimizer list in
      // /health is the tell: a build predating assignment_cpsat.py answers ["energy_mpc"].
      let deployed = "unknown (/health unreachable)";
      try {
        const health = await fetch(`${intelligenceUrl.replace(/\/$/, "")}/health`, {
          headers: { Authorization: `Bearer ${intelligenceToken}` },
          signal: AbortSignal.timeout(3_000),
        });
        deployed = (await health.text()).slice(0, 300);
      } catch (_) { /* the reason below is still better than the old one without it */ }
      const stale = !deployed.includes(PRIMARY_ASSIGNMENT_ENGINE);
      await logAssignAttempt({
        outcome: "refused",
        httpStatus: response.status,
        latencyMs: assignMs,
        detail: { invalid_envelope: true, stale_image: stale, health: deployed },
      });
      throw new Error(
        `intelligence /assign returned an invalid proposer envelope; ` +
        (stale
          ? `/health does not list ${PRIMARY_ASSIGNMENT_ENGINE} -- THE RUNNING IMAGE PREDATES CP-SAT. `
          : `/health DOES list ${PRIMARY_ASSIGNMENT_ENGINE}, so the envelope shape is the fault, not the build. `) +
        `/health said: ${deployed}`);
    }

    // What the solver said, separated from how many rows it returned. An all-abstain answer is a
    // legitimate CP-SAT outcome and is NOT a failure, so it gets its own outcome class rather than
    // being counted as an answer with zero proposals.
    const rowCount = result.rows.length;
    const realRows = result.rows.filter((r: any) => !(r?.proposal?.abstain === true)).length;

    const fire = {
      ...result.fire,
      agent_chain_id: chainId,
      agent_model: handoff.agent_model ?? "unknown",
      agent_objective: directive.objective,
      agent_objective_why: directive.why,
      pipeline: result.pipeline ?? null,
      site_source: resolvedSite.source,
      site_fallback_reason: resolvedSite.detail,
      site_power_cap_kw_hard: resolvedSite.site.power_cap_kw_hard ?? null,
      // 0301: this path, named on the record itself. PATH A writes the same source with the same
      // shape; only submitted_by_role and this field tell them apart.
      submit_path: "edge:ottoq-cpsat-propose",
      endpoint_source: endpointSource,
      assign_latency_ms: assignMs,
      // 0613: what this pass knew when it asked, so a plan made blind and a plan made with the
      // run's lesson are never confused. priority_applied is the service's own answer: an image
      // that predates 0613 has no batch_order and reads false.
      run_learning: {
        source: batch.source,
        detail: batch.detail,
        max_assets: batch.maxAssets,
        priority_len: batch.priority?.length ?? null,
        priority_applied: result.fire?.batch_order === "kernel_queue",
        chargers_free: learning?.chargers_free ?? null,
        waiting_for_a_charger: (learning?.queue as Record<string, unknown> | undefined)?.waiting_for_a_charger ?? null,
        lesson: (learning?.lesson as Record<string, unknown> | undefined)?.code ?? null,
        feedback_pairs: requestBody.feedback.length,
      },
    };
    const { data: receipt, error: submitError } = await sb.rpc("ottoq_proposer_submit_batch", {
      p_sim_run_id: simRunId,
      p_depot_id: run.depot_id,
      p_source: "forward_lex",
      p_rows: result.rows,
      p_fire: fire,
      p_ttl_seconds: 60,
    });
    if (submitError) {
      await logAssignAttempt({
        outcome: "errored", httpStatus: response.status, latencyMs: assignMs, proposalsOut: realRows,
        detail: { submit_error: submitError.message.slice(0, 300), rows: rowCount, real_rows: realRows },
      });
      throw new Error(`proposal batch: ${submitError.message}`);
    }
    if (["refused", "error"].includes(String(receipt?.status))) {
      await logAssignAttempt({
        outcome: "refused", httpStatus: response.status, latencyMs: assignMs, proposalsOut: realRows,
        detail: { receipt, rows: rowCount, real_rows: realRows },
      });
      throw new Error(`proposal batch ${receipt.status}: ${receipt.error ?? "no detail"}`);
    }

    // A NULL RECEIPT USED TO BE UNDIAGNOSABLE. All three causes -- CP-SAT abstained on everything,
    // the batch was empty, the RPC returned nothing -- are now distinguishable from this row alone.
    await logAssignAttempt({
      outcome: realRows > 0 ? "answered" : "solved_but_zero_proposals",
      httpStatus: response.status,
      latencyMs: assignMs,
      proposalsOut: realRows,
      detail: {
        rows: rowCount,
        real_rows: realRows,
        abstained: rowCount - realRows,
        fire_status: result.fire?.status ?? null,
        objective: directive.objective,
        receipt_present: receipt !== null && receipt !== undefined,
        receipt_status: receipt?.status ?? null,
        accepted: receipt?.accepted ?? null,
        site_source: resolvedSite.source,
        attempts: result.pipeline?.attempts ?? null,
        max_assets: batch.maxAssets,
        batch_source: batch.source,
        priority_applied: result.fire?.batch_order === "kernel_queue",
      },
    });

    return json({ ok: true, chain_id: chainId, engine: PRIMARY_ASSIGNMENT_ENGINE, solver_ran: true,
      receipt, pipeline: result.pipeline,
      assign: { latency_ms: assignMs, rows: rowCount, real_rows: realRows,
                endpoint_source: endpointSource } });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "CP-SAT bridge failed";
    try {
      const requestId = await queueCuOptFallback(sb, simRunId, handoff, reason);
      return json({ ok: true, chain_id: chainId, engine: FALLBACK_ASSIGNMENT_ENGINE,
        fallback: true, solver_ran: false, fallback_reason: reason, request_id: requestId });
    } catch (fallbackError) {
      return json({ ok: false, chain_id: chainId, primary_error: reason,
        fallback_error: fallbackError instanceof Error ? fallbackError.message : "cuOpt fallback failed" }, 502);
    }
  }
});
