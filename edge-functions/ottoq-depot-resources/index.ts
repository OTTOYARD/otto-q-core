// ottoq-depot-resources — B-2 of the OrchestraAV->otto-q-core unification. The depot resource grid
// from the one brain (otto-q-core `stalls`): counts by kind + per-stall occupancy. Lets OrchestraAV's
// Depot view / floor plan render the SAME stalls/bays as OTTO-PULSE. Read-only.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const url = new URL(req.url);
    const depot_id = body.depot_id ?? url.searchParams.get("depot_id") ?? DEFAULT_DEPOT;
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

    const [{ data: depot }, { data: stalls }] = await Promise.all([
      sb.from("depots").select("id,name,city,state").eq("id", depot_id).maybeSingle(),
      sb.from("stalls").select("id,stall_code,display_name,stall_kind,stall_type,status,current_vehicle_id,connector_type,zone,covered,distance_from_entrance").eq("depot_id", depot_id).order("stall_code"),
    ]);
    if (!depot) return json({ error: "depot not found" }, 404);
    const list = stalls ?? [];

    const occIds = [...new Set(list.map((s: any) => s.current_vehicle_id).filter(Boolean))];
    const vmap: Record<string, string> = {};
    if (occIds.length) { const { data: vs } = await sb.from("vehicles").select("id,display_name").in("id", occIds); for (const v of (vs ?? [])) vmap[v.id] = v.display_name; }

    const kinds: Record<string, any> = {};
    for (const s of list) {
      const k = s.stall_kind ?? "other";
      const r = kinds[k] = kinds[k] || { kind: k, total: 0, available: 0, occupied: 0, other: 0 };
      r.total++;
      if (s.status === "available") r.available++;
      else if (s.status === "occupied" || s.current_vehicle_id) r.occupied++;
      else r.other++;
    }

    const resources = list.map((s: any) => ({
      id: s.id, stall_code: s.stall_code, name: s.display_name ?? s.stall_code,
      kind: s.stall_kind, type: s.stall_type, status: s.status,
      connector_type: s.connector_type, zone: s.zone, covered: s.covered,
      occupant_vehicle_id: s.current_vehicle_id ?? null, occupant: s.current_vehicle_id ? (vmap[s.current_vehicle_id] ?? null) : null,
    }));

    return json({
      depot: { id: depot.id, name: depot.name, city: depot.city, state: depot.state },
      summary: { total: list.length, by_kind: Object.values(kinds) },
      resources,
    });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
