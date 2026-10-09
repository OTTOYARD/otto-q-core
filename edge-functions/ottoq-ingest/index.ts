// ottoq-ingest — OTTO-Q EXTERNAL real-fidelity ingestion seam (the twin/real-world door).
// Streams mirror REAL protocols so a real source plugs in with payload shapes unchanged:
//   energy ~ grid/site meter; telemetry ~ OEM telematics; ocpp ~ OCPP 2.0.1; arrival ~ OEM return
//   webhook; incident ~ AV disengagement/fault. Writes the SAME canonical tables the twin writes.
// data_source tags provenance on EVERY stream: real feed -> 'production', internal twin -> 'twin'.
//
// v9: energy+telemetry stamp sim_run_id (resolved from the depot's live run); energy stores
// lmp/carbon in real columns; incident maps arbitrary OEM types onto the exception_type enum
// (fallback 'other', raw type preserved) + guards severity; vehicle/charger resolution parameterized.
// v10 (otto-q-core 0649, G393): the depot and the data source come from the CREDENTIAL, never the body.
//   - A source key (X-OTTO-Q-API-Key, issued by ottoq_issue_source_key) binds depot, data source, source name and
//     the streams it may send; the door hashes it and asks ottoq_source_key_check. A body naming another depot or
//     data source is refused, not overridden.
//   - The platform (the injected service key itself, in apikey or as the Bearer; compared in constant time, as
//     ottoq-cpsat-propose does) may name both, and must name the depot; an unknown data source is refused, never
//     stored as production.
//   - Deployed with verify_jwt OFF, on purpose: the gateway now refuses legacy JWT keys (UNAUTHORIZED_LEGACY_JWT,
//     measured 2026-10-09), so with it on, an outside source holding only its source key could never reach this code.
//     Every check is here instead, before the first read.
//   - Anything else, the public key included, is refused before a single row is read or written.
//   - A vehicle or charger is looked up only at that depot. One elsewhere reads "not found", exactly like one that
//     does not exist, so a key can neither write to another depot's car nor learn that it exists.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-otto-q-api-key" };
const DATA_SOURCES = ["production", "twin", "replay", "shadow"];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VEHICLE_STATES = new Set(["offline","deployed","en_route_to_depot","arrived_at_gate","staged_awaiting_service","charging_dcfc","charging_l2","charge_complete_holding","in_wash_bay","in_detail_bay","in_service_bay","service_complete_holding","staged_for_departure","en_route_to_deployment","emergency_staged","tow_requested","out_of_service"]);
const TARIFFS = new Set(["off_peak","mid_peak","on_peak"]);
const OCPP_STATES = ["Available","Occupied","Reserved","Unavailable","Faulted"];
const OCPP_DIR = ["cs_to_csms", "csms_to_cs"];
const VEH_COLS = "id,current_state,current_soc,fleet_operator_id,home_depot_id,current_depot_id";
const EXC_TYPES = new Set(["vehicle_damage","vehicle_malfunction","sensor_anomaly","tire_issue","excessive_contamination","charger_fault","wash_system_fault","service_bay_fault","vehicle_unresponsive","schedule_conflict","unauthorized_movement","safety_concern","other"]);
const EXC_SEV = new Set(["low","medium","high","critical"]);
function json(o: any, s = 200) { return new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } }); }
function n(x: any): number | null { const v = Number(x); return isFinite(v) ? v : null; }

// Resolve a vehicle by UUID, display_name, or VIN, AT THE CREDENTIAL'S DEPOT ONLY (v10). Natural-key lookups use
// PARAMETERIZED .eq queries — never a string-built .or() filter — so a crafted vehicle_ref cannot inject into the filter.
async function resolveVehicle(sb: any, ref: any, depotId: string) {
  if (ref == null) return null;
  const r = String(ref);
  const atDepot = (v: any) => !!v && (v.current_depot_id === depotId || v.home_depot_id === depotId);
  if (UUID_RE.test(r)) {
    const { data } = await sb.from("vehicles").select(VEH_COLS).eq("id", r).limit(1).maybeSingle();
    return atDepot(data) ? data : null;
  }
  for (const col of ["display_name", "vin"]) {
    const { data } = await sb.from("vehicles").select(VEH_COLS).eq(col, r).limit(20);
    const hit = (data ?? []).find(atDepot);
    if (hit) return hit;
  }
  return null;
}
async function resolveCharger(sb: any, ref: any, depotId: string) {
  if (ref == null) return null;
  const r = String(ref);
  const q = sb.from("ottoq_ocpp_chargers").select("charger_id").eq("depot_id", depotId);
  const { data } = await (UUID_RE.test(r) ? q.eq("charger_id", r) : q.eq("ocpp_identifier", r)).limit(1).maybeSingle();
  return data?.charger_id ?? null;
}
// Resolve the depot's live orchestration run so run-scoped consumers see externally-ingested rows.
async function resolveRunId(sb: any, depotId: string): Promise<string | null> {
  const { data } = await sb.from("ottoq_sim_runs").select("sim_run_id,run_by")
    .eq("depot_id", depotId).eq("status", "running").order("started_at", { ascending: false }).limit(5);
  if (!data || !data.length) return null;
  const prod = data.find((r: any) => r.run_by === "production_live");
  return (prod ?? data[0]).sim_run_id;
}
async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length || x.length === 0) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}
// The platform is whoever holds the injected service key: in apikey (the new sb_secret_ keys are sent there alone)
// or as the Bearer (the legacy service_role JWT).
function isPlatform(req: Request): boolean {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const bearer = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  return sameSecret(req.headers.get("apikey") ?? "", key) || sameSecret(bearer, key);
}
async function brainSignal(sb: any, vehicleId: string, soc: number | null, etaMin: number | null, source: string) {
  try {
    const { data, error } = await sb.rpc("ottoq_ingest_vehicle_signal", {
      p_vehicle_id: vehicleId, p_soc_pct: soc, p_eta_min: etaMin, p_source: source });
    if (error) return { evaluated: false, reason: "rpc_error", error: error.message };
    return data ?? null;
  } catch (e) { return { evaluated: false, reason: "rpc_exception", error: e instanceof Error ? e.message : "unknown" }; }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const stream = String(body.stream || "").toLowerCase();
    const dryRun = body.dry_run === true;
    if (!stream) return json({ error: "stream required (energy|telemetry|ocpp|arrival|incident)" }, 422);

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // ── the credential decides the depot and the data source (v10) ──
    let depot_id: string; let DS: string; let source: string; let credential: any;
    const sourceKey = req.headers.get("x-otto-q-api-key");
    if (sourceKey) {
      const { data: cred, error: cErr } = await sb.rpc("ottoq_source_key_check", { p_key_hash: await sha256Hex(sourceKey), p_stream: stream });
      if (cErr) return json({ error: "credential check failed", detail: cErr.message }, 500);
      if (!cred?.ok) return json({ error: "source key refused", reason: cred?.reason ?? "unknown" }, cred?.reason === "stream_not_allowed" ? 403 : 401);
      if (body.depot_id && body.depot_id !== cred.depot_id) return json({ error: "depot_id comes from the source key, and this body names another depot" }, 403);
      if (DATA_SOURCES.includes(String(body.source)) && body.source !== cred.data_source) return json({ error: "data_source comes from the source key, and this body names another" }, 403);
      depot_id = cred.depot_id; DS = cred.data_source; source = cred.source_name;
      credential = { kind: "source_key", key_prefix: cred.key_prefix, source_name: cred.source_name };
    } else if (isPlatform(req)) {
      if (!body.depot_id || !UUID_RE.test(String(body.depot_id))) return json({ error: "the platform must name depot_id" }, 422);
      if (!DATA_SOURCES.includes(String(body.source))) return json({ error: "source must be one of " + DATA_SOURCES.join("|") + "; an unknown source is never stored as production" }, 422);
      depot_id = String(body.depot_id); DS = String(body.source); source = DS;
      credential = { kind: "platform" };
    } else {
      return json({ error: "ottoq-ingest needs a source key (X-OTTO-Q-API-Key) or the platform credential; the public key is neither" }, 401);
    }

    let events: any[] = Array.isArray(body.events) ? body.events : null;
    if (!events) { const { stream: _s, source: _src, depot_id: _d, events: _e, dry_run: _dr, ...one } = body; events = Object.keys(one).length ? [one] : []; }
    if (!events.length) return json({ error: "no events" }, 422);

    const now = new Date().toISOString();
    const runId = await resolveRunId(sb, depot_id);  // may be null when the depot is idle
    const results: any[] = []; let ok = 0;

    for (const ev of events) {
      try {
        if (stream === "energy") {
          const row: any = { depot_id, timestamp: now, sim_run_id: runId, data_source: DS,
            grid_import_kw: n(ev.grid_import_kw), grid_export_kw: n(ev.grid_export_kw),
            solar_generation_kw: n(ev.solar_generation_kw ?? ev.solar_kw), bess_output_kw: n(ev.bess_output_kw),
            total_ev_charging_kw: n(ev.total_ev_charging_kw ?? ev.ev_charging_kw),
            building_load_kw: n(ev.building_load_kw ?? ev.building_kw),
            peak_demand_kw_15min: n(ev.peak_demand_kw_15min), billing_period_peak_kw: n(ev.billing_period_peak_kw),
            current_rate_per_kwh: n(ev.current_rate_per_kwh ?? ev.rate_per_kwh),
            lmp_usd_mwh: n(ev.lmp_usd_mwh), carbon_gco2_kwh: n(ev.carbon_gco2_kwh) };
          if (ev.tariff_label && TARIFFS.has(String(ev.tariff_label))) row.current_tariff_label = String(ev.tariff_label);
          for (const k of Object.keys(row)) if (row[k] === null) delete row[k];
          if (dryRun) { results.push({ stream, would_write: "site_energy_snapshots", row }); ok++; continue; }
          const { error } = await sb.from("site_energy_snapshots").insert(row);
          if (error) { results.push({ stream, error: error.message }); continue; }
          results.push({ stream, wrote: "site_energy_snapshots", sim_run_id: runId, stored_lmp: n(ev.lmp_usd_mwh), stored_carbon: n(ev.carbon_gco2_kwh) }); ok++;
        } else if (stream === "telemetry") {
          const veh = await resolveVehicle(sb, ev.vehicle_ref ?? ev.vehicle_id ?? ev.vin, depot_id);
          if (!veh) { results.push({ stream, error: "vehicle not found", ref: ev.vehicle_ref ?? ev.vehicle_id }); continue; }
          const soc = n(ev.soc ?? ev.soc_pct);
          const st = ev.state && VEHICLE_STATES.has(String(ev.state)) ? String(ev.state) : null;
          const pkt: any = { vehicle_id: veh.id, fleet_operator_id: veh.fleet_operator_id, sim_run_id: runId, packet_at: now,
            soc_pct: soc, soc_source: source, battery_temp_c: n(ev.battery_temp_c), speed_kmh: n(ev.speed_kmh),
            current_lat: n(ev.lat ?? ev.current_lat), current_lng: n(ev.lng ?? ev.current_lng),
            instant_power_kw: n(ev.instant_power_kw), vehicle_state: st ?? veh.current_state,
            odometer_km: n(ev.odometer_km), range_remaining_km: n(ev.range_remaining_km),
            dtc_codes: Array.isArray(ev.dtc_codes) ? ev.dtc_codes : null, data_source: DS, packet_integrity: "full" };
          for (const k of Object.keys(pkt)) if (pkt[k] === null) delete pkt[k];
          if (dryRun) { results.push({ stream, vehicle: veh.id, would_update: { soc, state: st }, packet: pkt }); ok++; continue; }
          const { error: pErr } = await sb.from("ottoq_telemetry_packets").insert(pkt);
          const vu: any = {}; if (soc !== null) vu.current_soc = Math.round(soc); if (st) vu.current_state = st;
          if (Object.keys(vu).length) await sb.from("vehicles").update(vu).eq("id", veh.id);
          const brain = await brainSignal(sb, veh.id, soc, null, DS);
          results.push({ stream, vehicle: veh.id, soc_updated: soc, state_updated: st, packet_logged: !pErr, packet_error: pErr?.message ?? null, brain }); ok++;
        } else if (stream === "ocpp") {
          const mt = String(ev.message_type ?? ev.messageType ?? "StatusNotification");
          const dir = OCPP_DIR.includes(String(ev.direction || "").toLowerCase()) ? String(ev.direction).toLowerCase() : "cs_to_csms";
          const chargerId = await resolveCharger(sb, ev.charger_id ?? ev.charger_ref ?? ev.ocpp_identifier, depot_id);
          const msg: any = { charger_id: chargerId, message_at: now, direction: dir,
            message_type: mt, ocpp_version: String(ev.ocpp_version ?? "2.0.1"), payload: ev.payload ?? ev, data_source: DS };
          if (dryRun) { results.push({ stream, would_write: "ottoq_ocpp_messages", message_type: mt, charger: chargerId }); ok++; continue; }
          const { error: mErr } = await sb.from("ottoq_ocpp_messages").insert(msg);
          const cs = ev.connector_status ?? ev.connectorStatus ?? ev.payload?.connectorStatus;
          let chargerUpdated = false;
          if (chargerId) {
            const cu: any = { last_heartbeat_at: now };
            if (cs && OCPP_STATES.includes(String(cs))) { cu.station_state = String(cs); cu.station_state_changed_at = now; }
            if (String(cs) === "Faulted") cu.last_fault_code = String(ev.error_code ?? ev.payload?.errorCode ?? "FAULT");
            const { error: cErr } = await sb.from("ottoq_ocpp_chargers").update(cu).eq("charger_id", chargerId);
            chargerUpdated = !cErr;
          }
          results.push({ stream, message_type: mt, charger: chargerId, connector_status: cs ?? null, message_logged: !mErr, charger_updated: chargerUpdated, message_error: mErr?.message ?? null }); ok++;
        } else if (stream === "arrival") {
          const veh = await resolveVehicle(sb, ev.vehicle_ref ?? ev.vehicle_id ?? ev.vin, depot_id);
          if (!veh) { results.push({ stream, error: "vehicle not found", ref: ev.vehicle_ref ?? ev.vehicle_id }); continue; }
          const eta = n(ev.eta_min); const arrivalSoc = n(ev.arrival_soc ?? ev.soc);
          const newState = (eta !== null && eta <= 0) ? "arrived_at_gate" : "en_route_to_depot";
          if (dryRun) { results.push({ stream, vehicle: veh.id, would_set_state: newState }); ok++; continue; }
          const brain = await brainSignal(sb, veh.id, arrivalSoc, eta ?? 0, DS);
          const vu: any = { current_state: newState }; if (arrivalSoc !== null) vu.current_soc = Math.round(arrivalSoc);
          const { error: aErr } = await sb.from("vehicles").update(vu).eq("id", veh.id).in("current_state", ["deployed","offline","en_route_to_deployment","en_route_to_depot"]);
          results.push({ stream, vehicle: veh.id, state: newState, eta_min: eta, applied: !aErr,
            appointment: brain?.appointment ?? null, brain, error: aErr?.message ?? null }); ok++;
        } else if (stream === "incident") {
          const veh = (ev.vehicle_ref || ev.vehicle_id) ? await resolveVehicle(sb, ev.vehicle_ref ?? ev.vehicle_id, depot_id) : null;
          const rawType = String(ev.type ?? "other");
          const excType = EXC_TYPES.has(rawType) ? rawType : "other";
          const sev = EXC_SEV.has(String(ev.severity)) ? String(ev.severity) : "medium";
          const desc = String(ev.description ?? "external incident") + (excType !== rawType ? ` [oem_type=${rawType}]` : "");
          const row: any = { depot_id, vehicle_id: veh?.id ?? null, exception_type: excType,
            severity: sev, description: desc, status: "open", data_source: DS };
          if (dryRun) { results.push({ stream, would_write: "exceptions", row }); ok++; continue; }
          const { error } = await sb.from("exceptions").insert(row);
          if (error) { results.push({ stream, error: error.message }); continue; }
          results.push({ stream, wrote: "exceptions", type: excType, oem_type: rawType, data_source: DS }); ok++;
        } else { results.push({ error: "unknown stream: " + stream }); }
      } catch (e) { results.push({ stream, error: e instanceof Error ? e.message : "unknown" }); }
    }
    return json({ stream, source, data_source: DS, depot_id, credential, sim_run_id: runId, dry_run: dryRun, received: events.length, processed: ok, results });
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
