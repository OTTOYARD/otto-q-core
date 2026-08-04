// ottoq-energy-optimize v2 — energy co-optimizer + shield-gated commit.
// Computes BESS dispatch + DCFC cap, then (submit=true) emits them via
// ottoq_emit_recommendation -> 52-rule shield (EN.003 BESS; EN.001/002/004 power cap).
// shadow-safe by default (records + shield-evaluates, no actuation).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const DEFAULT_DEPOT = "11111111-1111-1111-1111-111111111111";
function json(obj: any, status = 200) { return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } }); }
function num(x: any, d = 0) { const n = Number(x); return isFinite(n) ? n : d; }
function rank(label: string) { const m: any = { off_peak: 0, mid_peak: 1, peak: 2, on_peak: 2, super_peak: 3 }; return m[label] ?? 1; }

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const depot_id = body.depot_id ?? DEFAULT_DEPOT;
    const submit = body.submit === true;
    const shadow = body.shadow !== false;
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const [{ data: depot }, { data: energyRows }, { data: bessRows }, { data: dr }, { data: tariffs }, { data: gridEv }] = await Promise.all([
      sb.from("depots").select("name,service_max_kw,demand_charge_threshold_kw,dcfc_max_concurrent_kw,dcfc_safety_margin_pct,demand_response_active").eq("id", depot_id).maybeSingle(),
      sb.from("site_energy_snapshots").select("timestamp,grid_import_kw,solar_generation_kw,bess_output_kw,total_ev_charging_kw,building_load_kw,peak_demand_kw_15min,billing_period_peak_kw,current_tariff_label,current_rate_per_kwh").eq("depot_id", depot_id).order("timestamp", { ascending: false }).limit(1),
      sb.from("ottoq_bess_units").select("bess_id,bess_identifier,capacity_kwh,max_charge_kw,max_discharge_kw,current_soc_pct,current_temperature_c,current_state,current_power_kw,soc_min_floor_pct,soc_max_ceiling_pct,temperature_max_c,roundtrip_efficiency_pct,auxiliary_load_kw").eq("depot_id", depot_id).limit(1),
      sb.from("ottoq_dr_calls").select("required_load_cap_kw,expires_at,call_status,reason").eq("depot_id", depot_id).in("call_status", ["active", "issued"]).limit(1),
      sb.from("ottoq_tariff_windows").select("label,rate_usd_per_kwh,hour_start,hour_end,season").eq("depot_id", depot_id).eq("active", true),
      sb.from("ottoq_grid_events").select("event_type,severity,active,expires_at").eq("depot_id", depot_id).eq("active", true).limit(3),
    ]);
    if (!depot) return json({ error: "depot not found" }, 404);
    const e = energyRows?.[0] ?? {}; const b = bessRows?.[0] ?? {};
    const now = new Date(); const hour = now.getUTCHours(); const month = now.getUTCMonth() + 1;
    const seasonNow = (month >= 5 && month <= 9) ? "summer" : "winter";
    let win: any = null;
    for (const t of (tariffs ?? [])) {
      const h0 = num(t.hour_start), h1 = num(t.hour_end);
      const inWin = h0 <= h1 ? (hour >= h0 && hour < h1) : (hour >= h0 || hour < h1);
      const seasonOk = t.season === "all" || t.season === seasonNow || !t.season;
      if (inWin && seasonOk && (!win || rank(t.label) > rank(win.label))) win = t;
    }
    const tariffLabel = win?.label ?? e.current_tariff_label ?? "unknown";
    const rate = num(win?.rate_usd_per_kwh, num(e.current_rate_per_kwh, 0.12));
    const expensive = rank(tariffLabel) >= 2; const cheap = rank(tariffLabel) === 0;
    const solar = num(e.solar_generation_kw); const building = num(e.building_load_kw); const ev = num(e.total_ev_charging_kw);
    const netLoad = building + ev - solar;
    const solarSurplus = Math.max(0, solar - (building + ev));
    const billingPeak = num(e.billing_period_peak_kw, num(depot.service_max_kw, 2500) * 0.6);
    const serviceMax = num(depot.service_max_kw, 2500);
    const margin = num(depot.dcfc_safety_margin_pct, 10) / 100;
    const drActive = (dr ?? []).length > 0;
    const drCap = drActive ? num(dr[0].required_load_cap_kw, serviceMax) : Infinity;
    const hardstop = (gridEv ?? []).some((g: any) => String(g.event_type || "").toLowerCase().includes("hardstop") || String(g.severity || "").toLowerCase() === "critical");
    const effectiveCap = Math.min(serviceMax * (1 - margin), drCap, billingPeak);
    const cap = num(b.capacity_kwh, 0); const soc = num(b.current_soc_pct);
    const floor = num(b.soc_min_floor_pct, 10); const ceil = num(b.soc_max_ceiling_pct, 95);
    const temp = num(b.current_temperature_c); const tempMax = num(b.temperature_max_c, 50);
    const tempOk = temp < tempMax - 2;
    const dischargeableKwh = Math.max(0, (soc - floor) / 100 * cap);
    const chargeableKwh = Math.max(0, (ceil - soc) / 100 * cap);
    const pDisMax = Math.min(num(b.max_discharge_kw, 0), dischargeableKwh);
    const pChMax = Math.min(num(b.max_charge_kw, 0), chargeableKwh);
    let bessKw = 0; let action = "hold"; let reason = "Balanced; holding BESS.";
    if (hardstop) {
      bessKw = Math.min(pDisMax, Math.max(0, netLoad)); action = bessKw > 0 ? "discharge" : "hold";
      reason = "Grid hardstop (EN.005): no new grid-fed charging; BESS supports critical load only.";
    } else if (drActive && netLoad > drCap && pDisMax > 0 && tempOk) {
      bessKw = Math.min(pDisMax, netLoad - drCap); action = "discharge";
      reason = "Active demand-response (EN.004): discharging BESS to hold site load under the " + Math.round(drCap) + " kW cap.";
    } else if (netLoad > effectiveCap - 1 && pDisMax > 0 && tempOk) {
      bessKw = Math.min(pDisMax, netLoad - (effectiveCap - 1)); action = "discharge";
      reason = "Peak-shaving: discharging to keep grid draw under the " + Math.round(effectiveCap) + " kW peak target (protects the demand charge).";
    } else if (expensive && pDisMax > 0 && tempOk && netLoad > 0) {
      bessKw = Math.min(pDisMax * 0.6, netLoad); action = "discharge";
      reason = "Tariff arbitrage: " + tariffLabel + " at $" + rate.toFixed(3) + "/kWh; discharging stored energy to offset expensive grid (reserve kept).";
    } else if (solarSurplus > 5 && pChMax > 0 && tempOk) {
      bessKw = -Math.min(pChMax, solarSurplus); action = "charge";
      reason = "Solar capture: banking " + Math.round(solarSurplus) + " kW of surplus solar into the BESS (free energy).";
    } else if (cheap && pChMax > 0 && tempOk) {
      const room = Math.max(0, effectiveCap - netLoad);
      bessKw = -Math.min(pChMax, room); action = bessKw < 0 ? "charge" : "hold";
      reason = "Off-peak banking: charging BESS at $" + rate.toFixed(3) + "/kWh to discharge during peak (arbitrage), within the peak cap.";
    }
    if (!tempOk && bessKw !== 0) { bessKw = 0; action = "hold"; reason = "BESS thermal guard (EN.003): temp " + temp + "C near limit; holding."; }
    const siteNonEv = building - bessKw;
    let dcfcCap = Math.max(0, Math.min(num(depot.dcfc_max_concurrent_kw, effectiveCap), effectiveCap - siteNonEv));
    if (hardstop) dcfcCap = 0;
    const projGrid = Math.max(0, netLoad - bessKw);
    const projPeak = Math.max(billingPeak, siteNonEv + dcfcCap);
    const naiveGrid = Math.max(0, netLoad);
    const hourlySavingsUsd = Math.max(0, (naiveGrid - projGrid)) * rate;
    const out: any = {
      depot: depot.name, timestamp_utc: now.toISOString(),
      context: { tariff_window: tariffLabel, rate_usd_per_kwh: rate, solar_kw: solar, building_kw: building, ev_charging_kw: ev, net_load_kw: Math.round(netLoad), solar_surplus_kw: Math.round(solarSurplus), billing_period_peak_kw: billingPeak, service_max_kw: serviceMax, dr_active: drActive, dr_cap_kw: drActive ? drCap : null, grid_hardstop: hardstop },
      bess: { id: b.bess_id, identifier: b.bess_identifier, soc_pct: soc, temp_c: temp, action, setpoint_kw: Math.round(Math.abs(bessKw)), direction: bessKw > 0 ? "discharge" : bessKw < 0 ? "charge" : "idle", reason },
      dcfc_concurrency_cap_kw: Math.round(dcfcCap),
      projections: { effective_cap_kw: Math.round(effectiveCap), projected_grid_kw: Math.round(projGrid), projected_peak_kw: Math.round(projPeak), demand_peak_protected: projPeak <= billingPeak + 0.5, est_hourly_grid_cost_usd: Math.round(projGrid * rate * 100) / 100, est_hourly_savings_vs_no_bess_usd: Math.round(hourlySavingsUsd * 100) / 100 },
      note: "Deterministic single-step optimum (run per tick = rolling MPC). cuOpt-MILP foresight upgrade when self-hosted on GPU.",
    };
    if (submit && b.bess_id) {
      const recIds: string[] = [];
      const bessAction = bessKw > 0 ? "bess_discharge" : bessKw < 0 ? "bess_charge" : "bess_dispatch";
      const { data: bessRec, error: bErr } = await sb.rpc("ottoq_emit_recommendation", {
        p_proposed_action: bessAction, p_prediction_type: "demand_kw",
        p_action_parameters: { bess_id: b.bess_id, direction: out.bess.direction, setpoint_kw: out.bess.setpoint_kw, current_soc_pct: soc, temperature_c: temp, reason },
        p_entity_type: "bess", p_entity_id: b.bess_id, p_depot_id: depot_id, p_shadow_only: shadow,
      });
      if (bessRec) recIds.push(bessRec);
      const { data: capRec } = await sb.rpc("ottoq_emit_recommendation", {
        p_proposed_action: "power_increase", p_prediction_type: "demand_kw",
        p_action_parameters: { scope: "dcfc_concurrency_cap", requested_kw: Math.round(dcfcCap), depot_id, building_kw: building, effective_cap_kw: Math.round(effectiveCap), billing_peak_kw: billingPeak },
        p_entity_type: "depot", p_entity_id: depot_id, p_depot_id: depot_id, p_shadow_only: shadow,
      });
      if (capRec) recIds.push(capRec);
      let results: any = null;
      if (recIds.length) { const { data } = await sb.from("ottoq_recommendations").select("recommendation_id,proposed_action,status,rules_blocked_by,decision_reason").in("recommendation_id", recIds); results = data; }
      out.committed = { shadow_only: shadow, bess_error: bErr ? bErr.message : null, recommendations: results };
    }
    return json(out);
  } catch (e) { return json({ error: e instanceof Error ? e.message : "unknown" }, 500); }
});
