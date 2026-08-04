// ottoq-orchestrate-tick — OTTO-Q depot-wide continuous re-optimizer (the LIVE production brain).
// One tick: see the WHOLE depot -> energy budget -> cuOpt-assign contended charge stalls across all
// waiting vehicles -> sequence each vehicle's full service chain from shared resource pools ->
// STABILITY BIAS (lock technician-confirmed / in-progress tasks + stalls) -> then feed the whole plan
// through ottoq_shield_and_log: the 52-rule shield gates EVERY action FAIL-CLOSED + writes a full
// ottoq_decisions audit row on the canonical production run, recommending only shield-cleared actions
// (advisory; technician confirms in OTTO-PULSE). This is the unified, shielded, auditable live brain.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const CUOPT = "https://optimize.api.nvidia.com/v1/nvidia/cuopt";
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
const DCFC_KW = 150;
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d = 0) { const n = Number(x); return isFinite(n) ? n : d; }
const CATALOG: Record<string, { kind: string; rank: number; dur: number; energy?: boolean }> = {
  charge: { kind: "charging", rank: 1, dur: 40, energy: true }, dcfc_charge: { kind: "charging", rank: 1, dur: 25, energy: true }, l2_charge: { kind: "charging", rank: 1, dur: 120, energy: true },
  inspection: { kind: "inspection", rank: 2, dur: 20 }, maintenance: { kind: "service", rank: 2, dur: 45 },
  cabin_filter: { kind: "service", rank: 2, dur: 15 }, tire_rotation: { kind: "service", rank: 2, dur: 25 }, wiper_replace: { kind: "service", rank: 2, dur: 10 },
  exterior_wash: { kind: "wash", rank: 3, dur: 15 }, wash: { kind: "wash", rank: 3, dur: 15 }, interior_detail: { kind: "wash", rank: 4, dur: 30 }, detail: { kind: "wash", rank: 4, dur: 30 }, full_detail: { kind: "wash", rank: 4, dur: 60 },
  staging: { kind: "staging", rank: 8, dur: 5 }, final_approval: { kind: "staging", rank: 9, dur: 5 },
};
const KIND_STALLS: Record<string, string[]> = { charging: ["charging"], inspection: ["inspection"], service: ["service"], wash: ["wash", "detail"], staging: ["staging"] };
const SHARED_BAY = new Set(["wash", "service"]);
function chargeCompatible(inlet: string, st: any) {
  const sup = st.supported_inlet_types; const list = Array.isArray(sup) ? sup : (sup ? [sup] : []);
  if (list.length && inlet) return list.map((x: any) => String(x).toUpperCase()).includes(String(inlet).toUpperCase());
  if (st.connector_type && inlet) { const c = String(st.connector_type).toUpperCase(); return c === "MULTI" || c === String(inlet).toUpperCase(); }
  return true;
}

async function cuoptCharge(apiKey: string, vehicles: any[], stalls: any[]) {
  const n = vehicles.length, m = stalls.length, dim = n + m, BIG = 1000000;
  const cost = Array.from({ length: dim }, (_, i) => Array.from({ length: dim }, (_, j) => {
    if (i === j) return 0;
    if (i < n && j >= n) { const v = vehicles[i], s = stalls[j - n];
      if (!chargeCompatible(v.inlet_type, s)) return BIG;
      const soc = num(v.current_soc, 100); let c = (100 - soc) + (s.stall_type === "dcfc" ? 0 : 35); if (s.stall_type === "dcfc" && soc > 60) c += 60; return Math.round(c); }
    return 1; }));
  const payload = { action: "cuOpt_OptimizedRouting", data: {
    task_data: { task_locations: vehicles.map((_, i) => i), demand: [vehicles.map(() => 1)], task_time_windows: vehicles.map(() => [0, 86400]), service_times: vehicles.map(() => 1) },
    fleet_data: { vehicle_locations: stalls.map((_, i) => [n + i, n + i]), capacities: [stalls.map(() => 1)], vehicle_types: stalls.map(() => 0), vehicle_time_windows: stalls.map(() => [0, 86400]) },
    cost_matrix_data: { data: { "0": cost } }, solver_config: { time_limit: 5 } } };
  const res = await fetch(CUOPT, { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey, Accept: "application/json" }, body: JSON.stringify(payload) });
  const txt = await res.text(); if (!res.ok) throw new Error("HTTP " + res.status + ": " + txt.slice(0, 160));
  const result = JSON.parse(txt); const out: Record<string, string> = {};
  const vd = result?.response?.solver_response?.vehicle_data ?? result?.response?.solver_infeasible_response?.vehicle_data;
  if (vd) for (const sIdx of Object.keys(vd)) { const r = vd[sIdx]; if (r.task_id) for (const tid of r.task_id) { const tnum = typeof tid === "number" ? tid : parseInt(String(tid).replace(/[^0-9]/g, "")); const v = vehicles[tnum], s = stalls[parseInt(sIdx)]; if (v && s) out[v.id] = s.id; } }
  return out;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    const maxV = Math.min(num(body.max_vehicles, 12), 30);
    const submit = body.submit === true; const shadow = body.shadow !== false;
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const [{ data: depot }, { data: energyRows }, { data: vehicles }, { data: stalls }, { data: locked }] = await Promise.all([
      sb.from("depots").select("name,service_max_kw,dcfc_max_concurrent_kw,dcfc_safety_margin_pct").eq("id", depot_id).maybeSingle(),
      sb.from("site_energy_snapshots").select("building_load_kw,billing_period_peak_kw,solar_generation_kw,current_tariff_label,current_rate_per_kwh").eq("depot_id", depot_id).order("created_at", { ascending: false }).limit(1),
      sb.from("vehicles").select("id,display_name,current_soc,target_soc,inlet_type,current_state,default_service_sequence").eq("home_depot_id", depot_id).in("current_state", ["arrived_at_gate", "staged_awaiting_service", "charge_complete_holding"]).order("current_soc", { ascending: true }).limit(maxV),
      sb.from("stalls").select("id,stall_code,stall_type,stall_kind,connector_type,supported_inlet_types,distance_from_entrance").eq("depot_id", depot_id).eq("status", "available"),
      sb.from("schedule_tasks").select("assigned_stall_id,actual_stall_id,vehicle_id").in("status", ["in_progress"]).not("assigned_stall_id", "is", null),
    ]);
    if (!depot) return json({ error: "depot not found" }, 404);
    const e = energyRows?.[0] ?? {};
    const cands = vehicles ?? [];
    const lockedStalls = new Set<string>(); for (const l of (locked ?? [])) { if (l.assigned_stall_id) lockedStalls.add(l.assigned_stall_id); if (l.actual_stall_id) lockedStalls.add(l.actual_stall_id); }
    const freeStalls = (stalls ?? []).filter((s: any) => !lockedStalls.has(s.id));
    if (cands.length === 0) return json({ depot: depot.name, vehicles: 0, note: "no vehicles need action" });

    const serviceMax = num(depot.service_max_kw, 2500); const margin = num(depot.dcfc_safety_margin_pct, 10) / 100;
    const billingPeak = num(e.billing_period_peak_kw, serviceMax * 0.6); const building = num(e.building_load_kw, 0);
    // Cap at the depot's hard capacity; respect the historical billing peak as a shave target, but
    // never let a low historical peak (e.g. an idle billing period) zero out NECESSARY charging —
    // floor at serviceMax*0.5 so the fleet can always charge (the first wave inevitably sets a peak).
    const effectiveCap = Math.min(serviceMax * (1 - margin), Math.max(billingPeak, serviceMax * 0.5));
    const dcfcBudgetKw = Math.max(0, Math.min(num(depot.dcfc_max_concurrent_kw, effectiveCap), effectiveCap - building));
    const maxConcurrentDcfc = Math.max(0, Math.floor(dcfcBudgetKw / DCFC_KW));

    const svcOf = (v: any): string[] => Array.isArray(v.default_service_sequence) && v.default_service_sequence.length ? v.default_service_sequence : ["charge", "inspection", "staging"];
    const chargeVehicles = cands.filter((v: any) => svcOf(v).some((s) => CATALOG[s]?.kind === "charging") && num(v.current_soc, 100) < num(v.target_soc, 90));

    const chargeStalls = freeStalls.filter((s: any) => s.stall_kind === "charging");
    const offeredCharge = [...chargeStalls.filter((s: any) => s.stall_type === "dcfc").slice(0, maxConcurrentDcfc), ...chargeStalls.filter((s: any) => s.stall_type === "l2")];
    let chargeAssign: Record<string, string> = {}; let chargeSource = "none";
    const apiKey = Deno.env.get("NVIDIA_API_KEY_CUOPT") ?? Deno.env.get("NVIDIA_API_KEY");
    if (chargeVehicles.length && offeredCharge.length && apiKey) {
      try { chargeAssign = await cuoptCharge(apiKey, chargeVehicles, offeredCharge); chargeSource = "cuopt"; }
      catch { for (const v of chargeVehicles) { const s = offeredCharge.find((x: any) => !Object.values(chargeAssign).includes(x.id) && chargeCompatible(v.inlet_type, x)); if (s) chargeAssign[v.id] = s.id; } chargeSource = "fallback"; }
    } else if (chargeVehicles.length && offeredCharge.length) { for (const v of chargeVehicles) { const s = offeredCharge.find((x: any) => !Object.values(chargeAssign).includes(x.id) && chargeCompatible(v.inlet_type, x)); if (s) chargeAssign[v.id] = s.id; } chargeSource = "fallback"; }

    const stallById: Record<string, any> = {}; for (const s of freeStalls) stallById[s.id] = s;
    const used = new Set<string>(Object.values(chargeAssign));
    const pool: Record<string, any[]> = {}; for (const s of freeStalls) (pool[s.stall_kind] = pool[s.stall_kind] || []).push(s);
    const poolFor = (kind: string) => (KIND_STALLS[kind] || []).flatMap((k) => (pool[k] || []).filter((s) => !used.has(s.id)));
    const board: any[] = []; let assignedTasks = 0; let unresourced = 0;
    for (const v of cands) {
      const steps = svcOf(v).map((s) => ({ service: s, cat: CATALOG[s] ?? { kind: "unknown", rank: 5, dur: 15 } })).sort((a, b) => a.cat.rank - b.cat.rank);
      let cursor = Date.now(); const coded: any[] = []; let seq = 0; const claimedBay: Record<string, string> = {};
      for (const step of steps) {
        seq++; let stall: any = null; let reused = false;
        if (step.cat.kind === "charging" && chargeAssign[v.id]) { stall = stallById[chargeAssign[v.id]]; reused = true; }
        else if (SHARED_BAY.has(step.cat.kind) && claimedBay[step.cat.kind]) { stall = stallById[claimedBay[step.cat.kind]]; reused = true; }
        else { const c = poolFor(step.cat.kind).sort((a, b) => num(a.distance_from_entrance) - num(b.distance_from_entrance)); stall = c[0] || null; }
        if (stall) { if (!reused) { used.add(stall.id); if (SHARED_BAY.has(step.cat.kind)) claimedBay[step.cat.kind] = stall.id; } assignedTasks++; } else unresourced++;
        const start = new Date(cursor); const end = new Date(cursor + step.cat.dur * 60000); if (stall) cursor = end.getTime() + 60000;
        coded.push({ seq, service: step.service, kind: step.cat.kind, stall: stall?.stall_code ?? null, stall_id: stall?.id ?? null, dur_min: step.cat.dur, status: stall ? "planned" : "awaiting_resource" });
      }
      board.push({ vehicle: v.display_name, vehicle_id: v.id, soc: v.current_soc, sequence: coded.map((c) => c.stall ? (c.service + " @ " + c.stall) : (c.service + " (awaiting)")).join(" -> "), tasks: coded });
    }

    const out: any = {
      depot: depot.name, tick_at: new Date().toISOString(),
      energy: { tariff: e.current_tariff_label, effective_cap_kw: Math.round(effectiveCap), dcfc_budget_kw: Math.round(dcfcBudgetKw), max_concurrent_dcfc: maxConcurrentDcfc, billing_peak_kw: billingPeak },
      stability: { in_progress_locked_stalls: lockedStalls.size },
      summary: { vehicles_planned: cands.length, charge_vehicles: chargeVehicles.length, charge_assigned: Object.keys(chargeAssign).length, charge_source: chargeSource, tasks_assigned: assignedTasks, tasks_awaiting_resource: unresourced, free_stalls: freeStalls.length },
      depot_board: board,
      note: "Depot-wide tick: cuOpt charge assignment + shared-pool sequencing, stability-biased; plan gated by the 52-rule shield + logged to ottoq_decisions via ottoq_shield_and_log.",
    };

    if (submit) {
      const { data: prun } = await sb.from("ottoq_sim_runs")
        .select("sim_run_id,tick_count").eq("run_by", "production_live").eq("status", "running")
        .order("started_at", { ascending: false }).limit(1).maybeSingle();
      if (!prun) { out.committed = { error: "no running production_live run — cannot shield/audit" }; return json(out); }
      const actions: any[] = [];
      for (const row of board) for (const t of row.tasks) {
        if (!t.stall_id) continue;
        actions.push({ vehicle_id: row.vehicle_id, action_context: t.kind === "charging" ? "stall_assignment" : "task_start",
          stall_id: t.stall_id, service: t.service, kind: t.kind, requested_kw: t.kind === "charging" ? DCFC_KW : 0 });
      }
      const { data: shieldRes, error: shErr } = await sb.rpc("ottoq_shield_and_log", {
        p_sim_run_id: prun.sim_run_id, p_tick_seq: prun.tick_count, p_depot_id: depot_id, p_actions: actions, p_shadow: shadow });
      out.committed = shErr ? { error: shErr.message } : { shadow_only: shadow, production_run: prun.sim_run_id, tick_seq: prun.tick_count, shield: shieldRes };
    }
    return json(out);
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});

