// ottoq-sequence-optimize — OTTO-Q multi-service SEQUENCER (keystone).
// For a vehicle: order its services by precedence, assign each to a compatible available depot
// resource (connector/energy/capacity-aware), compute timing, and produce the CODED SEQUENCE.
// A vehicle's wash+detail share ONE cleaning bay; multiple maintenance services share ONE service
// bay (one visit, sequential). Every task gated through the 52-rule shield. Deterministic v1.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d = 0) { const n = Number(x); return isFinite(n) ? n : d; }

const CATALOG: Record<string, { kind: string; rank: number; dur: number; energy?: boolean }> = {
  charge: { kind: "charging", rank: 1, dur: 40, energy: true },
  dcfc_charge: { kind: "charging", rank: 1, dur: 25, energy: true },
  l2_charge: { kind: "charging", rank: 1, dur: 120, energy: true },
  inspection: { kind: "inspection", rank: 2, dur: 20 },
  maintenance: { kind: "service", rank: 2, dur: 45 },
  cabin_filter: { kind: "service", rank: 2, dur: 15 },
  tire_rotation: { kind: "service", rank: 2, dur: 25 },
  wiper_replace: { kind: "service", rank: 2, dur: 10 },
  exterior_wash: { kind: "wash", rank: 3, dur: 15 },
  wash: { kind: "wash", rank: 3, dur: 15 },
  interior_detail: { kind: "wash", rank: 4, dur: 30 },
  detail: { kind: "wash", rank: 4, dur: 30 },
  full_detail: { kind: "wash", rank: 4, dur: 60 },
  staging: { kind: "staging", rank: 8, dur: 5 },
  final_approval: { kind: "staging", rank: 9, dur: 5 },
};
// resource kind -> stall_kind values that satisfy it. 'wash' = the 3 COMBINED wash/detail bays;
// 'service' = the 2 service bays; inspection stays on its inspect-in-staging stalls (OQ-9).
const KIND_STALLS: Record<string, string[]> = {
  charging: ["charging"], inspection: ["inspection"], service: ["service"], wash: ["wash", "detail"], staging: ["staging"],
};
// A vehicle's multiple same-kind BAY tasks share ONE bay (one cleaning/service visit, sequential).
const SHARED_BAY = new Set(["wash", "service"]);

function compatible(vehicleInlet: string, stall: any) {
  if (stall.stall_kind !== "charging") return true;
  const sup = stall.supported_inlet_types; const list = Array.isArray(sup) ? sup : (sup ? [sup] : []);
  if (list.length && vehicleInlet) return list.map((x: any) => String(x).toUpperCase()).includes(String(vehicleInlet).toUpperCase());
  if (stall.connector_type && vehicleInlet) { const c = String(stall.connector_type).toUpperCase(); return c === "MULTI" || c === String(vehicleInlet).toUpperCase(); }
  return true;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    const vehicle_id = body.vehicle_id;
    const submit = body.submit === true;
    const shadow = body.shadow !== false;
    if (!vehicle_id) return json({ error: "vehicle_id required" }, 400);
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const [{ data: veh }, { data: sched }, { data: stalls }] = await Promise.all([
      sb.from("vehicles").select("id,display_name,current_soc,target_soc,inlet_type,inlet_max_kw,default_service_sequence,fleet_operator_id").eq("id", vehicle_id).maybeSingle(),
      sb.from("vehicle_schedules").select("id,planned_services,arrival_time,departure_time,priority").eq("vehicle_id", vehicle_id).order("created_at", { ascending: false }).limit(1),
      sb.from("stalls").select("id,stall_code,stall_type,stall_kind,status,connector_type,supported_inlet_types,distance_from_entrance").eq("depot_id", depot_id).eq("status", "available"),
    ]);
    if (!veh) return json({ error: "vehicle not found" }, 404);
    const schedule = sched?.[0] ?? null;

    let services: string[] = Array.isArray(body.services) ? body.services
      : (Array.isArray(schedule?.planned_services) ? schedule.planned_services
        : (Array.isArray(veh.default_service_sequence) ? veh.default_service_sequence : ["charge", "inspection", "staging"]));
    const steps = services.map((s: string) => ({ service: s, cat: CATALOG[s] ?? { kind: "unknown", rank: 5, dur: 15 } }))
      .sort((a, b) => a.cat.rank - b.cat.rank);

    const pool: Record<string, any[]> = {};
    for (const st of (stalls ?? [])) { (pool[st.stall_kind] = pool[st.stall_kind] || []).push(st); }
    const poolFor = (kind: string) => (KIND_STALLS[kind] || []).flatMap((k) => pool[k] || []);
    const stallById: Record<string, any> = {}; for (const st of (stalls ?? [])) stallById[st.id] = st;
    const claimedBay: Record<string, string> = {};

    const t0 = schedule?.arrival_time ? new Date(schedule.arrival_time) : new Date();
    let cursor = new Date(Math.max(t0.getTime(), Date.now()));
    const used = new Set<string>();
    const coded: any[] = [];
    let seq = 0;
    for (const step of steps) {
      seq++;
      let stall: any = null; let reused = false;
      if (SHARED_BAY.has(step.cat.kind) && claimedBay[step.cat.kind]) {
        stall = stallById[claimedBay[step.cat.kind]]; reused = true;   // reuse this vehicle's cleaning/service bay
      } else {
        const candidates = poolFor(step.cat.kind).filter((st) => !used.has(st.id) && compatible(veh.inlet_type, st));
        candidates.sort((a, b) => {
          if (step.cat.energy) { const ad = a.stall_type === "dcfc" ? 0 : 1, bd = b.stall_type === "dcfc" ? 0 : 1; if (ad !== bd) return num(veh.current_soc, 100) < 35 ? ad - bd : bd - ad; }
          return num(a.distance_from_entrance) - num(b.distance_from_entrance);
        });
        stall = candidates[0] || null;
      }
      const start = new Date(cursor); const end = new Date(cursor.getTime() + step.cat.dur * 60000);
      if (stall) { if (!reused) { used.add(stall.id); if (SHARED_BAY.has(step.cat.kind)) claimedBay[step.cat.kind] = stall.id; } cursor = new Date(end.getTime() + 60000); }
      coded.push({
        seq, service: step.service, resource_kind: step.cat.kind,
        stall_id: stall?.id ?? null, stall_code: stall?.stall_code ?? null, stall_type: stall?.stall_type ?? null,
        duration_min: step.cat.dur, scheduled_start: start.toISOString(), scheduled_end: stall ? end.toISOString() : null,
        status: stall ? "planned" : "awaiting_resource",
        note: stall ? null : ("no available '" + step.cat.kind + "' resource at depot"),
      });
    }

    const deadlineOk = schedule?.departure_time ? (cursor.getTime() <= new Date(schedule.departure_time).getTime()) : null;
    const codedString = coded.map((c) => c.stall_code ? (c.service + " @ " + c.stall_code) : (c.service + " (awaiting)")).join("  ->  ");

    const out: any = {
      vehicle: veh.display_name, vehicle_id, depot_id,
      soc: veh.current_soc, inlet: veh.inlet_type,
      arrival: schedule?.arrival_time ?? null, departure_deadline: schedule?.departure_time ?? null,
      deadline_feasible: deadlineOk,
      coded_sequence: coded, coded_sequence_string: codedString,
      unresourced: coded.filter((c) => c.status === "awaiting_resource").map((c) => c.service),
      note: "Sequencer v1. Wash+detail share one cleaning bay; maintenance shares one service bay (one visit). Kinds: charging/inspection/service(2)/wash(3 combined)/staging. Depot-wide cuOpt re-opt = orchestrate-tick.",
    };

    if (submit) {
      const recs: any[] = [];
      for (const c of coded) {
        if (!c.stall_id) continue;
        const { data: rid } = await sb.rpc("ottoq_emit_recommendation", {
          p_proposed_action: "stall_assignment", p_prediction_type: "service_duration_minutes",
          p_action_parameters: { vehicle_id, stall_id: c.stall_id, service: c.service, sequence_order: c.seq, requested_kw: c.resource_kind === "charging" ? (c.stall_type === "dcfc" ? 150 : 19) : 0, scheduled_start: c.scheduled_start },
          p_entity_type: "vehicle", p_entity_id: vehicle_id, p_depot_id: depot_id, p_shadow_only: shadow,
        });
        if (rid) recs.push({ seq: c.seq, service: c.service, stall: c.stall_code, recommendation_id: rid });
      }
      let statuses: any = null;
      const ids = recs.map((r) => r.recommendation_id);
      if (ids.length) { const { data } = await sb.from("ottoq_recommendations").select("recommendation_id,proposed_action,status,rules_blocked_by").in("recommendation_id", ids); statuses = data; }
      out.committed = { shadow_only: shadow, gated_tasks: recs, shield_results: statuses };
    }
    return json(out);
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
