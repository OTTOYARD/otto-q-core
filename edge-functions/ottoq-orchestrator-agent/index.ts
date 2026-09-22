// ottoq-orchestrator-agent — OTTO-Q PRIME (N4 / FR-4). ONE central deciding agent
// (Nemotron 3 Ultra) wearing THREE analyst lenses in a single audited call:
//   (1) depot orchestration/flow  (2) return-wave analysis  (3) energy strategy.
// Doctrine: model proposes, SQL disposes. AUTO-ACTIONS an expanded set:
//   • DIALS: 6 whitelisted policy knobs, hard-clamped + drift-limited.
//   • OPS ACTIONS: whitelisted operational moves via ottoq_apply_ops_action (clamped);
//     anything out-of-whitelist ROUTES TO THE HUMAN APPROVAL QUEUE (ottoq_ops_approvals).
//   • DIRECTIVES: operator-facing advisory text (logged + surfaced in Pulse).
// Full rationale + applied/queued/rejected into ottoq_decisions. Deterministic fallback
// (no action) — a failed model call never touches the depot. L1 shield still gates every
// physical effect; vehicle-first inviolable.
//
// v20 (0434, G164): the agent raised deploy_surge_catchup "to clear the 67-vehicle service backlog" on run
//      7a42982a's first v19 pass, with deployed (4) already above the work side's target (3) -- where the dial,
//      the share of a POSITIVE deploy gap released per tick, does nothing. The grounding block now publishes
//      work_side_demand.deploy_gap (0434) and the prompt says the dial acts only on a positive gap.
// v19 (0432, db/checks/0352): 🔴 THE AGENT WAS SETTING THE DEMAND IT IS MEASURED AGAINST, FROM A
//      BOARD THAT MISREPORTED IT. On run 0682752c the board said deploy_peak_fraction = 0.90 while
//      the dispatcher used busy_day's 0.45; the agent's first move was 0.95 -- doubling the peak
//      deployment target -- and it then asked for 0.35-0.45 on 96 of 106 writes, all clamped to the
//      0.50 floor it was never told about. All 312 stored rows of that dial were agent-written.
//      NOW:
//        * deploy_peak_fraction is the work side's DEMAND (CLAUDE.md rule 6), not a knob. It is gone
//          from KNOBS, a write to it is REJECTED here (not queued for a human), and since 0432 the
//          setter refuses it for any agent actor anyway.
//        * the board carries `grounding` (0432): values in force, each actuator's envelope, the
//          agent's own last write and last CHANGE, a real service queue, energy limits including a DR
//          call, 30-minute flow, and the work-side demand read-only. The drift clamp reads the current
//          value from there -- v18 read `board.policy`, which carried three of the six dials, so the
//          drift limiter never ran on deploy_surge_catchup or forecast_horizon_min.
//        * a write to the value already in force is rejected as `no_change`, not applied and counted
//          as a move; a reversal of the agent's own change younger than
//          grounding.stability.reversal_dwell_min is rejected as `reversal_within_dwell`.
//        * an ops action the setter refused comes back `refused` (0432 C) and is REJECTED here; it
//          used to fall into `queued`, next to real approval requests.
//        * the prompt states each dial's envelope and meaning, the stability rule, and what the queue
//          and asset blocks mean. The dial logic lives in _shared/agent_dial_discipline.ts, tested.
// v18 (0301/0304): 🔴 THE SOLVER HANDOFF NAMED AN ENGINE THAT HAD NOT RUN.
//      `engine: receipt.engine ?? "cp_sat_forward_lex"` named the primary engine whenever the
//      reply named none, and `??` falls through on null as well as undefined. So when
//      ottoq-cpsat-propose correctly DECLINED a run that was no longer live --
//      `{ok:true, skipped:"run is not active"}` -- this code recorded
//      `status:"completed", engine:"cp_sat_forward_lex", receipt:null`, and that row was read
//      for an hour as proof the agent chain had reached CP-SAT end to end. It had not: the
//      service's own uvicorn access log held ZERO `POST /assign` lines over the window
//      containing it, and the surviving evidence row at that timestamp was nvidia_nemotron
//      with no cpsat_service row carrying an endpoint anywhere near it. A decline is not a
//      success, and a default that invents an engine is how one became the other.
//      NOW: a reply carrying `skipped` records status "skipped" with engine null; the engine
//      is NEVER defaulted (absent means nothing ran); `solver_ran` is carried through from the
//      bridge; and `solverAccepted` -- which drives both the verb and outcome_status -- counts
//      only "completed" and "fallback", so a skip can no longer produce `analyze_and_solve`.
// v17: audit honesty (check 0045 R5). enacted_action gains a `verb` derived from what was
//      ACTUALLY applied, and outcome_status is 'enacted' only when something was — a tick
//      where everything the model asked for was rejected or queued now records
//      'noop_no_candidate' instead of claiming action. 100 of 822 enacted decisions on run
//      9291ec6d were verbless, all from this insert.
// v16: 🔴 FIXED — THE MODEL'S NUMBERS WERE BEING REPLACED WITH AN EXTREME.
//      v15 clamped with `if (cd.hi - cd.lo <= 1) { Math.round(value) }`. That test was
//      meant to ask "is this a whole-number dial?" but it measures RANGE WIDTH, and 4 of
//      the 6 dials are FRACTIONS with narrow ranges (deploy_peak_fraction 0.5-1.0,
//      energy_demand_factor_peak 0.3-0.9, energy_demand_factor_expensive 0.2-0.8,
//      deploy_surge_catchup 0.1-1.0). Math.round collapsed each to 0 or 1, which then
//      clamped to the dial's FLOOR or CEILING — frequently the OPPOSITE of the request.
//      Because those dials took the `if` branch, the ±30% MAX_DRIFT limiter (the actual
//      guardrail, living in the `else`) NEVER RAN on them.
//      MEASURED over 462 run-scoped writes across 123 runs before this fix:
//        asked deploy_peak_fraction 0.7 → applied 1.0 (ceiling); 0.8 → 1; 0.85 → 1
//        asked energy_demand_factor_peak 0.65 → applied 0.9 (ceiling); 0.35 → 0.3 (floor)
//        distribution: deploy_peak_fraction 106/109 = 1.00; energy_demand_factor_peak
//        107 = 0.9; energy_demand_factor_expensive 73 = 0.20; energy_reserve_shave 98/98 = 1
//      energy_demand_factor_peak feeds ottoq_energy_orchestrate (v_demand_target =
//      v_service_max * factor) where HIGHER = LESS peak shaving — so the bug pinned the
//      peak-shave dial to its most permissive setting ~88% of the time.
//      NOW: integer-ness is an EXPLICIT per-dial flag (`int`), the drift limiter applies
//      to EVERY continuous dial, and only genuinely integer dials round.
//      Also: real propose/total latency instead of hardcoded 0 (we could not previously
//      tell whether the model fits the ~0.5-1s thinking window).
// v15: reasoning disabled + robust JSON parse (Nemotron-3 <think> traces were overrunning
//      max_tokens → ~60% fell to fallback).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { normalizeSolverDirective } from "../_shared/agent_solver_chain.ts";
import {
  KNOBS, WORK_SIDE_KEYS, OPS_ACTION_DIAL,
  clampDial, currentDialValue, reversalDwellMin, admitDialChange, opsActionDirection, reversalHold,
} from "../_shared/agent_dial_discipline.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
function json(o: unknown, s = 200) { return new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); }

const OPS_WHITELIST = new Set(Object.keys(OPS_ACTION_DIAL));

const NV_KEYS = ["NVIDIA_API_KEY_NEMOTRON", "NVIDIA_API_KEY_CUOPT", "NVIDIA_API_KEY"];
const NV_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const MODEL = "nvidia/nemotron-3-ultra-550b-a55b";

function extractJson(text: string): unknown {
  const cleaned = text.replace(/<think>[\s\S]*?<\/think>/g, "").replace(/<think>[\s\S]*$/g, "");
  // scan ALL balanced {...} spans, return the last one that parses with an actions array
  let best: any = null;
  for (let k = 0; k < cleaned.length; k++) {
    if (cleaned[k] !== "{") continue;
    let depth = 0, inStr = false, esc = false;
    for (let i = k; i < cleaned.length; i++) {
      const c = cleaned[i];
      if (esc) { esc = false; continue; }
      if (c === "\\") { esc = true; continue; }
      if (c === '"') inStr = !inStr;
      if (inStr) continue;
      if (c === "{") depth++;
      else if (c === "}") { depth--; if (depth === 0) { try { const o = JSON.parse(cleaned.slice(k, i + 1)); if (o && Array.isArray((o as any).actions)) best = o; } catch { /* keep scanning */ } break; } }
    }
  }
  return best;
}

const SYSTEM = `You are OTTO-Q PRIME, the central orchestration intelligence of an autonomous-robotaxi depot. Review the BOARD DIGEST through three lenses and return STRICT JSON only — no prose, no explanation outside the JSON.

LENS 1 — DEPOT ORCHESTRATION & FLOW: service backlog, inbound pressure, assignment health, plan-vs-actual deviation. Is throughput healthy? Is the depot releasing vehicles at the pace the work side wants?
LENS 2 — RETURN-WAVE: inbound_60m vehicles have already COMMUNICATED needs. Is the depot postured for the wave (chargers, staging)?
LENS 3 — ENERGY: grid draw vs forecast vs battery. Peak shaving comes ONLY from battery + timing — NEVER from holding vehicles.

READ THE BOARD THIS WAY:
- "grounding" is the source of truth for what is true NOW. Take each dial's current value from grounding.actuators[dial].value, never from "policy".
- grounding.work_side_demand is READ-ONLY: it is the demand you are measured against (deploy_target_now vs deployed_now). You cannot change it and must not try; deploy_peak_fraction is not a dial.
- grounding.queue.waiting_for_service is the service backlog. readiness_checks_not_yet_due are the final gate check of visits still in service — NOT backlog. exit_checks_due are staged vehicles waiting for that check.
- grounding.resources are pointer counts per stall type (free_by_pointer excludes faulted chargers); general_tech is the technician pool.
- grounding.energy_limits.dr_call, when present, caps NEW charging at cap_kw for minutes_left; battery discharge does not raise that cap.
- "assets" (when present): SoC distribution, hard constraints with their causes (dcfc blocked by pack_temp_high clears by waiting; cell_balance_overdue needs service; soh_derate is permanent), deadline pressure, and a named attention list. Use it to choose the solver objective and to write directives about named vehicles.

DIALS (the only keys set_policy accepts; value in [min, max]):
  energy_demand_factor_peak [0.3, 0.9] — grid-draw target as a fraction of service_max outside expensive windows. HIGHER = draw more from the grid, shave less; LOWER = the battery covers more.
  energy_demand_factor_expensive [0.2, 0.8] — the same target during expensive-tariff windows.
  deploy_surge_catchup [0.1, 1.0] — fraction of a POSITIVE deploy gap (grounding.work_side_demand.deploy_gap = target − deployed) released per tick: how fast the depot catches up to the work side's target, never the target itself. At a gap of 0 or less it does nothing — leave it alone; it is not a service-backlog lever.
  forecast_horizon_min [10, 90] integer — arrival-forecast horizon (minutes) for energy and staging pre-positioning.
  energy_reserve_shave 0|1 — 1 = causal water-fill reserve target instead of the fixed demand factor.
STABILITY: each grounding.actuators[dial] shows last_change {direction, min_ago} and how often your requests were clamped. A dial whose last_change is younger than grounding.stability.reversal_dwell_min may move again ONLY in the same direction — a reversal is rejected. Re-sending the value already in force is rejected as no_change. Values outside [min, max] are clamped, so ask inside the range.

INVIOLABLE: vehicles/chargers are never held back; a vehicle needing charge with a free charger charges immediately; you communicate — you never move vehicles.

Return EXACTLY: {"actions":[...],"solver":{"objective":"readiness_first|throughput_first|energy_balanced","why":"<short>"},"rationale":"<3-6 sentences citing board numbers>"} where each action is one of:
  {"type":"set_policy","key":"<dial>","value":<number>,"why":"<short>"}  dials: energy_demand_factor_peak | energy_demand_factor_expensive | deploy_surge_catchup | forecast_horizon_min | energy_reserve_shave(0|1)
  {"type":"ops_action","action":"<name>","args":{},"why":"<short>"}  ops: raise_deploy_surge | extend_forecast_horizon | enable_energy_reserve (any OTHER name → human approval queue)
  {"type":"directive","text":"<advisory>","severity":"info|warning"}
The solver objective ranks feasible assignments only: readiness_first protects low-SoC readiness, throughput_first prefers faster service, and energy_balanced conserves DCFC for vehicles that need it. It never changes eligibility and never holds a vehicle back.
At most 3 policy/ops actions; dial values near current (max ±30%); prefer the smallest effective change; empty actions is a good answer when healthy — a dial that is working should be left alone. Fractional dials accept fractional values — send the precise number you intend, not a rounded one. Output ONLY the JSON object.`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const tStart = Date.now();
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const requestedDepot = body.depot_id ?? "11111111-1111-1111-1111-111111111111";
    const requestedRun = typeof body.sim_run_id === "string" && body.sim_run_id.length > 0
      ? body.sim_run_id
      : null;
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    let runQuery = sb.from("ottoq_sim_runs")
      .select("sim_run_id, depot_id, tick_count, sim_clock_current")
      .eq("status", "running");
    runQuery = requestedRun
      ? runQuery.eq("sim_run_id", requestedRun)
      : runQuery.eq("depot_id", requestedDepot).order("started_at", { ascending: false }).limit(1);
    const { data: run } = await runQuery.maybeSingle();
    if (!run) return json({ ok: true, skipped: "no running run" });
    const depot = run.depot_id;

    // 0332: multiple clocks can request an agent pass at the same run tick.
    // Claim the tick atomically before spending a model call or changing policy.
    // Chain-disabled sessions preserve the legacy behavior and are admitted by
    // the RPC without writing a claim.
    const { data: claim, error: claimError } = await sb.rpc("ottoq_agent_chain_claim", {
      p_sim_run_id: run.sim_run_id,
      p_source: "edge:ottoq-orchestrator-agent",
    });
    if (claimError) return json({ ok: false, error: `agent chain claim: ${claimError.message}` }, 500);
    if (claim?.claimed === false) {
      return json({ ok: true, run: run.sim_run_id, skipped: claim.reason ?? "agent tick already claimed",
        tick_seq: claim.tick_seq ?? run.tick_count });
    }
    const chainTriggerTick = Number(claim?.tick_seq ?? run.tick_count);

    const { data: board, error: bErr } = await sb.rpc("ottoq_agent_board", { p_sim_run_id: run.sim_run_id });
    if (bErr || !board) return json({ ok: false, error: bErr?.message ?? "no board" }, 500);

    // ---- the ONE model call (three lenses). Reasoning disabled for reliable, fast JSON. ----
    let parsed: any = null; let modelUsed = "none"; let raw = "";
    let proposeMs = 0;
    const keys = NV_KEYS
      .map((name) => ({ name, value: Deno.env.get(name) }))
      .filter((candidate): candidate is { name: string; value: string } => Boolean(candidate.value));
    if (keys.length > 0) {
      const tModel = Date.now();
      const requestBody = JSON.stringify({
        model: MODEL, temperature: 0.1, max_tokens: 1400,
        chat_template_kwargs: { enable_thinking: false }, // fast structured output for the control loop
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: SYSTEM },
          { role: "user", content: `BOARD DIGEST:\n${JSON.stringify(board, null, 1)}\n\nReturn ONLY the JSON object.` },
        ],
      });
      for (const candidate of keys) {
        try {
          const r = await fetch(NV_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: `Bearer ${candidate.value}` },
            body: requestBody,
          });
          const responseText = await r.text();
          if (!r.ok) {
            // A legacy NVCF key can be valid yet point at a retired function and return
            // 404. Keep trying the remaining configured NVIDIA keys before falling safe.
            raw = `HTTP ${r.status}: ${responseText.slice(0, 240)}`;
            continue;
          }
          const j = JSON.parse(responseText);
          raw = j?.choices?.[0]?.message?.content ?? "";
          parsed = extractJson(raw);
          if (parsed && Array.isArray(parsed.actions)) modelUsed = MODEL;
          break;
        } catch (error) {
          raw = `request error: ${error instanceof Error ? error.message : "unknown"}`;
        }
      }
      proposeMs = Date.now() - tModel;
    }
    if (!parsed || !Array.isArray(parsed.actions)) parsed = { actions: [], solver: { objective: "readiness_first", why: "model unavailable" }, rationale: `fallback: model unavailable or unparseable (${raw ? raw.slice(0,40) : "no key"}) — no action taken` };
    const solverDirective = normalizeSolverDirective(parsed.solver);

    // ---- SQL disposes: whitelist + clamps + drift, execute or QUEUE FOR APPROVAL ----
    const applied: unknown[] = []; const queued: unknown[] = []; const rejected: unknown[] = [];
    let moves = 0;
    async function queueApproval(kind: string, detail: unknown, priority = "normal") {
      const { error } = await sb.from("ottoq_ops_approvals").insert({
        approval_type: kind, sim_run_id: run.sim_run_id, depot_id: depot, status: "pending", priority,
        payload: detail, requested_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 30 * 60_000).toISOString(),
      });
      if (!error) queued.push({ kind, ...(<any>detail) }); else rejected.push({ kind, detail, reason: error.message });
    }

    const dwellMin = reversalDwellMin(board);
    for (const a of parsed.actions.slice(0, 6)) {
      if (a?.type === "set_policy" && Number.isFinite(Number(a.value))) {
        // v19: the work side's demand is not an agent actuator and not a question for the approval
        // queue either -- it is rejected with a reason the agent can read on its next board.
        if (WORK_SIDE_KEYS.has(a.key)) {
          rejected.push({ ...a, reason: "work_side_demand: read-only, not an agent actuator (0432)" });
          continue;
        }
        if (!KNOBS[a.key]) { await queueApproval("nemotron_policy_out_of_whitelist", { key: a.key, value: Number(a.value), why: a.why }); continue; }
        if (moves >= 3) { rejected.push({ ...a, reason: "move cap (3) reached" }); continue; }
        // v19: the current value comes from the grounding block (the engine's own resolution). v18 read
        // board.policy, which carried three of the six dials, so the drift limiter never ran on
        // deploy_surge_catchup or forecast_horizon_min.
        const current = currentDialValue(board, a.key);
        const c = clampDial(a.key, Number(a.value), current);
        const hold = admitDialChange(a.key, c.value, c, board?.grounding?.actuators?.[a.key], current, dwellMin);
        if (hold) { rejected.push({ ...a, reason: hold.reason, detail: hold.detail, clamped_to: c.value }); continue; }
        const { data: setRes, error } = await sb.rpc("ottoq_policy_set", { p_scope_type: "run", p_scope_id: run.sim_run_id, p_param_key: a.key, p_param_value: c.value, p_by: "ottoq_prime" });
        // G65 (0231-era): ottoq_policy_set REFUSES by RETURNING {"ok":false,"error":...}, not
        // by raising. The previous code read only `error` -- the transport failure -- so every
        // refusal arrived as error===null and was pushed to `applied` AND counted against the
        // move cap. The agent was told it had set a dial it had not set, and the audit row
        // agreed with it. There are now FIVE refusal reasons the setter can return
        // (invalid_scope_type, scope_id_required, unknown_param, outside_exclusive_bound from
        // 0303, null_value from 0306), so the number of things that could be silently wrong
        // went UP today. An agent that cannot hear "no" has the catalog in the path and none
        // of its benefit.
        //
        // The enacted value is read back from the DATABASE (setRes.applied), not from the
        // client-side clamp: the catalog may clamp further than this file's KNOBS table, and
        // when two allow-lists disagree the catalog is the one that actually wrote the row.
        // record BOTH the model's number and what was enacted, so a future audit can see
        // at a glance whether the model's judgement survived the guardrails.
        if (error) { rejected.push({ ...a, reason: `rpc: ${error.message}` }); }
        else if (!setRes || (<any>setRes).ok !== true) {
          rejected.push({ ...a, reason: `catalog refused: ${(<any>setRes)?.error ?? "no ok field in response"}`, refusal: setRes });
        } else {
          const enacted = Number((<any>setRes).applied);
          applied.push({
            type: "set_policy", key: a.key,
            value: Number.isFinite(enacted) ? enacted : c.value,
            requested: c.requested,
            limited_by: (<any>setRes).clamped === true ? `${c.limiter}+catalog` : c.limiter,
            // v19: the value this write replaced, so the grounding block can tell a change from a
            // resend without reconstructing it from the previous row.
            from: current,
          });
          moves++;
        }
      } else if (a?.type === "ops_action" && typeof a.action === "string") {
        if (moves >= 3 && OPS_WHITELIST.has(a.action)) { rejected.push({ ...a, reason: "move cap (3) reached" }); continue; }
        // v19: an ops action moves a dial too, so the reversal dwell applies to it.
        const opsDial = OPS_ACTION_DIAL[a.action];
        if (opsDial) {
          const cur = currentDialValue(board, opsDial.key);
          const hold = reversalHold(opsDial.key, opsActionDirection(a.action, a.args, cur),
                                    board?.grounding?.actuators?.[opsDial.key], dwellMin);
          if (hold) { rejected.push({ ...a, reason: hold.reason, detail: hold.detail }); continue; }
        }
        const { data: res, error } = await sb.rpc("ottoq_apply_ops_action", {
          p_sim_run_id: run.sim_run_id, p_depot_id: depot, p_action: a.action,
          p_args: (a.args && typeof a.args === "object") ? a.args : {}, p_by: "ottoq_prime",
        });
        const status = String((<any>res)?.status ?? "");
        if (error) { rejected.push({ ...a, reason: error.message }); }
        else if (status === "applied") { applied.push({ type: "ops_action", ...(<any>res) }); moves++; }
        else if (status === "queued_for_approval") { queued.push({ type: "ops_action", ...(<any>res) }); }
        // v19: 'refused' (the setter said no, 0432 C) and 'no_change' (already in force) are not
        // approval requests. v18 filed both under `queued`, next to the real ones.
        else { rejected.push({ ...a, reason: status || "no status in response", result: res }); }
      } else if (a?.type === "directive" && typeof a.text === "string") {
        applied.push({ type: "directive", text: a.text.slice(0, 400), severity: a.severity === "warning" ? "warning" : "info" });
      } else {
        rejected.push({ ...a, reason: "unrecognized action shape" });
      }
    }

    // ---- ONE PROCESS: agent analysis -> CP-SAT proposal -> deterministic core ----
    // The bridge response is awaited so the audit trail records completion,
    // fallback, or failure instead of claiming that an unobserved request queued.
    // The bridge bounds the external solver call and falls back to cuOpt.
    const chainId = crypto.randomUUID();
    let solverHandoff: Record<string, unknown> = {
      chain_id: chainId,
      status: "disabled",
      directive: solverDirective,
    };
    const { data: chainGate, error: chainGateError } = await sb.rpc("ottoq_policy_get", {
      p_sim_run_id: run.sim_run_id,
      p_param_key: "agent_solver_chain_enabled",
      p_default: 0,
    });
    if (chainGateError) {
      solverHandoff = { ...solverHandoff, status: "gate_error", error: chainGateError.message };
    } else if (Number(chainGate) >= 1) {
      const handoff = {
        chain_id: chainId,
        agent_model: modelUsed !== "none" ? modelUsed : "deterministic_fallback",
        agent_tick: chainTriggerTick,
        solver: solverDirective,
        rationale: String(parsed.rationale ?? "").slice(0, 1200),
        applied,
        queued,
        rejected,
      };
      const solverUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/ottoq-cpsat-propose`;
      const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      try {
        const response = await fetch(solverUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceKey}`,
            apikey: serviceKey,
          },
          body: JSON.stringify({ sim_run_id: run.sim_run_id, agent_handoff: handoff }),
        });
        const responseText = await response.text();
        let receipt: any = null;
        try { receipt = JSON.parse(responseText); } catch { /* bounded raw detail below */ }
        if (!response.ok || receipt?.ok !== true) {
          solverHandoff = {
            ...solverHandoff,
            status: "failed",
            engine: "cp_sat_forward_lex",
            error: String(receipt?.error ?? receipt?.primary_error ?? responseText ?? `HTTP ${response.status}`).slice(0, 600),
          };
        } else if (receipt.skipped) {
          // v18. A DECLINE IS NOT A SUCCESS. ottoq-cpsat-propose returns
          // {ok:true, skipped:"run is not active", engine:null, solver_ran:false} when the run
          // has finished -- which is correct of it, and used to be recorded here as
          // status "completed" with engine "cp_sat_forward_lex" and receipt null. That row was
          // then read as proof the chain had reached CP-SAT. It records what happened now.
          solverHandoff = {
            ...solverHandoff,
            status: "skipped",
            engine: null,
            solver_ran: false,
            skipped: String(receipt.skipped).slice(0, 200),
          };
        } else {
          solverHandoff = {
            ...solverHandoff,
            status: receipt.fallback === true ? "fallback" : "completed",
            // v18: NO DEFAULT. An absent engine means NOTHING RAN, and naming the primary
            // engine here is how a decline became a completed solve for an hour. `??` falls
            // through on null as well as undefined, so `engine: null` from the bridge was
            // being replaced too -- which is exactly why the bridge setting it was not enough
            // on its own and this line had to change.
            engine: receipt.engine ?? null,
            solver_ran: receipt.solver_ran === true,
            receipt: receipt.receipt ?? null,
            // The real numbers, so a bare "completed" never again stands in for whether
            // anything was actually proposed.
            assign: receipt.assign ?? null,
            fallback_reason: receipt.fallback_reason ?? null,
          };
        }
      } catch (error) {
        solverHandoff = {
          ...solverHandoff,
          status: "failed",
          engine: "cp_sat_forward_lex",
          error: error instanceof Error ? error.message.slice(0, 600) : "solver handoff failed",
        };
      }
    }

    const totalMs = Date.now() - tStart;
    // 0088-era audit fix (check 0045 R5). Two defects lived in this one insert:
    //  * no `verb` anywhere -- 100 of 822 enacted decisions on run 9291ec6d could not say WHAT
    //    the agent did; the AI layer was the only actor whose actions the trail lost.
    //  * outcome_status hardcoded "enacted" even when NOTHING was applied -- everything the
    //    model asked for was rejected or queued, and the audit still said the agent acted.
    // The verb is derived from what actually happened, never from what was proposed: one
    // applied ops_action names itself; one set_policy names the dial; several name the batch.
    const a0 = applied[0] as any;
    // v18: "skipped" is deliberately NOT in this list. It used to be reachable only as
    // "completed", which made a declined handoff produce the verb `analyze_and_solve` and an
    // outcome_status of `enacted` on a tick where no solver ran at all.
    const solverAccepted = ["completed", "fallback"].includes(String(solverHandoff.status));
    const verb =
      solverAccepted ? "analyze_and_solve"
      : applied.length === 0 ? "no_op"
      : applied.length === 1
        ? (a0.type === "ops_action" ? String(a0.action ?? "ops_action")
           : a0.type === "set_policy" ? `set_policy:${a0.key}`
           : String(a0.type))
      : `agent_batch:${applied.length}`;
    await sb.from("ottoq_decisions").insert({
      sim_run_id: run.sim_run_id, tick_seq: run.tick_count, sim_clock: run.sim_clock_current,
      depot_id: depot, action_context: "task_start", resolved_action_context: "orchestrator_agent",
      entity_type: "depot", entity_id: depot,
      context_frame: { board_tick: board.tick, lens: "board+return_wave+energy", fr4: true,
                       agent_solver_chain_id: chainId, agent_chain_trigger_tick: chainTriggerTick,
                       // v19: which halves of the board the model actually saw, so an audit can
                       // separate a grounded decision from one made on counters alone.
                       board_blocks: { grounding: board.grounding != null, assets: board.assets != null,
                                       review: board.review != null },
                       agent_version: "v20" },
      proposed_action: { actions: parsed.actions, solver: solverDirective, model: modelUsed,
                         agent_solver_chain_id: chainId },
      enacted_action: { verb, applied, queued, rejected, rationale: String(parsed.rationale ?? "").slice(0, 1200),
                        solver_handoff: solverHandoff,
                        source: modelUsed !== "none" ? "nemotron" : "deterministic_fallback" },
      outcome_status: applied.length > 0 || solverAccepted ? "enacted" : "noop_no_candidate",
      propose_latency_ms: proposeMs, total_latency_ms: totalMs,
    });

    return json({ ok: true, run: run.sim_run_id, model: modelUsed, applied, queued, rejected,
      solver_handoff: solverHandoff,
      latency_ms: { propose: proposeMs, total: totalMs }, rationale: parsed.rationale });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : "unknown" }, 500);
  }
});
