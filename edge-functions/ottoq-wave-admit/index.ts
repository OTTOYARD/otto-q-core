// ottoq-wave-admit — OTTO-Q ingress / wave-admission policy. Controls HOW MANY returning vehicles
// are admitted from the gate into the depot per tick, so the site/gate flow isn't overloaded.
//   DAYTIME (ad-hoc): vehicles trickle in when flagged (low SoC / cleaning / service) -> admit freely,
//                     bounded only by real capacity.
//   OVERNIGHT (turnover wave): most of the fleet returns ~together -> THROTTLE admission to a small
//                     per-tick ingress cap so we stage the wave instead of swamping the gate.
// Admission is bounded by: ingress cap (the throttle) AND real free capacity AND SLA.002 queue depth.
// Dry-run by default; commit=true admits (arrived_at_gate -> staged_awaiting_service). Real gate queue
// = vehicles in 'arrived_at_gate'. what_if_arrivals=N demonstrates the throttle on a hypothetical wave.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d: number) { const n = Number(x); return isFinite(n) ? n : d; }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    const commit = body.commit === true;
    const whatIf = Math.max(0, num(body.what_if_arrivals, 0));
    const onStart = num(body.overnight_start_hour, 20);
    const onEnd = num(body.overnight_end_hour, 6);
    const nightCap = num(body.night_ingress_per_tick, 6);
    const dayCap = num(body.day_ingress_per_tick, 999);
    const hour = body.now_hour !== undefined ? num(body.now_hour, 0) : new Date().getUTCHours();
    const overnight = onStart > onEnd ? (hour >= onStart || hour < onEnd) : (hour >= onStart && hour < onEnd);
    const mode = overnight ? "overnight_wave" : "daytime_adhoc";
    const ingressCap = overnight ? nightCap : dayCap;

    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: stalls } = await sb.from("stalls").select("stall_kind,status").eq("depot_id", depot_id);
    const free: Record<string, number> = {};
    for (const s of (stalls ?? [])) if (s.status === "available") free[s.stall_kind] = (free[s.stall_kind] ?? 0) + 1;
    const receiveCapacity = (free["staging"] ?? 0) + (free["charging"] ?? 0) + (free["service"] ?? 0) + (free["inspection"] ?? 0);

    const [{ data: depot }, { data: erows }] = await Promise.all([
      sb.from("depots").select("name,service_max_kw,dcfc_max_concurrent_kw,dcfc_safety_margin_pct").eq("id", depot_id).maybeSingle(),
      sb.from("site_energy_snapshots").select("building_load_kw,billing_period_peak_kw").eq("depot_id", depot_id).order("timestamp", { ascending: false }).limit(1),
    ]);
    const e = erows?.[0] ?? {};
    const serviceMax = num(depot?.service_max_kw, 2500), margin = num(depot?.dcfc_safety_margin_pct, 10) / 100;
    const effCap = Math.min(serviceMax * (1 - margin), num(e.billing_period_peak_kw, serviceMax * 0.6));
    const dcfcBudget = Math.max(0, Math.min(num(depot?.dcfc_max_concurrent_kw, effCap), effCap - num(e.building_load_kw, 0)));
    const maxConcurrentDcfc = Math.max(0, Math.floor(dcfcBudget / 150));

    const { data: gate } = await sb.from("vehicles")
      .select("id,display_name,current_soc,target_soc,home_depot_id")
      .eq("home_depot_id", depot_id).eq("current_state", "arrived_at_gate").order("current_soc", { ascending: true });
    const gateQueue = gate ?? [];
    const { count: inboundCount } = await sb.from("vehicles").select("id", { count: "exact", head: true })
      .eq("home_depot_id", depot_id).eq("current_state", "en_route_to_depot");

    const queueDepth = gateQueue.length + whatIf;
    const admitCount = Math.max(0, Math.min(ingressCap, receiveCapacity, queueDepth));
    const realAdmit = gateQueue.slice(0, Math.min(admitCount, gateQueue.length));
    const whatIfAdmit = Math.max(0, admitCount - realAdmit.length);

    let committed: any = null;
    if (commit && realAdmit.length) {
      const ids = realAdmit.map((v: any) => v.id);
      const { error } = await sb.from("vehicles").update({ current_state: "staged_awaiting_service" }).in("id", ids).eq("current_state", "arrived_at_gate");
      committed = { admitted_vehicle_ids: ids, error: error?.message ?? null };
    }

    return json({
      depot: depot?.name ?? depot_id,
      mode, now_hour: hour, overnight_window: `${onStart}:00-${onEnd}:00`,
      ingress_cap_per_tick: ingressCap,
      gate_queue: gateQueue.length, inbound_en_route: inboundCount ?? null,
      receive_capacity: { staging: free["staging"] ?? 0, charging: free["charging"] ?? 0, service: free["service"] ?? 0, inspection: free["inspection"] ?? 0, total: receiveCapacity },
      energy: { effective_cap_kw: Math.round(effCap), dcfc_budget_kw: Math.round(dcfcBudget), max_concurrent_dcfc: maxConcurrentDcfc },
      admit_now: admitCount, hold_in_queue: Math.max(0, queueDepth - admitCount),
      admitted_real: realAdmit.map((v: any) => ({ id: v.id, vehicle: v.display_name, soc: v.current_soc })),
      admitted_what_if: whatIf ? whatIfAdmit : undefined,
      reasoning: overnight
        ? `Overnight turnover: throttling ingress to ${ingressCap}/tick (capacity for ${receiveCapacity}); staging the wave to protect gate/site flow + the ${maxConcurrentDcfc}-DCFC energy cap.`
        : `Daytime: ad-hoc arrivals admitted up to real free capacity (${receiveCapacity}); no wave throttle needed.`,
      dry_run: !commit, committed,
    });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
