// ottoq-assign-optimize — OTTO-Q stall/charger ASSIGNMENT optimizer (NVIDIA cuOpt routing).
// Multi-objective cost: SoC urgency + DCFC-for-neediest preference + HW.001 connector/inlet
// compatibility (forbidden pairs = prohibitive cost). Respects the energy co-optimizer's DCFC
// concurrency cap (only offers as many DCFC stalls as the demand-peak budget allows). Heuristic
// fallback if cuOpt unavailable.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const CUOPT = "https://optimize.api.nvidia.com/v1/nvidia/cuopt";
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
const DCFC_KW = 150;
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d = 0) { const n = Number(x); return isFinite(n) ? n : d; }
function compatible(vehicleInlet: string, stall: any) {
  const sup = stall.supported_inlet_types; const list = Array.isArray(sup) ? sup : (sup ? [sup] : []);
  if (list.length && vehicleInlet) return list.map((x: any) => String(x).toUpperCase()).includes(String(vehicleInlet).toUpperCase());
  if (stall.connector_type && vehicleInlet) return String(stall.connector_type).toUpperCase() === String(vehicleInlet).toUpperCase();
  return true;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    const maxV = Math.min(num(body.max_vehicles, 20), 40);
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const [{ data: depot }, { data: energyRows }, { data: vehicles }, { data: stalls }] = await Promise.all([
      sb.from("depots").select("service_max_kw,dcfc_max_concurrent_kw,dcfc_safety_margin_pct").eq("id", depot_id).maybeSingle(),
      sb.from("site_energy_snapshots").select("building_load_kw,billing_period_peak_kw").eq("depot_id", depot_id).order("timestamp", { ascending: false }).limit(1),
      sb.from("vehicles").select("id,current_soc,inlet_type,inlet_max_kw,max_charge_rate_kw").eq("home_depot_id", depot_id).in("current_state", ["arrived_at_gate", "staged_awaiting_service"]).order("current_soc", { ascending: true }).limit(maxV),
      sb.from("stalls").select("id,stall_code,stall_type,connector_type,connector_max_kw,supported_inlet_types").eq("depot_id", depot_id).eq("status", "available").in("stall_type", ["dcfc", "l2"]).limit(80),
    ]);
    if (!depot) return json({ error: "depot not found" }, 404);
    const e = energyRows?.[0] ?? {};
    const cands = vehicles ?? [];
    let free = stalls ?? [];
    if (cands.length === 0 || free.length === 0) return json({ assignments: [], candidates: cands.length, stalls: free.length, source: "none" });
    const serviceMax = num(depot.service_max_kw, 2500);
    const margin = num(depot.dcfc_safety_margin_pct, 10) / 100;
    const billingPeak = num(e.billing_period_peak_kw, serviceMax * 0.6);
    const building = num(e.building_load_kw, 0);
    const effectiveCap = Math.min(serviceMax * (1 - margin), billingPeak);
    const dcfcBudgetKw = Math.max(0, Math.min(num(depot.dcfc_max_concurrent_kw, effectiveCap), effectiveCap - building));
    const maxConcurrentDcfc = Math.max(0, Math.floor(dcfcBudgetKw / DCFC_KW));
    const dcfcStalls = free.filter((s: any) => s.stall_type === "dcfc").slice(0, maxConcurrentDcfc);
    const l2Stalls = free.filter((s: any) => s.stall_type === "l2");
    free = [...dcfcStalls, ...l2Stalls];
    if (free.length === 0) return json({ assignments: [], candidates: cands.length, stalls: 0, source: "none", note: "no energy-permitted stalls" });
    const apiKey = Deno.env.get("NVIDIA_API_KEY_CUOPT") ?? Deno.env.get("NVIDIA_API_KEY");
    let assignments: any[] = []; let source = "cuopt_fallback"; let cuoptError: string | null = null;
    if (apiKey) {
      try { assignments = await cuoptAssign(apiKey, cands, free); source = "cuopt"; }
      catch (err) { cuoptError = err instanceof Error ? err.message : String(err); assignments = heuristic(cands, free); }
    } else { assignments = heuristic(cands, free); cuoptError = "no NVIDIA_API_KEY_CUOPT"; }
    return json({
      depot_id, source, cuopt_error: cuoptError,
      candidates: cands.length, offered_stalls: free.length,
      energy_link: { dcfc_concurrency_budget_kw: Math.round(dcfcBudgetKw), max_concurrent_dcfc: maxConcurrentDcfc, effective_cap_kw: Math.round(effectiveCap), billing_peak_kw: billingPeak },
      assignments,
      note: "Connector-compat (HW.001) enforced in cost; DCFC count bounded by the energy demand-peak budget. Proposals still pass the 52-rule shield at commit.",
    });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});

function heuristic(vehicles: any[], stalls: any[]) {
  const out: any[] = []; const used = new Set<number>();
  for (const v of vehicles) {
    let bi = -1;
    for (let j = 0; j < stalls.length; j++) {
      if (used.has(j) || !compatible(v.inlet_type, stalls[j])) continue;
      if (bi < 0 || (stalls[j].stall_type === "dcfc" && stalls[bi].stall_type !== "dcfc")) bi = j;
    }
    if (bi >= 0) { used.add(bi); out.push({ vehicle_id: v.id, stall_id: stalls[bi].id, stall_type: stalls[bi].stall_type, stall_code: stalls[bi].stall_code, soc: v.current_soc }); }
  }
  return out;
}

async function cuoptAssign(apiKey: string, vehicles: any[], stalls: any[]) {
  const n = vehicles.length, m = stalls.length, dim = n + m, BIG = 1000000;
  const cost = Array.from({ length: dim }, (_, i) =>
    Array.from({ length: dim }, (_, j) => {
      if (i === j) return 0;
      if (i < n && j >= n) {
        const v = vehicles[i], s = stalls[j - n];
        if (!compatible(v.inlet_type, s)) return BIG;
        const soc = num(v.current_soc, 100);
        let c = (100 - soc);
        c += (s.stall_type === "dcfc" ? 0 : 35);
        if (s.stall_type === "dcfc" && soc > 60) c += 60;
        return Math.round(c);
      }
      return 1;
    })
  );
  const payload = {
    action: "cuOpt_OptimizedRouting",
    data: {
      task_data: { task_locations: vehicles.map((_, i) => i), demand: [vehicles.map(() => 1)], task_time_windows: vehicles.map(() => [0, 86400]), service_times: vehicles.map(() => 1) },
      fleet_data: { vehicle_locations: stalls.map((_, i) => [n + i, n + i]), capacities: [stalls.map(() => 1)], vehicle_types: stalls.map(() => 0), vehicle_time_windows: stalls.map(() => [0, 86400]) },
      cost_matrix_data: { data: { "0": cost } },
      solver_config: { time_limit: 5 },
    },
  };
  const res = await fetch(CUOPT, { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey, Accept: "application/json" }, body: JSON.stringify(payload) });
  const rawText = await res.text();
  if (!res.ok) throw new Error("HTTP " + res.status + ": " + rawText.slice(0, 220));
  let result: any; try { result = JSON.parse(rawText); } catch { throw new Error("non-JSON: " + rawText.slice(0, 160)); }
  const out: any[] = [];
  const vd = result?.response?.solver_response?.vehicle_data;
  if (vd) for (const sIdx of Object.keys(vd)) {
    const route = vd[sIdx];
    if (route.task_id && route.task_id.length) for (const tid of route.task_id) {
      const v = vehicles[tid], s = stalls[parseInt(sIdx)];
      if (v && s) out.push({ vehicle_id: v.id, stall_id: s.id, stall_type: s.stall_type, stall_code: s.stall_code, soc: v.current_soc });
    }
  }
  if (out.length === 0) throw new Error("no assignments; topkeys=[" + Object.keys(result || {}).join(",") + "]");
  return out;
}
