// ottoq-cleaning-cadence — decide (and optionally apply) the cleaning a vehicle is DUE for.
// Interior detail = daily; exterior wash = weekly/bi-weekly. Derived from completed-task history via
// the ottoq_cleaning_due RPC. report (default) returns the determination for one vehicle or all
// home-depot vehicles; apply=true adds the due cleaning services to the vehicle's in-progress plan
// (via ottoq_amend_apply, skipping ones already present) so the sequencer slots them into ONE
// cleaning-bay visit. This is the intake-cadence rule the depot uses to build planned_services.
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
    const vehicle_id = body.vehicle_id ?? null;
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    const interiorHours = num(body.interior_hours, 24);
    const exteriorDays = num(body.exterior_days, 7);
    const apply = body.apply === true;
    const requested_by = body.requested_by ?? "cleaning_tech";
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const due = (vid: string) => sb.rpc("ottoq_cleaning_due", { p_vehicle_id: vid, p_interior_hours: interiorHours, p_exterior_days: exteriorDays });

    if (!vehicle_id) {
      const { data: vehs } = await sb.from("vehicles").select("id,display_name").eq("home_depot_id", depot_id).limit(num(body.limit, 25));
      const rows: any[] = [];
      for (const v of (vehs ?? [])) { const { data: d } = await due(v.id); rows.push({ vehicle: v.display_name, vehicle_id: v.id, interior_due: d?.interior_due, exterior_due: d?.exterior_due, recommended: d?.recommended_cleaning_services ?? [] }); }
      return json({ depot_id, interior_threshold_hours: interiorHours, exterior_threshold_days: exteriorDays, count: rows.length, vehicles: rows });
    }

    const { data: veh } = await sb.from("vehicles").select("display_name").eq("id", vehicle_id).maybeSingle();
    if (!veh) return json({ error: "vehicle not found" }, 404);
    const { data: d, error: derr } = await due(vehicle_id);
    if (derr) return json({ error: derr.message }, 500);
    const recommended: string[] = Array.isArray(d?.recommended_cleaning_services) ? d.recommended_cleaning_services : [];

    if (!apply) return json({ vehicle: veh.display_name, vehicle_id, determination: d, note: "report only — set apply:true to add the due cleaning services to the plan" });

    const { data: scheds } = await sb.from("vehicle_schedules").select("id").eq("vehicle_id", vehicle_id).eq("status", "in_progress").order("created_at", { ascending: false }).limit(1);
    const schedule_id = scheds?.[0]?.id ?? null;
    if (!schedule_id) return json({ vehicle: veh.display_name, vehicle_id, determination: d, applied: false, note: "no in-progress schedule to amend (cadence is a report here)" });
    const { data: tasks } = await sb.from("schedule_tasks").select("service_code,status").eq("vehicle_schedule_id", schedule_id);
    const present = new Set((tasks ?? []).filter((t: any) => t.status !== "cancelled").map((t: any) => String(t.service_code).toLowerCase()));

    const added: string[] = []; const skipped: string[] = []; const errors: any[] = [];
    for (const svc of recommended) {
      if (present.has(svc.toLowerCase())) { skipped.push(svc); continue; }
      const { error: aerr } = await sb.rpc("ottoq_amend_apply", { p_schedule_id: schedule_id, p_amendment: { type: "service_add", service_code: svc }, p_requested_by: requested_by, p_reason: "cleaning cadence: " + svc + " due" });
      if (aerr) errors.push({ service: svc, error: aerr.message }); else added.push(svc);
    }

    let coded_sequence: string | null = null;
    try {
      const url = Deno.env.get("SUPABASE_URL"); const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      const r = await fetch(url + "/functions/v1/ottoq-sequence-optimize", { method: "POST", headers: { "Authorization": "Bearer " + svc, "apikey": svc, "Content-Type": "application/json" }, body: JSON.stringify({ vehicle_id, depot_id, submit: false }) });
      const sj = await r.json().catch(() => ({})); coded_sequence = sj?.coded_sequence_string ?? null;
    } catch (_e) { /* best-effort */ }

    return json({ vehicle: veh.display_name, vehicle_id, determination: d, applied: true, added, skipped, errors, new_coded_sequence: coded_sequence });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
