// ottoq-run-blackbox v2 — downloadable FLIGHT RECORDER. Assembles the bundle in MANY fast
// queries (not one giant 25MB RPC that trips the API gateway's ~22s ceiling): a light
// metadata+code header RPC, then each run-scoped data table paginated separately, then
// streamed as a .json attachment. Chase drops it into Claude Code for a code-vs-behavior audit.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function fetchAll(makeQuery: () => any): Promise<any[]> {
  const out: any[] = []; let off = 0; const page = 1000;
  while (true) {
    const { data, error } = await makeQuery().range(off, off + page - 1);
    if (error) { out.push({ _export_error: error.message }); break; }
    if (!data || data.length === 0) break;
    out.push(...data);
    if (data.length < page) break;
    off += page;
    if (off > 500000) break; // hard safety cap
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const url = new URL(req.url);
    let run = url.searchParams.get("run");
    if (!run && req.method === "POST") { const b = await req.json().catch(() => ({})); run = b.run ?? b.sim_run_id ?? null; }
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    if (!run) {
      const { data: latest } = await sb.from("ottoq_sim_runs").select("sim_run_id")
        .eq("run_by", "operator_demo").order("started_at", { ascending: false }).limit(1).maybeSingle();
      run = latest?.sim_run_id ?? null;
      if (!run) return new Response(JSON.stringify({ error: "no run found" }), { status: 404, headers: { ...cors, "Content-Type": "application/json" } });
    }

    // 1) fast header: run metadata + exact executed code + the list of data tables
    const { data: meta, error: mErr } = await sb.rpc("ottoq_run_blackbox_meta", { p_sim_run_id: run });
    if (mErr || !meta) return new Response(JSON.stringify({ error: mErr?.message ?? "meta failed" }), { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
    const depot = meta.depot_id;
    const tables: string[] = Array.isArray(meta.data_tables) ? meta.data_tables : [];

    // 2) each run-scoped data table, paginated (fast, indexed on sim_run_id)
    const data: Record<string, unknown> = {};
    for (const t of tables) data[t] = await fetchAll(() => sb.from(t).select("*").eq("sim_run_id", run));

    // 3) depot-keyed state tables
    data["vehicles"] = await fetchAll(() => sb.from("vehicles").select("*").or(`owning_sim_run_id.eq.${run},current_depot_id.eq.${depot}`));
    data["stalls"] = await fetchAll(() => sb.from("stalls").select("*").eq("depot_id", depot));
    data["ocpp_sessions"] = await fetchAll(() => sb.from("ocpp_sessions").select("*").eq("depot_id", depot).gte("started_at", meta.run?.started_at ?? "1970-01-01"));

    const bundle = { ...meta, data };
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
    const fname = `ottoq-blackbox-${String(run).slice(0, 8)}-${stamp}.json`;
    return new Response(JSON.stringify(bundle), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json", "Content-Disposition": `attachment; filename="${fname}"` },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "unknown" }), { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
