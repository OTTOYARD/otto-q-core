// ottoq-progress — OTTO-Q technician-gated PROGRESSION authorizer.
// On a confirmed station: find the next task in the sequence and SHIELD-GATE authorizing
// the move (task_start/stall_assignment); if the chain is complete, run the deploy-readiness
// gate (SLA.001 min-SoC, SLA.004 services-complete, SLA.007, HW.003). Dry-run by default
// (probe + decision only); commit=true advances state atomically via ottoq_progress_commit.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
// Charge-related services — drives the explicit requires_charging flag fed to the shield so
// charge-only rules (HW.001 connector, HW.003 SoC-liveness) self-scope: full enforcement on
// charging steps, N/A on non-charging transitions. Belt-and-suspenders alongside service code.
const CHARGING_SERVICES = new Set(["charge", "dcfc_charge", "l2_charge", "charging", "fast_charge", "dc_fast_charge"]);
const isCharging = (svc: string) => CHARGING_SERVICES.has(String(svc ?? "").toLowerCase());
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const vehicle_id = body.vehicle_id;
    const commit = body.commit === true;
    const role = body.confirmed_by_role ?? "yard_supervisor";
    if (!vehicle_id) return json({ error: "vehicle_id required" }, 400);
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: veh } = await sb.from("vehicles").select("id,display_name,current_soc,target_soc,min_soc_threshold,current_state,home_depot_id").eq("id", vehicle_id).maybeSingle();
    if (!veh) return json({ error: "vehicle not found" }, 404);
    const depot_id = veh.home_depot_id ?? DEFAULT_DEPOT;
    const { data: scheds } = await sb.from("vehicle_schedules").select("id,status").eq("vehicle_id", vehicle_id).eq("status", "in_progress").order("created_at", { ascending: false }).limit(1);
    const schedule = scheds?.[0];
    if (!schedule) return json({ error: "no in-progress schedule for vehicle (run sequencer first)", vehicle: veh.display_name }, 404);
    const { data: tasks } = await sb.from("schedule_tasks").select("id,sequence_order,service_code,status,assigned_stall_id").eq("vehicle_schedule_id", schedule.id).order("sequence_order");
    const chain = tasks ?? [];
    const pending = chain.filter((t: any) => t.status !== "completed" && t.status !== "cancelled");
    const current = [...chain].reverse().find((t: any) => t.status === "completed" || t.status === "in_progress") ?? null;
    const next = pending.find((t: any) => t.status === "pending") ?? pending[0] ?? null;

    const probe = async (action: string, ctx: any) => {
      const { data } = await sb.rpc("ottoq_shield_probe", { p_action_context: action, p_entity_type: "vehicle", p_entity_id: vehicle_id, p_context: ctx, p_depot_id: depot_id });
      const rows = data ?? [];
      const blocked = rows.filter((r: any) => r.would_block).map((r: any) => ({ rule: r.rule_code, reason: r.reason }));
      return { authorized: blocked.length === 0, blocked, evaluated: rows.map((r: any) => ({ rule: r.rule_code, passed: r.passed })) };
    };

    let result: any;
    if (next) {
      // ---- authorize advance to next station ----
      const action = next.assigned_stall_id ? "stall_assignment" : "task_start";
      const sh = await probe(action, { vehicle_id, stall_id: next.assigned_stall_id, service: next.service_code, requires_charging: isCharging(next.service_code), sequence_order: next.sequence_order });
      result = { action: "advance", current_service: current?.service_code ?? null, next_service: next.service_code, next_stall_id: next.assigned_stall_id, sequence_from: current?.sequence_order ?? null, sequence_to: next.sequence_order, authorized: sh.authorized, blocked_by: sh.blocked, shield_evaluated: sh.evaluated };
      if (commit && sh.authorized) {
        // Atomic, optimistic-concurrency-guarded commit (one transaction; rolls back on any error).
        const { data: cr, error: cerr } = await sb.rpc("ottoq_progress_commit", {
          p_mode: "advance", p_vehicle_id: vehicle_id, p_schedule_id: schedule.id, p_depot_id: depot_id, p_role: role,
          p_current_task_id: current?.id ?? null, p_next_task_id: next.id,
          p_from_seq: current?.sequence_order ?? null, p_to_seq: next.sequence_order, p_to_stall_id: next.assigned_stall_id,
          p_audit_note: "shield-authorized advance",
        });
        result.committed = !cerr && cr?.committed === true;
        result.commit_result = cr ?? null;
        if (cerr) result.commit_error = cerr.message;
      }
    } else {
      // ---- chain complete -> deploy-readiness gate ----
      const sh = await probe("redeployment", { vehicle_id, current_soc: veh.current_soc, min_soc: veh.min_soc_threshold, target_soc: veh.target_soc, services_complete: true });
      result = { action: "deploy", all_services_complete: true, current_soc: veh.current_soc, authorized: sh.authorized, blocked_by: sh.blocked, shield_evaluated: sh.evaluated };
      if (commit && sh.authorized) {
        const { data: cr, error: cerr } = await sb.rpc("ottoq_progress_commit", {
          p_mode: "deploy", p_vehicle_id: vehicle_id, p_schedule_id: schedule.id, p_depot_id: depot_id, p_role: role,
          p_audit_note: "shield-authorized deploy (all services complete, readiness passed)",
        });
        result.committed = !cerr && cr?.committed === true;
        result.commit_result = cr ?? null;
        if (cerr) result.commit_error = cerr.message;
      }
    }
    return json({ vehicle: veh.display_name, vehicle_id, schedule_id: schedule.id, soc: veh.current_soc, chain: chain.map((t: any) => ({ seq: t.sequence_order, service: t.service_code, status: t.status })), decision: result, dry_run: !commit });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
