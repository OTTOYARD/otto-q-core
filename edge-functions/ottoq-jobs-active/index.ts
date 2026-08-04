// ottoq-jobs-active — B-3 of the OrchestraAV->otto-q-core unification. Active service items from the
// frontier schedule model (vehicle_schedules + schedule_tasks) projected as "jobs", so OrchestraAV's
// fleet-context / activity views read the SAME in-flight work as OTTO-Q. Read-only.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
const ACTIVE = ["pending", "vehicle_en_route", "in_progress"];
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d: number) { const n = Number(x); return isFinite(n) ? n : d; }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const url = new URL(req.url);
    const depot_id = body.depot_id ?? url.searchParams.get("depot_id") ?? DEFAULT_DEPOT;
    const limit = Math.min(num(body.limit ?? url.searchParams.get("limit"), 200), 1000);
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: tasks, error } = await sb.from("schedule_tasks")
      .select("id,vehicle_schedule_id,vehicle_id,service_code,status,sequence_order,assigned_stall_id,scheduled_start,scheduled_end")
      .eq("depot_id", depot_id).in("status", ACTIVE).order("scheduled_start").limit(limit);
    if (error) return json({ error: error.message }, 500);
    const list = tasks ?? [];

    const vIds = [...new Set(list.map((t: any) => t.vehicle_id).filter(Boolean))];
    const sIds = [...new Set(list.map((t: any) => t.assigned_stall_id).filter(Boolean))];
    const vmap: Record<string, any> = {}, smap: Record<string, string> = {};
    if (vIds.length) { const { data } = await sb.from("vehicles").select("id,display_name,current_soc,make").in("id", vIds); for (const v of (data ?? [])) vmap[v.id] = v; }
    if (sIds.length) { const { data } = await sb.from("stalls").select("id,stall_code").in("id", sIds); for (const s of (data ?? [])) smap[s.id] = s.stall_code; }

    const jobs = list.map((t: any) => ({
      id: t.id, schedule_id: t.vehicle_schedule_id,
      vehicle_id: t.vehicle_id, vehicle: vmap[t.vehicle_id]?.display_name ?? null, oem: vmap[t.vehicle_id]?.make ?? null, soc: vmap[t.vehicle_id]?.current_soc ?? null,
      service: t.service_code, status: t.status, sequence_order: t.sequence_order,
      stall_id: t.assigned_stall_id, stall_code: t.assigned_stall_id ? (smap[t.assigned_stall_id] ?? null) : null,
      scheduled_start: t.scheduled_start, scheduled_end: t.scheduled_end,
    }));

    const byStatus: Record<string, number> = {}, byService: Record<string, number> = {};
    for (const j of jobs) { byStatus[j.status] = (byStatus[j.status] ?? 0) + 1; if (j.service) byService[j.service] = (byService[j.service] ?? 0) + 1; }

    return json({ depot_id, count: jobs.length, summary: { by_status: byStatus, by_service: byService }, jobs });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
