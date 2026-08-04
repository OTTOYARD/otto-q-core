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

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
function json(o: unknown, s = 200) { return new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); }

// `int: true` marks a dial whose value is genuinely whole-numbered. Everything else is
// continuous and must NEVER be rounded. Do not infer this from (hi - lo) — that was the v15 bug.
const KNOBS: Record<string, { lo: number; hi: number; int?: boolean }> = {
  deploy_peak_fraction:           { lo: 0.5, hi: 1.0 },
  energy_demand_factor_peak:      { lo: 0.3, hi: 0.9 },
  energy_demand_factor_expensive: { lo: 0.2, hi: 0.8 },
  deploy_surge_catchup:           { lo: 0.1, hi: 1.0 },
  forecast_horizon_min:           { lo: 10,  hi: 90, int: true },
  energy_reserve_shave:           { lo: 0,   hi: 1,  int: true },   // binary switch
};
const OPS_WHITELIST = new Set(["raise_deploy_surge", "extend_forecast_horizon", "enable_energy_reserve"]);
const MAX_DRIFT = 0.30;

const NV_KEYS = ["NVIDIA_API_KEY_NEMOTRON", "NVIDIA_API_KEY_CUOPT", "NVIDIA_API_KEY"];
const NV_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const MODEL = "nvidia/nemotron-3-ultra-550b-a55b";

// Clamp a requested dial value: drift-limit (continuous dials only) → hard range clamp
// → round ONLY if the dial is integer-valued. Returns the value plus how it was reached,
// so the audit row shows whether the model's number survived.
function clampDial(key: string, requested: number, current: number | undefined) {
  const cd = KNOBS[key];
  const isBinary = !!cd.int && (cd.hi - cd.lo) <= 1;
  let v = requested;
  let limiter = "none";

  // ±30% drift limiter — now applied to EVERY continuous dial (in v15 it lived in an
  // else-branch that 5 of 6 dials never reached). Skipped for binary switches, where
  // drift is meaningless and a current of 0 would otherwise pin the dial at 0 forever.
  const cur = Number(current);
  if (!isBinary && Number.isFinite(cur) && cur > 0) {
    const dLo = cur * (1 - MAX_DRIFT), dHi = cur * (1 + MAX_DRIFT);
    const before = v;
    v = Math.min(dHi, Math.max(dLo, v));
    if (v !== before) limiter = "drift";
  }

  const beforeClamp = v;
  v = Math.min(cd.hi, Math.max(cd.lo, v));
  if (v !== beforeClamp) limiter = limiter === "drift" ? "drift+range" : "range";

  if (cd.int) v = Math.round(v);   // ONLY genuinely integer dials
  return { value: v, limiter, requested };
}

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

LENS 1 — DEPOT ORCHESTRATION & FLOW: gate/inbound pressure, pending needs, assignment health, plan-vs-actual deviation. Is throughput healthy? Is deploy pacing right for the hour?
LENS 2 — RETURN-WAVE: inbound_60m vehicles have already COMMUNICATED needs. Is the depot postured for the wave (chargers, staging)?
LENS 3 — ENERGY: grid draw vs forecast vs battery. Peak shaving comes ONLY from battery + timing — NEVER from holding vehicles.

INVIOLABLE: vehicles/chargers are never held back; a vehicle needing charge with a free charger charges immediately; you communicate — you never move vehicles.

Return EXACTLY: {"actions":[...],"rationale":"<3-6 sentences citing board numbers>"} where each action is one of:
  {"type":"set_policy","key":"<dial>","value":<number>,"why":"<short>"}  dials: deploy_peak_fraction | energy_demand_factor_peak | energy_demand_factor_expensive | deploy_surge_catchup | forecast_horizon_min | energy_reserve_shave(0|1)
  {"type":"ops_action","action":"<name>","args":{},"why":"<short>"}  ops: raise_deploy_surge | extend_forecast_horizon | enable_energy_reserve (any OTHER name → human approval queue)
  {"type":"directive","text":"<advisory>","severity":"info|warning"}
At most 3 policy/ops actions; dial values near current (max ±30%); prefer the smallest effective change; empty actions is a good answer when healthy. Fractional dials accept fractional values — send the precise number you intend, not a rounded one. Output ONLY the JSON object.`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const tStart = Date.now();
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot = body.depot_id ?? "11111111-1111-1111-1111-111111111111";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: run } = await sb.from("ottoq_sim_runs").select("sim_run_id, tick_count, sim_clock_current")
      .eq("depot_id", depot).eq("status", "running")
      .order("started_at", { ascending: false }).limit(1).maybeSingle();
    if (!run) return json({ ok: true, skipped: "no running run" });

    const { data: board, error: bErr } = await sb.rpc("ottoq_agent_board", { p_sim_run_id: run.sim_run_id });
    if (bErr || !board) return json({ ok: false, error: bErr?.message ?? "no board" }, 500);

    // ---- the ONE model call (three lenses). Reasoning disabled for reliable, fast JSON. ----
    let parsed: any = null; let modelUsed = "none"; let raw = "";
    let proposeMs = 0;
    const key = NV_KEYS.map((k) => Deno.env.get(k)).find(Boolean);
    if (key) {
      const tModel = Date.now();
      try {
        const r = await fetch(NV_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
          body: JSON.stringify({
            model: MODEL, temperature: 0.1, max_tokens: 1400,
            chat_template_kwargs: { enable_thinking: false }, // fast structured output for the control loop
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: SYSTEM },
              { role: "user", content: `BOARD DIGEST:\n${JSON.stringify(board, null, 1)}\n\nReturn ONLY the JSON object.` },
            ],
          }),
        });
        if (r.ok) {
          const j = await r.json();
          raw = j?.choices?.[0]?.message?.content ?? "";
          parsed = extractJson(raw);
          modelUsed = MODEL;
        } else { raw = `HTTP ${r.status}`; }
      } catch (_e) { /* deterministic fallback below */ }
      proposeMs = Date.now() - tModel;
    }
    if (!parsed || !Array.isArray(parsed.actions)) parsed = { actions: [], rationale: `fallback: model unavailable or unparseable (${raw ? raw.slice(0,40) : "no key"}) — no action taken` };

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

    for (const a of parsed.actions.slice(0, 6)) {
      if (a?.type === "set_policy" && Number.isFinite(Number(a.value))) {
        if (!KNOBS[a.key]) { await queueApproval("nemotron_policy_out_of_whitelist", { key: a.key, value: Number(a.value), why: a.why }); continue; }
        if (moves >= 3) { rejected.push({ ...a, reason: "move cap (3) reached" }); continue; }
        const c = clampDial(a.key, Number(a.value), board.policy?.[a.key]);
        const { error } = await sb.rpc("ottoq_policy_set", { p_scope_type: "run", p_scope_id: run.sim_run_id, p_param_key: a.key, p_param_value: c.value, p_by: "ottoq_prime" });
        // record BOTH the model's number and what was enacted, so a future audit can see
        // at a glance whether the model's judgement survived the guardrails.
        if (!error) { applied.push({ type: "set_policy", key: a.key, value: c.value, requested: c.requested, limited_by: c.limiter }); moves++; }
        else rejected.push({ ...a, reason: error.message });
      } else if (a?.type === "ops_action" && typeof a.action === "string") {
        if (moves >= 3 && OPS_WHITELIST.has(a.action)) { rejected.push({ ...a, reason: "move cap (3) reached" }); continue; }
        const { data: res, error } = await sb.rpc("ottoq_apply_ops_action", {
          p_sim_run_id: run.sim_run_id, p_depot_id: depot, p_action: a.action,
          p_args: (a.args && typeof a.args === "object") ? a.args : {}, p_by: "ottoq_prime",
        });
        if (error) { rejected.push({ ...a, reason: error.message }); }
        else if ((<any>res)?.status === "applied") { applied.push({ type: "ops_action", ...(<any>res) }); moves++; }
        else { queued.push({ type: "ops_action", ...(<any>res) }); }
      } else if (a?.type === "directive" && typeof a.text === "string") {
        applied.push({ type: "directive", text: a.text.slice(0, 400), severity: a.severity === "warning" ? "warning" : "info" });
      } else {
        rejected.push({ ...a, reason: "unrecognized action shape" });
      }
    }

    const totalMs = Date.now() - tStart;
    await sb.from("ottoq_decisions").insert({
      sim_run_id: run.sim_run_id, tick_seq: run.tick_count, sim_clock: run.sim_clock_current,
      depot_id: depot, action_context: "task_start", resolved_action_context: "orchestrator_agent",
      entity_type: "depot", entity_id: depot,
      context_frame: { board_tick: board.tick, lens: "board+return_wave+energy", fr4: true },
      proposed_action: { actions: parsed.actions, model: modelUsed },
      enacted_action: { applied, queued, rejected, rationale: String(parsed.rationale ?? "").slice(0, 1200),
                        source: modelUsed !== "none" ? "nemotron" : "deterministic_fallback" },
      outcome_status: "enacted", propose_latency_ms: proposeMs, total_latency_ms: totalMs,
    });

    return json({ ok: true, run: run.sim_run_id, model: modelUsed, applied, queued, rejected,
      latency_ms: { propose: proposeMs, total: totalMs }, rationale: parsed.rationale });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : "unknown" }, 500);
  }
});
