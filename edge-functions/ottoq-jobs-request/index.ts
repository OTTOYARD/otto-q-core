// ottoq-jobs-request — OTTO-Q owner/fleet REQUEST entry point (the 'ideal plan' side).
// An asset owner / fleet manager (OrchestraAV) requests that a vehicle receive service(s) at a
// depot. This CREATES the plan: ensures a vehicle_schedule + inserts the requested service tasks
// (pending) + (optionally) dispatches the vehicle inbound + returns OTTO-Q's coded sequence.
// Stall assignment + execution happen later: on arrival, ottoq-wave-admit throttles ingress and
// ottoq-orchestrate-tick assigns resources; the technician (OTTO-PULSE) confirms/executes (final say).
// Special case: job_type STAGING/HOLD (or relocate=true) = a recall/relocate request with no service.
// dry_run=true returns the plan WITHOUT writing (UI preview + safe testing).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
function json(o: any, s = 200) { return new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); }

// coarse owner-facing job types -> representative service code(s). The owner requests at a high
// level; OTTO-Q + the technician resolve the exact work. Explicit service_codes[] overrides.
const JOB_TYPE_CODES: Record<string, string[]> = {
  CHARGE: ["dcfc_charge"], CHARGING: ["dcfc_charge"], CHARGE_STALL: ["dcfc_charge"],
  MAINTENANCE: ["inspection"], SERVICE: ["inspection"], INSPECTION: ["inspection"], MAINTENANCE_BAY: ["inspection"],
  DETAILING: ["full_detail"], DETAIL: ["full_detail"], CLEAN_DETAIL_STALL: ["full_detail"],
  WASH: ["exterior_wash"],
};
const RELOCATE_TYPES = ["STAGING", "STAGE", "HOLD", "RELOCATE", "PARK", "STAGING_STALL"];

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const vehicleId = body.vehicle_id;
    if (!vehicleId) return json({ error: "vehicle_id required" }, 422);
    const dryRun = body.dry_run === true;
    const commit = body.commit !== false;       // default true (sets dispatch intent)
    const requeue = body.requeue === true;       // default false (assignment happens on arrival)
    const priority = ["standard", "priority", "vip"].includes(body.priority) ? body.priority : "standard";
    const jt = String(body.job_type || "").toUpperCase();

    const URL = Deno.env.get("SUPABASE_URL")!;
    const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(URL, SRK);

    const { data: veh, error: vErr } = await sb.from("vehicles")
      .select("id, display_name, current_state, home_depot_id, current_soc, target_soc")
      .eq("id", vehicleId).maybeSingle();
    if (vErr) return json({ error: "vehicle lookup failed", details: vErr.message }, 500);
    if (!veh) return json({ error: "vehicle not found", vehicle_id: vehicleId }, 404);

    const depotId = body.preferred_depot_id || veh.home_depot_id || DEFAULT_DEPOT;

    let codes: string[] = Array.isArray(body.service_codes) && body.service_codes.length
      ? body.service_codes.map((c: any) => String(c))
      : (JOB_TYPE_CODES[jt] || []);
    codes = Array.from(new Set(codes));
    const isRelocate = codes.length === 0 && (RELOCATE_TYPES.includes(jt) || body.relocate === true);
    if (!codes.length && !isRelocate) return json({ error: "no service requested", hint: "pass job_type (CHARGE|MAINTENANCE|DETAILING|WASH|STAGING) or service_codes[]" }, 422);
    const serviceLabel = codes.length ? codes.join(", ") : "staging/hold";

    const defByCode: Record<string, any> = {};
    if (codes.length) {
      const { data: defs, error: dErr } = await sb.from("service_definitions")
        .select("id, code, estimated_duration_minutes, default_sequence_order")
        .eq("depot_id", depotId).in("code", codes);
      if (dErr) return json({ error: "service catalog lookup failed", details: dErr.message }, 500);
      for (const d of (defs || [])) defByCode[d.code] = d;
      const unknown = codes.filter((c) => !defByCode[c]);
      if (unknown.length) return json({ error: "unknown service code(s) for this depot", unknown, depot_id: depotId }, 422);
    }

    const nowIso = new Date().toISOString();
    const startIso = typeof body.earliest_start_at === "string" ? body.earliest_start_at : nowIso;
    const schedDate = startIso.slice(0, 10);

    const { data: openSched } = await sb.from("vehicle_schedules")
      .select("id, planned_services, modification_count, status")
      .eq("vehicle_id", vehicleId).eq("depot_id", depotId)
      .in("status", ["draft", "confirmed", "modified"])
      .order("created_at", { ascending: false }).limit(1).maybeSingle();

    let already = new Set<string>();
    if (openSched) {
      const { data: ex } = await sb.from("schedule_tasks")
        .select("service_code, status").eq("vehicle_schedule_id", openSched.id)
        .in("status", ["pending", "vehicle_en_route", "in_progress"]);
      already = new Set((ex || []).map((t: any) => t.service_code));
    }
    const toAdd = codes.filter((c) => !already.has(c));
    const willDispatch = commit && ["deployed", "offline", "en_route_to_deployment"].includes(veh.current_state);

    if (dryRun) {
      return json({
        dry_run: true, relocate: isRelocate, vehicle: { id: veh.id, name: veh.display_name, state: veh.current_state, soc: veh.current_soc },
        depot_id: depotId, existing_schedule: openSched?.id ?? null, would_create_schedule: !openSched,
        services_requested: codes, would_add: toAdd, already_present: codes.filter((c) => already.has(c)), would_dispatch: willDispatch,
        message: `Preview: would ${codes.length ? "request " + serviceLabel : "queue for staging/hold"} for ${veh.display_name}` + (willDispatch ? " and dispatch it inbound." : "."),
      });
    }

    let scheduleId: string; let createdSchedule = false;
    if (openSched) { scheduleId = openSched.id; }
    else {
      const { data: ns, error: nsErr } = await sb.from("vehicle_schedules").insert({
        vehicle_id: vehicleId, depot_id: depotId, scheduled_date: schedDate,
        arrival_time: startIso, priority, status: "draft", planned_services: codes,
      }).select("id").single();
      if (nsErr || !ns) return json({ error: "could not create schedule", details: nsErr?.message }, 500);
      scheduleId = ns.id; createdSchedule = true;
    }

    let added: any[] = [];
    if (toAdd.length) {
      const rows = toAdd.map((c) => {
        const d = defByCode[c]; const mins = d.estimated_duration_minutes || 30;
        const end = new Date(new Date(startIso).getTime() + mins * 60000).toISOString();
        return {
          vehicle_schedule_id: scheduleId, schedule_id: scheduleId, vehicle_id: vehicleId, depot_id: depotId,
          service_definition_id: d.id, service_code: c, sequence_order: d.default_sequence_order ?? 50,
          scheduled_start: startIso, scheduled_end: end, status: "pending",
          target_soc: c.indexOf("charge") >= 0 ? (veh.target_soc ?? 80) : null,
          notes: "requested via OrchestraAV (owner)",
        };
      });
      const { data: ins, error: iErr } = await sb.from("schedule_tasks").insert(rows).select("id, service_code, sequence_order");
      if (iErr) return json({ error: "could not add service tasks", details: iErr.message }, 500);
      added = ins || [];
      const merged = Array.from(new Set([...((openSched?.planned_services as string[]) || []), ...codes]));
      await sb.from("vehicle_schedules").update({
        planned_services: merged, modification_count: (openSched?.modification_count ?? 0) + 1,
        status: createdSchedule ? "draft" : "modified", updated_at: nowIso,
      }).eq("id", scheduleId);
    }

    let dispatched = false;
    if (willDispatch) {
      const { error: upErr } = await sb.from("vehicles")
        .update({ current_state: "en_route_to_depot" })
        .eq("id", vehicleId).eq("current_state", veh.current_state);
      dispatched = !upErr;
    }

    let coded: any = null;
    try {
      const r = await fetch(`${URL}/functions/v1/ottoq-sequence-optimize`, {
        method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${SRK}`, apikey: SRK },
        body: JSON.stringify({ vehicle_id: vehicleId, schedule_id: scheduleId, depot_id: depotId }),
      });
      if (r.ok) coded = await r.json();
    } catch (_) { /* tasks already created; sequence advisory */ }

    let requeueRes: any = null;
    if (requeue) {
      try {
        const r = await fetch(`${URL}/functions/v1/ottoq-orchestrate-tick`, {
          method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${SRK}`, apikey: SRK },
          body: JSON.stringify({ depot_id: depotId, submit: true }),
        });
        requeueRes = { invoked: true, ok: r.ok };
      } catch (_) { requeueRes = { invoked: true, ok: false }; }
    }

    return json({
      ok: true, relocate: isRelocate,
      vehicle: { id: veh.id, name: veh.display_name, previous_state: veh.current_state, dispatched, new_state: dispatched ? "en_route_to_depot" : veh.current_state },
      depot_id: depotId, schedule_id: scheduleId, schedule_created: createdSchedule,
      services_requested: codes, tasks_added: added.map((a) => a.service_code),
      tasks_skipped_existing: codes.filter((c) => already.has(c)),
      coded_sequence: coded?.coded_sequence ?? coded?.new_coded_sequence ?? null,
      deadline_feasible: coded?.deadline_feasible ?? null,
      sequence: coded?.sequence ?? coded?.chain ?? coded?.new_chain ?? null,
      requeue: requeueRes,
      message: (isRelocate
        ? `Queued ${veh.display_name} for staging/hold`
        : `Requested ${serviceLabel} for ${veh.display_name}`) + (dispatched ? "; dispatched inbound. OTTO-Q assigns resources on arrival; technician confirms at the depot." : ". OTTO-Q sequences it and the technician confirms at the depot."),
    });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
