// ottoq-amend — OTTO-Q amendment / re-queue handler (the "amend anytime -> OTTO-Q reshuffles").
// A tech/operator submits a change to a vehicle's in-depot plan; OTTO-Q applies it atomically
// (stability-biased: PENDING tasks only, never touches in_progress/completed), records the
// schedule_modifications audit, RE-QUEUES the depot via orchestrate-tick (optional), and ALWAYS
// returns the amended vehicle's fresh coded sequence. Dry-run by default; commit=true applies.
// Amendment types: service_add | service_remove | reorder | stall_reassignment | priority_change | departure_change.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const KNOWN = new Set(["service_add", "service_remove", "reorder", "stall_reassignment", "priority_change", "departure_change"]);
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
const codes = (chain: any[]) => chain.filter((t) => t.status !== "cancelled").map((t) => t.service_code);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const amendment = body.amendment ?? {};
    const type = String(amendment.type ?? "").toLowerCase();
    const commit = body.commit === true;
    const requeue = body.requeue !== false;
    const requested_by = body.requested_by ?? "yard_supervisor";
    const reason = body.reason ?? null;
    if (!KNOWN.has(type)) return json({ error: "amendment.type must be one of " + [...KNOWN].join(", ") }, 400);

    const url = Deno.env.get("SUPABASE_URL");
    const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const sb = createClient(url, svc);

    // ---- resolve schedule ----
    let schedule_id = body.schedule_id ?? null;
    let vehicle_id = body.vehicle_id ?? null;
    if (!schedule_id) {
      if (!vehicle_id) return json({ error: "vehicle_id or schedule_id required" }, 400);
      const { data: s } = await sb.from("vehicle_schedules").select("id").eq("vehicle_id", vehicle_id).eq("status", "in_progress").order("created_at", { ascending: false }).limit(1);
      schedule_id = s?.[0]?.id ?? null;
      if (!schedule_id) return json({ error: "no in-progress schedule for vehicle" }, 404);
    }
    const { data: sched } = await sb.from("vehicle_schedules").select("id,vehicle_id,depot_id,status,priority,departure_time").eq("id", schedule_id).maybeSingle();
    if (!sched) return json({ error: "schedule not found" }, 404);
    vehicle_id = sched.vehicle_id;
    const depot_id = sched.depot_id;
    const { data: veh } = await sb.from("vehicles").select("display_name").eq("id", vehicle_id).maybeSingle();
    const { data: tasks } = await sb.from("schedule_tasks").select("id,sequence_order,service_code,status,assigned_stall_id").eq("vehicle_schedule_id", schedule_id).order("sequence_order");
    const chain = tasks ?? [];
    const pending = chain.filter((t: any) => t.status === "pending");

    // ---- validate (no mutation) ----
    const errs: string[] = [];
    if (type === "service_add") {
      const code = String(amendment.service_code ?? "").toLowerCase();
      if (!code) errs.push("service_add requires service_code");
      else {
        const { data: sd } = await sb.from("service_definitions").select("id,code,estimated_duration_minutes,stall_type_required").eq("depot_id", depot_id).ilike("code", code).eq("is_active", true).limit(1);
        if (!sd?.length) errs.push('unknown/inactive service "' + code + '" at depot');
      }
    } else if (type === "service_remove") {
      const code = String(amendment.service_code ?? "").toLowerCase();
      const match = pending.find((t: any) => t.id === amendment.task_id || String(t.service_code).toLowerCase() === code);
      if (!match) errs.push("no PENDING task matches task_id/service_code (locked tasks cannot be removed)");
    } else if (type === "reorder") {
      if (!Array.isArray(amendment.order)) errs.push("reorder requires an order[] of service codes");
      else { const want = amendment.order.map((x: string) => String(x).toLowerCase()); const have = pending.map((t: any) => String(t.service_code).toLowerCase()); const missing = have.filter((c: string) => !want.includes(c)); if (missing.length) errs.push("order[] missing pending services: " + missing.join(", ")); }
    } else if (type === "stall_reassignment") {
      const code = String(amendment.service_code ?? "").toLowerCase();
      const match = pending.find((t: any) => t.id === amendment.task_id || String(t.service_code).toLowerCase() === code);
      if (!match) errs.push("no PENDING task matches task_id/service_code");
    } else if (type === "priority_change") {
      if (!amendment.priority) errs.push("priority_change requires priority");
    } else if (type === "departure_change") {
      if (!amendment.departure_time) errs.push("departure_change requires departure_time (ISO)");
    }
    if (errs.length) return json({ error: "validation failed", details: errs, schedule_id, vehicle: veh?.display_name }, 422);

    const base = { schedule_id, vehicle_id, vehicle: veh?.display_name, depot_id, amendment };
    if (!commit) {
      return json({ ...base, dry_run: true, valid: true, current_chain: chain.map((t: any) => ({ seq: t.sequence_order, service: t.service_code, status: t.status, stall: t.assigned_stall_id })), current_services: codes(chain), note: "preview only — set commit:true to apply atomically and re-queue the depot" });
    }

    // ---- commit: atomic structural amend + audit ----
    const { data: amend, error: aerr } = await sb.rpc("ottoq_amend_apply", { p_schedule_id: schedule_id, p_amendment: amendment, p_requested_by: requested_by, p_reason: reason });
    if (aerr) return json({ ...base, committed: false, error: aerr.message }, 422);

    const hdr = { "Authorization": "Bearer " + svc, "apikey": svc, "Content-Type": "application/json" };

    // ---- re-queue: depot-wide stability-biased re-opt + shield gate (optional) ----
    let requeue_result: any = { invoked: false };
    if (requeue) {
      try {
        const r = await fetch(url + "/functions/v1/ottoq-orchestrate-tick", { method: "POST", headers: hdr, body: JSON.stringify({ depot_id, submit: true }) });
        const tick = await r.json().catch(() => ({}));
        requeue_result = { invoked: true, ok: r.ok, energy: tick?.energy ?? null, summary: tick?.summary ?? null };
      } catch (e) { requeue_result = { invoked: true, ok: false, error: e instanceof Error ? e.message : "tick failed" }; }
    }

    // ---- ALWAYS: the amended vehicle's fresh coded sequence (the "sequence back to the vehicle") ----
    let new_coded_sequence: string | null = null, sequence_detail: any = null, deadline_feasible: any = null;
    try {
      const sr = await fetch(url + "/functions/v1/ottoq-sequence-optimize", { method: "POST", headers: hdr, body: JSON.stringify({ vehicle_id, depot_id, submit: false }) });
      const sj = await sr.json().catch(() => ({}));
      new_coded_sequence = sj?.coded_sequence_string ?? null;
      sequence_detail = sj?.coded_sequence ?? null;
      deadline_feasible = sj?.deadline_feasible ?? null;
    } catch (_e) { /* sequence preview best-effort */ }

    return json({ ...base, committed: true, amendment_result: amend, new_coded_sequence, deadline_feasible, sequence_detail, requeue: requeue_result });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
