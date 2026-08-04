// ottoq-fleet-vehicles — B-1 of the OrchestraAV->otto-q-core unification. Read-only list of the
// SHARED fleet from the one brain (otto-q-core `vehicles`), so OrchestraAV's Fleet view shows the
// exact same vehicles as OTTO-PULSE. Filter by depot/city/operator. Identity bridge fields
// (display_name / vin / license_plate) included so the old sim-keyed UI can match rows.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d: number) { const n = Number(x); return isFinite(n) ? n : d; }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const url = new URL(req.url);
    const depot_id = body.depot_id ?? url.searchParams.get("depot_id") ?? null;
    const fleet_operator_id = body.fleet_operator_id ?? url.searchParams.get("fleet_operator_id") ?? null;
    const city = (body.city ?? url.searchParams.get("city") ?? "").toString().trim().toLowerCase();
    const limit = Math.min(num(body.limit ?? url.searchParams.get("limit"), 300), 1000);
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: depots } = await sb.from("depots").select("id,name,city,state");
    const dmap: Record<string, any> = {}; for (const d of (depots ?? [])) dmap[d.id] = d;

    let q = sb.from("vehicles").select("id,display_name,make,model,year,vin,license_plate,current_soc,target_soc,min_soc_threshold,current_state,home_depot_id,fleet_operator_id,inlet_type,platform,current_soc_updated_at").limit(limit);
    if (depot_id) q = q.eq("home_depot_id", depot_id);
    if (fleet_operator_id) q = q.eq("fleet_operator_id", fleet_operator_id);
    const { data: vehs, error } = await q.order("current_soc", { ascending: true });
    if (error) return json({ error: error.message }, 500);

    let rows = (vehs ?? []).map((v: any) => {
      const dep = dmap[v.home_depot_id] ?? {};
      return {
        id: v.id,
        display_name: v.display_name,
        oem: v.make,
        model: v.model, year: v.year,
        vin: v.vin, plate: v.license_plate,
        soc: v.current_soc, target_soc: v.target_soc, min_soc: v.min_soc_threshold,
        state: v.current_state,
        inlet_type: v.inlet_type, platform: v.platform,
        soc_updated_at: v.current_soc_updated_at,
        depot_id: v.home_depot_id, depot_name: dep.name ?? null,
        city: dep.city ?? null, state_region: dep.state ?? null,
        fleet_operator_id: v.fleet_operator_id,
      };
    });
    if (city) rows = rows.filter((r) => (r.city ?? "").toLowerCase() === city);

    const byDepot: Record<string, any> = {};
    for (const r of rows) { const k = r.depot_id ?? "none"; (byDepot[k] = byDepot[k] || { depot_id: r.depot_id, depot_name: r.depot_name, city: r.city, count: 0 }).count++; }

    return json({ count: rows.length, depots: Object.values(byDepot), vehicles: rows });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
