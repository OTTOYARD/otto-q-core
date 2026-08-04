// ottoq-ottocommand — the ONE shared OttoCommand agent, living ON the OTTO-Q brain (otto-q-core).
// Natural-language → intent → real, shield-gated OTTO-Q actions. v5 adds the COMMS bridge: locate a
// vehicle from the live comms bus, and escalate a manager-suggested move to the depot teleop queue.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-6";
const SB_URL = Deno.env.get("SUPABASE_URL");
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }

async function callFn(fn: string, body: unknown) {
  const r = await fetch(`${SB_URL}/functions/v1/${fn}`, { method: "POST", headers: { "Content-Type": "application/json", "Authorization": "Bearer " + SB_KEY, "apikey": SB_KEY }, body: JSON.stringify(body ?? {}) });
  const t = await r.text(); let j: any; try { j = JSON.parse(t); } catch { j = { raw: t.slice(0, 400) }; }
  if (!r.ok) return { error: `${fn} ${r.status}`, detail: j };
  return j;
}
async function callApi(path: string) {
  const r = await fetch(`${SB_URL}/functions/v1/otto-q-api/api/v1${path}`, { headers: { "Authorization": "Bearer " + SB_KEY, "apikey": SB_KEY } });
  const t = await r.text(); let j: any; try { j = JSON.parse(t); } catch { j = { raw: t.slice(0, 400) }; }
  if (!r.ok) return { error: `otto-q-api ${path} ${r.status}` };
  return j?.data ?? j;
}
async function callRpc(fn: string, args: unknown) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: { "Content-Type": "application/json", "Authorization": "Bearer " + SB_KEY, "apikey": SB_KEY }, body: JSON.stringify(args ?? {}) });
  const t = await r.text(); let j: any; try { j = JSON.parse(t); } catch { j = { raw: t.slice(0, 400) }; }
  if (!r.ok) return { error: `rpc ${fn} ${r.status}`, detail: j };
  return j;
}
async function callTable(table: string, query: string) {
  const r = await fetch(`${SB_URL}/rest/v1/${table}?${query}`, { headers: { "Authorization": "Bearer " + SB_KEY, "apikey": SB_KEY } });
  const t = await r.text(); let j: any; try { j = JSON.parse(t); } catch { j = { raw: t.slice(0, 400) }; }
  if (!r.ok) return { error: `table ${table} ${r.status}` };
  return j;
}

const TOOLS = [
  { name: "get_fleet_summary", description: "Cross-depot fleet aggregates: vehicle counts by state, SoC distribution, stall utilization, active exceptions. Use for 'how is the fleet/depot doing'.", input_schema: { type: "object", properties: {} } },
  { name: "get_schedule_intelligence", description: "OTTO-Q scheduling engine view: waves, risk, pending + applied optimizations, demand forecast.", input_schema: { type: "object", properties: { horizon: { type: "string", enum: ["12h", "24h", "48h"] } } } },
  { name: "get_energy_status", description: "Energy posture: grid/BESS/solar, tariff, demand peak, DCFC headroom from the energy co-optimizer.", input_schema: { type: "object", properties: {} } },
  { name: "get_status_brief", description: "OTTO-Q's live self-status on the running operation: how aggressively it is shaving energy, how CONFIDENT it is right now (forecast uncertainty 0-1), battery charge, recent grid peak, cars ready/charging, unsafe count. Use for 'how are you doing / how confident are you / status'.", input_schema: { type: "object", properties: {} } },
  { name: "set_energy_aggressiveness", description: "Set how hard OTTO-Q shaves the depot's peak grid power (the demand charge). aggressiveness 0 = relaxed (charge fast, higher peak), 1 = maximum shave (lowest peak, lean on the battery). REAL action, auto-clamped to the safe range. Use for 'shave the peak harder / ease off / cut our demand charge tonight'.", input_schema: { type: "object", properties: { aggressiveness: { type: "number", minimum: 0, maximum: 1 } }, required: ["aggressiveness"] } },
  { name: "evaluate_energy_options", description: "Look-ahead planner: simulate several energy-aggressiveness settings forward in the digital twin and report the predicted grid peak + demand charge for each, so you can recommend the best. Read-only.", input_schema: { type: "object", properties: {} } },
  { name: "self_improve", description: "Run OTTO-Q's self-improving loop once: it A/B-tests tweaks to its own settings in the twin and ADOPTS any that do strictly better with zero safety loss; rejects the rest. Returns what it decided. Safe (shield-gated).", input_schema: { type: "object", properties: {} } },
  { name: "get_improvement_log", description: "Recent self-improvement decisions (what OTTO-Q tried, adopted or rejected, and why). Use for 'what have you changed / what have you learned'.", input_schema: { type: "object", properties: {} } },
  { name: "recommend_actions", description: "Ask the OTTO-Q Nemotron agent to predict + propose an energy/SLA-aware depot plan.", input_schema: { type: "object", properties: { max_vehicles: { type: "number" } } } },
  { name: "reoptimize_depot", description: "Run OTTO-Q's depot-wide re-optimizer NOW (cuOpt charge assignment + energy cap + 52-rule shield, stability-biased). A real action; safe (shield-gated).", input_schema: { type: "object", properties: {} } },
  { name: "sequence_vehicle", description: "Get/compute a vehicle's coded multi-service sequence (charge/clean/service/staging across the right stalls).", input_schema: { type: "object", properties: { vehicle_id: { type: "string" } }, required: ["vehicle_id"] } },
  { name: "cleaning_due", description: "What cleaning a vehicle is due for (interior detail = daily, exterior wash = weekly/bi-weekly).", input_schema: { type: "object", properties: { vehicle_id: { type: "string" } }, required: ["vehicle_id"] } },
  { name: "amend_schedule", description: "Amend a vehicle's plan (OTTO-Q re-queues, stability-biased). Managers REQUEST changes; technicians execute/confirm. type is one of service_add|service_remove|reorder|stall_reassignment|priority_change|departure_change.", input_schema: { type: "object", properties: { vehicle_id: { type: "string" }, type: { type: "string" }, service_code: { type: "string" }, priority: { type: "string" } }, required: ["vehicle_id", "type"] } },
  { name: "locate_vehicle", description: "Find where a specific vehicle is and why — its current physical state + SoC, its dispatch/queue status, and its recent vehicle↔OTTO-Q↔teleoperator comms line by line. Use when asked 'where is vehicle X / why is it stuck / what is vehicle X doing'. Accepts a full id or the short id shown in the cockpit (e.g. 03726c33).", input_schema: { type: "object", properties: { vehicle: { type: "string" } }, required: ["vehicle"] } },
  { name: "escalate_to_depot", description: "Escalate a manager-suggested move to the depot/teleoperator queue for HUMAN confirmation — e.g. elevate a stuck vehicle's queue position (priority_restage) or request a temporary stage. This does NOT move the vehicle directly; it places a one-tap Approve/Deny in front of the depot operator (indirect control, SAE J3016). Use when a manager wants to intervene on a specific vehicle outside normal orchestration.", input_schema: { type: "object", properties: { vehicle: { type: "string" }, action: { type: "string", description: "short action code, e.g. priority_restage, temporary_stage, elevate_queue" }, reason: { type: "string" } }, required: ["vehicle", "action"] } },
];

async function runTool(name: string, input: any, role: string, depot_id: string) {
  switch (name) {
    case "get_fleet_summary": return await callApi("/fleet/summary");
    case "get_schedule_intelligence": return await callApi(`/fleet/schedule-intelligence?horizon=${input?.horizon ?? "24h"}`);
    case "get_energy_status": return await callFn("ottoq-energy-optimize", { depot_id });
    case "get_status_brief": return await callRpc("ottoq_nl_status_brief", { p_sim_run_id: null });
    case "set_energy_aggressiveness": {
      const a = Math.max(0, Math.min(1, Number(input?.aggressiveness ?? 0.5)));
      const factor = Number((0.90 - a * 0.75).toFixed(3)); // 0→0.90 relaxed, 1→0.15 max shave (policy_set clamps to safe range)
      return await callRpc("ottoq_policy_set", { p_scope_type: "depot", p_scope_id: depot_id, p_param_key: "energy_demand_factor_peak", p_param_value: factor, p_by: "ottocommand" });
    }
    case "evaluate_energy_options": {
      const run = await callRpc("ottoq_active_sim_run", {});
      if (!run || run?.error) return { note: "No simulation is currently running to look ahead on." };
      return await callRpc("ottoq_mpc_energy_lookahead", { p_sim_run_id: run, p_horizon_ticks: 3, p_factors: [0.20, 0.35, 0.50, 0.65] });
    }
    case "self_improve": {
      const run = await callRpc("ottoq_active_sim_run", {});
      if (!run || run?.error) return { note: "No simulation is currently running to self-improve on." };
      return await callRpc("ottoq_cil_tick", { p_sim_run_id: run, p_horizon: 3 });
    }
    case "get_improvement_log": return await callTable("ottoq_cil_adoptions", "select=decided_at,adopted,plan_label,score_current,score_adopted,rationale&order=decided_at.desc&limit=5");
    case "recommend_actions": return await callFn("ottoq-orchestrator-agent", { depot_id, max_vehicles: input?.max_vehicles ?? 6 });
    case "reoptimize_depot": return await callFn("ottoq-orchestrate-tick", { depot_id, submit: true });
    case "sequence_vehicle": return await callFn("ottoq-sequence-optimize", { vehicle_id: input?.vehicle_id, depot_id });
    case "cleaning_due": return await callFn("ottoq-cleaning-cadence", { vehicle_id: input?.vehicle_id });
    case "amend_schedule": {
      const requested_by = role === "technician" ? "yard_supervisor" : "fleet_operator";
      const amendment: any = { type: input?.type, service_code: input?.service_code, priority: input?.priority };
      return await callFn("ottoq-amend", { vehicle_id: input?.vehicle_id, amendment, commit: true, requeue: true, requested_by });
    }
    case "locate_vehicle": return await callRpc("ottoq_comms_locate_vehicle", { p_query: String(input?.vehicle ?? "") });
    case "escalate_to_depot": return await callRpc("ottoq_comms_manager_escalate", { p_vehicle_query: String(input?.vehicle ?? ""), p_action: String(input?.action ?? "priority_restage"), p_reason: input?.reason ?? null });
    default: return { error: "unknown tool " + name };
  }
}

function systemPrompt(role: string, depot_id: string) {
  const who = role === "technician"
    ? "You are speaking with a DEPOT TECHNICIAN / yard supervisor in OTTO-PULSE. They execute and confirm work on the ground and have the final say on what physically happens."
    : "You are speaking with a FLEET MANAGER / asset owner in OrchestraAV. They request and select services and watch fleet-wide analytics; the depot side executes it.";
  return [
    "You are OttoCommand, the conversational interface to OTTO-Q — the central AV/EV depot orchestration brain (deterministic 52-rule safety shield + cuOpt assignment + energy control + multi-service sequencing + a twin look-ahead planner + a self-improving loop).",
    "OTTO-Q is the single source of truth. NEVER invent numbers — call tools to read live state and to take real, shield-gated actions, then explain results plainly and concisely.",
    "You can also drive OTTO-Q's frontier controls in plain language: set_energy_aggressiveness (how hard to shave the demand-charge peak), evaluate_energy_options (look ahead in the twin and recommend the best setting), self_improve (let OTTO-Q A/B-test and adopt a better setting), get_status_brief (live status + how confident OTTO-Q is). Every change stays clamped to safe ranges and gated by the shield.",
    "You can read the live fleet comms bus: locate_vehicle answers 'where is vehicle X / why is it stuck' from its physical state, dispatch/queue status, and recent vehicle↔OTTO-Q↔teleoperator messages, line by line. If a manager wants to intervene on a specific vehicle (move it up the queue, re-stage it), use escalate_to_depot — you never move the vehicle directly; it places a one-tap Approve/Deny in front of the depot operator/teleoperator, who confirms the movement (indirect control).",
    who,
    "Respect role: a manager REQUESTS; a technician EXECUTES/CONFIRMS. If an action is out of the user's role, explain who performs it.",
    `Active depot: ${depot_id}. Be concise, specific, and operational. Surface energy/SLA/safety implications when relevant.`,
  ].join("\n");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    if (!ANTHROPIC_KEY) return json({ error: "ANTHROPIC_API_KEY not set on otto-q-core" }, 500);
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const message = body.message;
    const role = (body.role === "technician" || body.role === "manager") ? body.role : "manager";
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    if (!message) return json({ error: "message required" }, 400);

    const messages: any[] = Array.isArray(body.history) ? [...body.history] : [];
    messages.push({ role: "user", content: message });

    const actions: any[] = [];
    let finalText = "";
    for (let round = 0; round < 6; round++) {
      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-api-key": ANTHROPIC_KEY, "anthropic-version": "2023-06-01" },
        body: JSON.stringify({ model: MODEL, max_tokens: 1500, system: systemPrompt(role, depot_id), tools: TOOLS, messages }),
      });
      const data = await resp.json();
      if (!resp.ok) return json({ error: "anthropic " + resp.status, detail: data }, 502);

      const content = data.content ?? [];
      finalText = content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n").trim() || finalText;
      const toolUses = content.filter((b: any) => b.type === "tool_use");
      if (data.stop_reason !== "tool_use" || toolUses.length === 0) break;

      messages.push({ role: "assistant", content });
      const results: any[] = [];
      for (const tu of toolUses) {
        const out = await runTool(tu.name, tu.input ?? {}, role, depot_id);
        actions.push({ tool: tu.name, input: tu.input, ok: !out?.error });
        results.push({ type: "tool_result", tool_use_id: tu.id, content: JSON.stringify(out).slice(0, 6000) });
      }
      messages.push({ role: "user", content: results });
    }

    return json({ reply: finalText || "(no response)", role, depot_id, actions, model: MODEL });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
