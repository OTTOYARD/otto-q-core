import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function refit(p: Record<string, unknown>) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/ottoq_twin_refit_distribution`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    body: JSON.stringify(p),
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`refit ${r.status}: ${txt}`);
  return JSON.parse(txt);
}

async function patchProfile(profileName: string, profileData: Record<string, number>, desc: string) {
  const r = await fetch(
    `${SUPABASE_URL}/rest/v1/ottoq_calibration_profiles?profile_name=eq.${profileName}`,
    { method: "PATCH",
      headers: { "Content-Type": "application/json", apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, Prefer: "return=representation" },
      body: JSON.stringify({ profile_data: profileData, description: desc, fitted_at: new Date().toISOString() }) },
  );
  const txt = await r.text();
  if (!r.ok) throw new Error(`patchProfile ${r.status}: ${txt}`);
  return JSON.parse(txt);
}

const isoHour = (d: Date) => d.toISOString().slice(0, 13);
const isoDay = (d: Date) => d.toISOString().slice(0, 10);

function centralHour(period: string): number | null {
  const iso = period.length === 13 ? `${period}:00:00Z` : `${period}Z`;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  const h = Number(new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", hour: "2-digit", hour12: false }).format(d)) % 24;
  return isNaN(h) ? null : h;
}

async function ingestEia(key: string) {
  if (!key) throw new Error("missing eia_key");
  const end = new Date();
  const start = new Date(end); start.setDate(end.getDate() - 366);
  const values: number[] = [];
  const sums = new Array(24).fill(0);
  const counts = new Array(24).fill(0);
  let offset = 0;
  for (let page = 0; page < 3; page++) {
    const url = `https://api.eia.gov/v2/electricity/rto/region-data/data/?api_key=${key}`
      + `&frequency=hourly&data[0]=value&facets[respondent][]=TVA&facets[type][]=D`
      + `&start=${isoHour(start)}&end=${isoHour(end)}`
      + `&sort[0][column]=period&sort[0][direction]=desc&offset=${offset}&length=5000`;
    const r = await fetch(url);
    const j = await r.json();
    if (j?.error || j?.response == null) throw new Error(`EIA: ${JSON.stringify(j).slice(0, 300)}`);
    const rows = j.response.data ?? [];
    for (const x of rows) {
      const v = Number(x.value);
      if (isNaN(v)) continue;
      values.push(v);
      if (v >= 1000 && v <= 60000) {
        const h = centralHour(String(x.period));
        if (h != null) { sums[h] += v; counts[h] += 1; }
      }
    }
    offset += rows.length;
    if (rows.length < 5000) break;
  }
  const res = await refit({ p_dataset: "eia_grid", p_variable: "grid_demand_mw", p_segment: "global",
    p_values: values, p_units: "MW", p_clip_min: 1000, p_clip_max: 60000,
    p_src_start: isoDay(start), p_src_end: isoDay(end) });
  const totSum = sums.reduce((a, b) => a + b, 0);
  const totCnt = counts.reduce((a, b) => a + b, 0);
  const mean = totCnt ? totSum / totCnt : 1;
  const shape: Record<string, number> = {};
  for (let h = 0; h < 24; h++) shape[String(h)] = counts[h] && mean ? Number(((sums[h] / counts[h]) / mean).toFixed(4)) : 1.0;
  let shapeRes: unknown = null;
  if (totCnt > 0) shapeRes = await patchProfile("hourly_grid_demand_shape", shape,
    "TVA balancing-authority grid demand by hour-of-day (Central), real EIA hourly data, normalized to mean 1.0. Drives tariff-window + peak-demand timing.");
  return { source: "eia", fetched: values.length, refit: res, shape, shape_patched: shapeRes != null };
}

async function ingestNoaa(token: string) {
  if (!token) throw new Error("missing noaa_token");
  const end = new Date();
  const start = new Date(end); start.setDate(end.getDate() - 365);
  const url = `https://www.ncdc.noaa.gov/cdo-web/api/v2/data?datasetid=GHCND`
    + `&stationid=GHCND:USW00013897&datatypeid=TMAX&datatypeid=TMIN`
    + `&startdate=${isoDay(start)}&enddate=${isoDay(end)}&units=metric&limit=1000`;
  const r = await fetch(url, { headers: { token } });
  const j = await r.json();
  const rows = j?.results ?? [];
  if (!rows.length) throw new Error(`NOAA: ${JSON.stringify(j).slice(0, 300)}`);
  const values = rows.map((x: any) => Number(x.value)).filter((v: number) => !isNaN(v));
  const res = await refit({ p_dataset: "noaa_nws", p_variable: "ambient_temp_c", p_segment: "global",
    p_values: values, p_units: "C", p_clip_min: -50, p_clip_max: 60,
    p_src_start: isoDay(start), p_src_end: isoDay(end) });

  // precipitation — separate request (PRCP in mm with units=metric); enables wet-day couplings
  let precip_fetched = 0; let precip_refit: unknown = null;
  try {
    const purl = `https://www.ncdc.noaa.gov/cdo-web/api/v2/data?datasetid=GHCND`
      + `&stationid=GHCND:USW00013897&datatypeid=PRCP`
      + `&startdate=${isoDay(start)}&enddate=${isoDay(end)}&units=metric&limit=1000`;
    const pr = await fetch(purl, { headers: { token } });
    const pj = await pr.json();
    const prows = pj?.results ?? [];
    precip_fetched = prows.length;
    if (prows.length) {
      const pvals = prows.map((x: any) => Number(x.value)).filter((v: number) => !isNaN(v) && v >= 0);
      precip_refit = await refit({ p_dataset: "noaa_nws", p_variable: "precip_mm", p_segment: "global",
        p_values: pvals, p_units: "mm", p_clip_min: 0, p_clip_max: 200,
        p_src_start: isoDay(start), p_src_end: isoDay(end) });
    }
  } catch (e) { precip_refit = { error: String(e) }; }

  return { source: "noaa", fetched: values.length, refit: res, precip_fetched, precip_refit };
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const source = body.source ?? "eia";
    let out;
    if (source === "eia") out = await ingestEia(body.eia_key);
    else if (source === "noaa") out = await ingestNoaa(body.noaa_token);
    else throw new Error(`unknown source ${source}`);
    return new Response(JSON.stringify({ ok: true, ...out }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
