// ============================================================================
// ottoq-cuopt-propose — NVIDIA cuOpt → OTTO-Q external-proposal seam adapter.
// v25: ⭐ AVAILABILITY RE-FIX — THE CHARGER IS A HEALTH SIGNAL, NOT AN OCCUPANCY SIGNAL.
//      Phase-11 showed 11 gate-passed calls abstaining `no_free_stalls_demand_present`
//      with free_stalls_in = 0 on ALL 11 — a category phase 10 did not have.
//      MEASURED ROOT CAUSE (2026-08-03): on those same 11 calls the BOOKING LEDGER
//      (state IN held/active/done, `during` @> sim_clock) says an average of 22.64 of
//      45 charge stalls were FREE — minimum 21, never fewer. Meanwhile the telemetry
//      recorded chargers_healthy = 1.00 on 11 of 11. Supply did not run out; the
//      supply COUNT collapsed.
//      The collapsing term is this function's own `healthy` set, which required
//      ottoq_ocpp_chargers.station_state = 'Available'. That column is an OCPP MIRROR
//      of occupancy, and this function ALREADY tests occupancy directly and more
//      authoritatively via `!s.current_vehicle_id`. So the extra 'Available' test adds
//      nothing while the mirror is in sync and can only ever SUBTRACT supply when it
//      drifts — a strictly one-directional error, and the only term in the predicate
//      able to delete 44 of 45 stalls simultaneously.
//      TWO CHANGES, both confined to how CHARGER HEALTH is read:
//        (1) `usable` = station_state NOT IN ('Faulted','Unavailable'). A charger is
//            excluded when it is BROKEN, never because a mirror says it is busy.
//            Occupancy stays where it belongs: stalls.current_vehicle_id / status /
//            reservation, all unchanged below.
//        (2) Heartbeat staleness now DEGRADES instead of ERASING. The 90-SIM-SECOND
//            freshness window is shared by every charger, so one skipped heartbeat
//            tick zeroes the whole depot at once. If the fresh set is empty while
//            usable chargers exist, we fall back to `usable` and flag
//            heartbeat_fallback — a monitoring signal must never masquerade as an
//            empty depot.
//      SAFETY — THIS CANNOT CREATE A DOUBLE-BOOKING. This function only PROPOSES.
//      Enactment still runs through ottoq_submit_external_proposal → decide_tick's
//      honour path → ottoq.ottoq_validate_assignment, which independently re-checks
//      current_vehicle_id, the reservation, the forward calendar, AND still requires
//      station_state='Available' before begin_charge; and the
//      ottoq_stall_bookings_no_overlap_v3 EXCLUDE constraint is the final backstop
//      (verified 2026-08-03 by rolled-back probe: rejects overlap against
//      held/active/done/interrupted).
//      NEW TELEMETRY (feeds the workload_harness_metrics invariant):
//      physically_free_stalls, free_stalls_defect, chargers_usable, chargers_fresh,
//      heartbeat_fallback, chargers_mirror_occupied.
//      UNCHANGED, BYTE-FOR-BYTE: the LP formulation, the CSR construction, the parse
//      path (response.solver_response.solution.primal_solution), the stall selection,
//      compatible(), effKw(), pairCost(), heuristic(), the en-route cohort, the Zone A
//      approach band, the pinned instance, the energy-cap parity rule, and verify_jwt.
// v23: SUPPLY FIX — PINNED INSTANCE + ENERGY-CAP PARITY.
// v22: SUPPLY TELEMETRY — every execution writes EXACTLY ONE row to cuopt_invocation_log.
// v21: APPROACH BAND — Zone A cars posed to the LP alongside the gate cohort.
// v20: SOLVER SWITCH — ROUTING → LINEAR PROGRAMMING (action: "cuOpt_LP").
// v19: CLOCK-DOMAIN FIX — charger heartbeat freshness measured against the SIM clock.
// v18: additive en-route reserved cohort as a dedicated second instance.
// v16: constraint-aware cost model.
// ============================================================================
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const CUOPT_ENDPOINT = "https://optimize.api.nvidia.com/v1/nvidia/cuopt";
const FN_VERSION = "edge:v25";

// v25: a charger is unusable only when BROKEN. Occupancy is read from the stall.
const CHARGER_BROKEN = new Set(["Faulted", "Unavailable"]);

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function num(x: unknown, d: number) { const n = Number(x); return isFinite(n) ? n : d; }

// ── v22 SUPPLY TELEMETRY ────────────────────────────────────────────────────
async function logInvocation(sb: any, row: Record<string, unknown>) {
  try {
    if (!sb) { console.error("cuopt telemetry: no client, row dropped:", JSON.stringify(row)); return; }
    const { error } = await sb.from("cuopt_invocation_log").insert({
      stage: "edge",
      source_note: FN_VERSION,
      called_at: new Date().toISOString(),
      ...row,
    });
    if (error) console.error("cuopt telemetry INSERT failed:", error.message, JSON.stringify(row));
  } catch (e) {
    console.error("cuopt telemetry threw (ignored):", e instanceof Error ? e.message : e);
  }
}

// Same compatibility semantics as the deterministic ranker + orchestrate-tick.
function compatible(inlet: string | null, s: any): boolean {
  if (!inlet) return true;
  const sup = s.supported_inlet_types;
  const list: string[] = Array.isArray(sup) ? sup : sup ? [sup] : [];
  if (list.length) return list.map((x) => String(x).toUpperCase()).includes(inlet.toUpperCase());
  const c = s.connector_type ? String(s.connector_type).toUpperCase() : "";
  if (!c) return true;
  if (c === "MULTI") return true;
  if (c === "NACS") return ["NACS", "TESLA_PROPRIETARY"].includes(inlet.toUpperCase());
  return c === inlet.toUpperCase();
}

// Effective draw = min(connector, inlet) × charging-curve taper — the brain's exact E3 formula.
function effKw(v: any, s: any): number {
  const base = Math.min(num(s.connector_max_kw, 50), num(v.inlet_max_kw, 250));
  const soc = num(v.current_soc, 50);
  const taper = num(s.connector_max_kw, 50) <= 50 ? 1.0 : soc < 55 ? 0.85 : soc < 75 ? 0.55 : 0.3;
  return Math.round(base * taper * 10) / 10;
}

// The pairwise preference score. Lower is better. Unchanged from v16.
function pairCost(v: any, s: any): number {
  const soc = num(v.current_soc, 100);
  let c = (100 - soc) + (s.stall_type === "dcfc" ? 0 : 35);
  if (s.stall_type === "dcfc" && soc > 60) c += 60;      // conserve DCFC for the needy
  c += Math.round(num(s.relative_y, 200) / 20);           // nearest-wash spatial policy
  return c;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  const t0 = Date.now();
  const startedAt = new Date().toISOString();
  const ms = () => Date.now() - t0;
  let sb: any = null;
  try {
    sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  } catch (e) {
    console.error("client construction failed:", e instanceof Error ? e.message : e);
  }
  let simRunIdForLog: string | null = null;

  try {
    const body = await req.json();
    const sim_run_id = body?.sim_run_id;
    // v23: the gate ships the instance it authorised. Absent ⇒ v22 behaviour.
    const pinnedIds: string[] = Array.isArray(body?.vehicle_ids)
      ? body.vehicle_ids.filter((x: unknown) => typeof x === "string" && x.length > 0)
      : [];
    const gateTick = body?.gate_tick ?? null;
    if (!sim_run_id) {
      await logInvocation(sb, { sim_run_id: null, called_at: startedAt, latency_ms: ms(),
        abstained_reason: "missing_sim_run_id", detail: { fn_http_status: 400 } });
      return json({ error: "sim_run_id required" }, 400);
    }
    simRunIdForLog = sim_run_id;

    const { data: run } = await sb.from("ottoq_sim_runs")
      .select("sim_run_id, depot_id, status, sim_clock_current, tick_count").eq("sim_run_id", sim_run_id).single();
    if (!run) {
      await logInvocation(sb, { sim_run_id, called_at: startedAt, latency_ms: ms(),
        abstained_reason: "run_not_found", detail: { fn_http_status: 404 } });
      return json({ error: "run not found" }, 404);
    }
    const depot = run.depot_id;
    const clock = run.sim_clock_current ?? new Date().toISOString();
    const tickSeq = run.tick_count ?? null;

    // ══════════════════════════════════════════════════════════════════════════
    // v23 PINNED INSTANCE — the gate cohort. (unchanged)
    // net.http_post only QUEUES a request; the pg_net worker cannot transmit until
    // the CALLING TRANSACTION COMMITS, so this function physically cannot run until
    // after greedy has already placed the cars. Re-deriving the cohort here sampled
    // a world that had moved on. ottoq_cuopt_refresh therefore ships the ids it
    // gated on. THIS PINS IDENTITY, NEVER ELIGIBILITY — every id is re-validated
    // below against the SAME envelope ottoq_decide_tick's own cursor accepts.
    // ══════════════════════════════════════════════════════════════════════════
    const cohortMode = pinnedIds.length > 0 ? "pinned" : "live_rederive";
    let vehicles: any[] = [];
    if (cohortMode === "pinned") {
      const { data: pv } = await sb.from("vehicles")
        .select("id, current_soc, inlet_type, inlet_max_kw, current_state, current_stall_id")
        .eq("home_depot_id", depot).eq("category", "autonomous")
        .in("id", pinnedIds)
        .in("current_state", ["arrived_at_gate", "staged_awaiting_service"])
        .lt("current_soc", 85)
        .order("current_soc", { ascending: true }).limit(40);
      vehicles = pv ?? [];
    } else {
      const { data: lv } = await sb.from("vehicles")
        .select("id, current_soc, inlet_type, inlet_max_kw")
        .eq("home_depot_id", depot).eq("category", "autonomous")
        .eq("current_state", "arrived_at_gate").lt("current_soc", 85)
        .order("current_soc", { ascending: true }).limit(40);
      vehicles = lv ?? [];
    }

    const { data: stalls } = await sb.from("stalls")
      .select("id, stall_type, status, connector_type, supported_inlet_types, connector_max_kw, relative_y, current_vehicle_id, reserved_by, reservation_expires_at, ocpp_charger_id")
      .eq("depot_id", depot).in("stall_type", ["dcfc", "l2"]).limit(120);

    // ══════════════════════════════════════════════════════════════════════════
    // v25 CHARGER HEALTH — see the header. `station_state` is an OCPP mirror of
    // OCCUPANCY; occupancy is read authoritatively from the stall a few lines down
    // (`!s.current_vehicle_id`). Here we ask one question only: is this charger
    // BROKEN? Heartbeat freshness is still measured — in the SIM clock domain, per
    // v19 — but a stale heartbeat now degrades to the usable set rather than
    // deleting the entire depot's supply on one skipped tick.
    // ══════════════════════════════════════════════════════════════════════════
    const since = new Date(new Date(clock).getTime() - 90_000).toISOString();
    const { data: chargerRows } = await sb.from("ottoq_ocpp_chargers")
      .select("charger_id, station_state, last_heartbeat_at").eq("depot_id", depot);
    const allChargers = chargerRows ?? [];
    const usable = new Set(allChargers
      .filter((c: any) => !CHARGER_BROKEN.has(String(c.station_state)))
      .map((c: any) => c.charger_id));
    const fresh = new Set(allChargers
      .filter((c: any) => usable.has(c.charger_id) &&
        c.last_heartbeat_at && String(c.last_heartbeat_at) >= since)
      .map((c: any) => c.charger_id));
    const heartbeatFallback = fresh.size === 0 && usable.size > 0;
    const healthy = heartbeatFallback ? usable : fresh;
    const mirrorOccupied = allChargers.filter((c: any) => String(c.station_state) === "Occupied").length;

    // v23: second half of the pinned-instance re-validation. Needs the stall rows,
    // so it runs here rather than in the vehicle query — no extra round trip.
    const pinnedRequested = cohortMode === "pinned" ? pinnedIds.length : 0;
    let pinnedDroppedOnStall = 0, pinnedDroppedReserved = 0, pinnedDroppedByState = 0;
    if (cohortMode === "pinned") {
      pinnedDroppedByState = pinnedRequested - vehicles.length;   // state / soc / limit
      const chargeStallIds = new Set((stalls ?? []).map((s: any) => s.id));
      const heldByVehicle = new Set(
        (stalls ?? [])
          .filter((s: any) => s.reserved_by &&
            (!s.reservation_expires_at || s.reservation_expires_at >= clock))
          .map((s: any) => String(s.reserved_by)));
      vehicles = vehicles.filter((v: any) => {
        if (v.current_stall_id && chargeStallIds.has(v.current_stall_id)) { pinnedDroppedOnStall++; return false; }
        if (heldByVehicle.has(String(v.id))) { pinnedDroppedReserved++; return false; }
        return true;
      });
    }

    const allCands = vehicles ?? [];

    // OCCUPANCY IS READ FROM THE STALL, not from the charger mirror. Unchanged from
    // v23 apart from `healthy` now meaning "not broken" (see v25 block above).
    const freeStalls = (stalls ?? []).filter((s: any) =>
      s.status !== "occupied" &&
      !s.current_vehicle_id &&
      (!s.reserved_by || (s.reservation_expires_at && s.reservation_expires_at <= clock)) &&
      (!s.ocpp_charger_id || healthy.has(s.ocpp_charger_id)));

    // v25 INVARIANT INPUT. PHYSICAL freedom only: nobody parked on it and the stall
    // itself is not out of service. Deliberately ignores reservations, the charger
    // mirror and the heartbeat, so it is an independent witness against which
    // free_stalls_in can be audited. free_stalls_in = 0 while this is > 0 is a DEFECT.
    const physicallyFree = (stalls ?? []).filter((s: any) =>
      !s.current_vehicle_id &&
      s.status !== "maintenance" && s.status !== "closed" && s.status !== "occupied").length;

    let enrouteAll: any[] = [];
    try {
      const { data: reservedStalls } = await sb.from("stalls")
        .select("id, stall_type, reserved_by, reservation_expires_at")
        .eq("depot_id", depot).not("reserved_by", "is", null);
      const holders: Record<string, any> = {};
      for (const s of reservedStalls ?? []) {
        const liveRes = !s.reservation_expires_at || s.reservation_expires_at >= clock;
        if (liveRes && String(s.stall_type) !== "dcfc") holders[s.reserved_by] = s;
      }
      const holderIds = Object.keys(holders);
      if (holderIds.length) {
        const { data: enr } = await sb.from("vehicles")
          .select("id, current_soc, inlet_type, inlet_max_kw, current_state")
          .eq("home_depot_id", depot).eq("category", "autonomous")
          .in("current_state", ["deployed", "en_route_to_depot"])
          .lt("current_soc", 45).in("id", holderIds)
          .order("current_soc", { ascending: true }).limit(20);
        enrouteAll = (enr ?? []).map((v: any) => ({ ...v, enroute: true, reserved_stall_id: holders[v.id].id }));
      }
    } catch (e) {
      console.error("enroute cohort query failed (gate cohort unaffected):", e instanceof Error ? e.message : e);
    }

    // ── v21 APPROACH BAND — Zone A candidate SELECTION ──────────────────────
    let zoneAAll: any[] = [];
    let zoneAError: string | null = null;
    try {
      const { data: za, error: zaErr } = await sb.from("ottoq_approach_band")
        .select("vehicle_id, current_soc, inlet_type, inlet_max_kw, minutes_out")
        .eq("sim_run_id", sim_run_id)
        .eq("zone", "A")
        .eq("in_cuopt_window", true)
        .eq("category", "autonomous")
        .lt("current_soc", 85)
        .order("minutes_out", { ascending: true })
        .limit(40);
      if (zaErr) throw new Error(zaErr.message);
      zoneAAll = (za ?? []).map((v: any) => ({
        id: v.vehicle_id, current_soc: v.current_soc, inlet_type: v.inlet_type,
        inlet_max_kw: v.inlet_max_kw, minutes_out: v.minutes_out,
      }));
    } catch (e) {
      zoneAError = e instanceof Error ? e.message : String(e);
      console.error("approach band query failed (gate cohort unaffected):", zoneAError);
    }

    let reserveFrac = 0.25;
    try {
      const { data: f } = await sb.rpc("ottoq_policy_get", {
        p_sim_run_id: sim_run_id, p_param_key: "approach_reserve_max_fraction", p_default: 0.25 });
      if (f !== null && f !== undefined && isFinite(Number(f))) reserveFrac = Number(f);
    } catch (_) { reserveFrac = 0.25; }
    reserveFrac = Math.max(0, Math.min(1, reserveFrac));

    const freeDcfc = freeStalls.filter((s: any) =>
      s.stall_type === "dcfc" && s.status === "available" && !s.reserved_by &&
      s.ocpp_charger_id && healthy.has(s.ocpp_charger_id));

    const gateIds = new Set(allCands.map((v: any) => v.id));
    const enrouteIds = new Set(enrouteAll.map((v: any) => v.id));
    const zoneACap = Math.max(0, Math.floor(freeStalls.length * reserveFrac));
    const zoneACands = zoneAAll
      .filter((v: any) => !gateIds.has(v.id) && !enrouteIds.has(v.id))
      .slice(0, zoneACap);
    const zoneAIds = new Set(zoneACands.map((v: any) => v.id));

    const cands = [...allCands, ...zoneACands].slice(0, freeStalls.length);
    const enrouteCands = enrouteAll.slice(0, freeDcfc.length);

    // v25: the supply-side health block, shared by both log paths.
    const supplyDetail = {
      chargers_healthy: healthy.size, chargers_usable: usable.size, chargers_fresh: fresh.size,
      chargers_total: allChargers.length, chargers_mirror_occupied: mirrorOccupied,
      heartbeat_fallback: heartbeatFallback, heartbeat_since: since,
      physically_free_stalls: physicallyFree,
      free_stalls_defect: freeStalls.length === 0 && physicallyFree > 0,
    };

    if ((cands.length === 0 && enrouteCands.length === 0) || freeStalls.length === 0) {
      const reason = freeStalls.length === 0
        ? ((allCands.length + enrouteAll.length + zoneAAll.length) > 0
            ? "no_free_stalls_demand_present" : "no_free_stalls_no_demand")
        : "no_candidates_in_instance";
      await logInvocation(sb, {
        sim_run_id, tick_seq: tickSeq, sim_clock: clock, called_at: startedAt,
        candidates_in: cands.length, free_stalls_in: freeStalls.length,
        proposals_out: 0, abstained_reason: reason, latency_ms: ms(), http_status: null,
        detail: {
          fn_http_status: 200, source: "none", nvidia_called: false,
          gate_candidates: allCands.length, enroute_candidates: enrouteAll.length,
          zone_a_candidates: zoneAAll.length, zone_a_error: zoneAError,
          dcfc_free: freeDcfc.length,
          stalls_scanned: (stalls ?? []).length,
          cohort_mode: cohortMode, gate_tick: gateTick, pinned_requested: pinnedRequested,
          pinned_dropped: { by_state_or_soc: pinnedDroppedByState,
                            on_charge_stall: pinnedDroppedOnStall,
                            already_reserved: pinnedDroppedReserved },
          ...supplyDetail,
        },
      });
      return json({ proposed: 0, candidates: allCands.length, enroute_candidates: enrouteAll.length,
        zone_a_candidates: zoneAAll.length, zone_a_in_instance: 0, zone_a_proposed: 0,
        zone_a_reserve_fraction: reserveFrac, zone_a_error: zoneAError,
        stalls: freeStalls.length, dcfc_free: freeDcfc.length, source: "none",
        cohort_mode: cohortMode, pinned_requested: pinnedRequested, ...supplyDetail });
    }

    let capKw: number | null = null;
    let committedKw = 0;
    try {
      const { data: cap } = await sb.rpc("ottoq_active_charge_cap_kw", {
        p_sim_run_id: sim_run_id, p_depot_id: depot, p_sim_clock: clock });
      capKw = cap === null || cap === undefined ? null : Number(cap);
      if (capKw !== null) {
        const { data: charging } = await sb.from("vehicles")
          .select("current_soc, inlet_max_kw, current_stall_id")
          .eq("home_depot_id", depot).in("current_state", ["charging_dcfc", "charging_l2"]);
        const ids = (charging ?? []).map((v: any) => v.current_stall_id).filter(Boolean);
        const { data: chStalls } = ids.length
          ? await sb.from("stalls").select("id, connector_max_kw").in("id", ids)
          : { data: [] as any[] };
        const kwByStall: Record<string, number> = {};
        for (const s of chStalls ?? []) kwByStall[s.id] = num(s.connector_max_kw, 50);
        for (const v of charging ?? []) {
          const cmax = kwByStall[v.current_stall_id] ?? 50;
          committedKw += effKw({ current_soc: v.current_soc, inlet_max_kw: v.inlet_max_kw }, { connector_max_kw: cmax });
        }
      }
    } catch (_) { capKw = null; }

    const apiKey = Deno.env.get("NVIDIA_API_KEY_CUOPT") ?? Deno.env.get("NVIDIA_API_KEY");
    type Assign = { vehicleId: string; stallId: string; stallType: string; soc: number; kw: number; enroute: boolean; src: string };
    let assignments: Assign[] = [];
    let source = "cuopt_fallback";
    let enrouteSource = "none";
    let cuoptError: string | null = apiKey ? null : "no NVIDIA_API_KEY_CUOPT";
    let solveMs: number | null = null;
    let solveStatus: string | null = null;
    let bindingHint: unknown = null;
    const tele: { httpStatus?: number } = {};
    const nvidiaStatuses: number[] = [];

    if (cands.length > 0) {
      let raw: any[] = [];
      if (apiKey) {
        try {
          const r = await cuoptAssign(apiKey, cands, freeStalls, tele);
          raw = r.assignments; source = "cuopt";
          solveMs = r.solverTimeMs; solveStatus = r.status; bindingHint = r.binding;
        }
        catch (e) { cuoptError = e instanceof Error ? e.message : String(e); console.error("cuOpt LP gate solve failed; heuristic fallback:", cuoptError); raw = heuristic(cands, freeStalls); source = "cuopt_fallback"; }
        if (tele.httpStatus !== undefined) nvidiaStatuses.push(tele.httpStatus);
      } else {
        raw = heuristic(cands, freeStalls);
      }
      assignments.push(...raw.map((a: any) => ({ ...a, enroute: false, src: source })));
    }

    if (enrouteCands.length > 0) {
      const taken = new Set(assignments.map((a) => a.stallId));
      const upgradeStalls = freeDcfc.filter((s: any) => !taken.has(s.id));
      if (upgradeStalls.length > 0) {
        const eCands = enrouteCands.slice(0, upgradeStalls.length);
        let raw: any[] = [];
        if (apiKey) {
          try { const r = await cuoptAssign(apiKey, eCands, upgradeStalls, tele); raw = r.assignments; enrouteSource = "cuopt"; }
          catch (e) { const msg = e instanceof Error ? e.message : String(e); cuoptError = cuoptError ? cuoptError + " | enroute: " + msg : "enroute: " + msg; console.error("cuOpt LP enroute solve failed; heuristic fallback:", msg); raw = heuristic(eCands, upgradeStalls); enrouteSource = "cuopt_fallback"; }
          if (tele.httpStatus !== undefined) nvidiaStatuses.push(tele.httpStatus);
        } else {
          raw = heuristic(eCands, upgradeStalls);
          enrouteSource = "cuopt_fallback";
        }
        assignments.push(...raw.map((a: any) => ({ ...a, enroute: true, src: enrouteSource })));
      }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // v23 ENERGY-CAP PARITY (unchanged). The local greedy path is UNCAPPED by
    // doctrine — vehicles and chargers are never held back for energy; the shave is
    // taken through forecast + BESS and by SIGNALLING the external energy system.
    // Only the cuOpt path was capped, so greedy drove committed load past the cap and
    // cuOpt, reading that same load, trimmed ITSELF to nothing. The cap is now
    // ADVISORY here — exact parity — and still fully measured. Set the policy param
    // cuopt_energy_cap_enforce = 1 to restore hard trimming, for an A/B.
    // ══════════════════════════════════════════════════════════════════════════
    let enforceCap = false;
    try {
      const { data: ec } = await sb.rpc("ottoq_policy_get", {
        p_sim_run_id: sim_run_id, p_param_key: "cuopt_energy_cap_enforce", p_default: 0 });
      enforceCap = isFinite(Number(ec)) && Number(ec) >= 1;
    } catch (_) { enforceCap = false; }

    let trimmed = 0;
    let wouldTrim = 0;
    if (capKw !== null) {
      assignments.sort((a, b) => a.soc - b.soc);
      let acc = committedKw;
      const kept: typeof assignments = [];
      for (const a of assignments) {
        if (acc + a.kw > capKw) {
          wouldTrim++;
          if (enforceCap) { trimmed++; continue; }
        }
        acc += a.kw;
        kept.push(a);
      }
      assignments = kept;
    }
    const proposedKw = assignments.reduce((s, a) => s + a.kw, 0);
    const overCapKw = capKw === null ? null
      : Math.round((committedKw + proposedKw - capKw) * 10) / 10;

    let proposed = 0;
    let enrouteProposed = 0;
    let zoneAProposed = 0;
    let submitErrors = 0;
    for (const a of assignments) {
      const proposal: any = { abstain: false, stall_id: a.stallId, stall_type: a.stallType, requested_kw: a.kw, source: a.src };
      if (a.enroute) proposal.cohort = "enroute_reserved";
      else if (zoneAIds.has(a.vehicleId)) {
        proposal.cohort = "approach_band_zone_a";
        proposal.zone = "A";
        proposal.provisional = true;
      }
      const { error } = await sb.rpc("ottoq_submit_external_proposal", {
        p_sim_run_id: sim_run_id, p_depot_id: depot, p_action_context: "stall_assignment",
        p_entity_type: "vehicle", p_entity_id: a.vehicleId, p_proposal: proposal,
        p_source: a.src, p_ttl_seconds: 90,
      });
      if (!error) {
        proposed++;
        if (a.enroute) enrouteProposed++;
        else if (zoneAIds.has(a.vehicleId)) zoneAProposed++;
      } else { submitErrors++; console.error("submit proposal error:", error.message); }
    }

    const nvidiaAnswered = source === "cuopt" || enrouteSource === "cuopt";
    await logInvocation(sb, {
      sim_run_id, tick_seq: tickSeq, sim_clock: clock, called_at: startedAt,
      candidates_in: cands.length + enrouteCands.length, free_stalls_in: freeStalls.length,
      proposals_out: proposed, latency_ms: ms(),
      http_status: nvidiaStatuses.length ? nvidiaStatuses[nvidiaStatuses.length - 1] : null,
      abstained_reason: nvidiaAnswered
        ? (proposed === 0 ? "solved_but_zero_proposals" : null)
        : (apiKey ? "cuopt_error_heuristic_fallback" : "no_nvidia_api_key"),
      detail: {
        fn_http_status: 200, source, enroute_source: enrouteSource,
        nvidia_called: !!apiKey && (cands.length > 0 || enrouteCands.length > 0),
        nvidia_statuses: nvidiaStatuses,
        solver: { kind: "LP", status: solveStatus, solve_ms: solveMs, binding: bindingHint },
        gate_candidates: allCands.length, enroute_in_instance: enrouteCands.length,
        zone_a_candidates: zoneAAll.length, zone_a_in_instance: zoneACands.length,
        zone_a_proposed: zoneAProposed, zone_a_cap: zoneACap, zone_a_error: zoneAError,
        enroute_proposed: enrouteProposed, dcfc_free: freeDcfc.length,
        submit_errors: submitErrors,
        stalls_scanned: (stalls ?? []).length,
        cohort_mode: cohortMode, gate_tick: gateTick, pinned_requested: pinnedRequested,
        pinned_dropped: { by_state_or_soc: pinnedDroppedByState,
                          on_charge_stall: pinnedDroppedOnStall,
                          already_reserved: pinnedDroppedReserved },
        energy: { cap_kw: capKw, committed_kw: Math.round(committedKw * 10) / 10,
                  proposed_kw: Math.round(proposedKw * 10) / 10, over_cap_kw: overCapKw,
                  cap_enforced: enforceCap, would_trim_by_cap: wouldTrim, trimmed_by_cap: trimmed },
        cuopt_error: cuoptError,
        ...supplyDetail,
      },
    });

    return json({ proposed, candidates: allCands.length, stalls: freeStalls.length, source,
      solver: { kind: "LP", status: solveStatus, solve_ms: solveMs, binding: bindingHint },
      cohort_mode: cohortMode, gate_tick: gateTick, pinned_requested: pinnedRequested,
      pinned_dropped: { by_state_or_soc: pinnedDroppedByState,
                        on_charge_stall: pinnedDroppedOnStall,
                        already_reserved: pinnedDroppedReserved },
      enroute_candidates: enrouteAll.length, enroute_in_instance: enrouteCands.length,
      enroute_proposed: enrouteProposed, enroute_source: enrouteSource, dcfc_free: freeDcfc.length,
      zone_a_candidates: zoneAAll.length, zone_a_in_instance: zoneACands.length,
      zone_a_proposed: zoneAProposed, zone_a_cap: zoneACap,
      zone_a_reserve_fraction: reserveFrac, zone_a_error: zoneAError,
      sim_clock: clock,
      energy: { cap_kw: capKw, committed_kw: Math.round(committedKw * 10) / 10,
                proposed_kw: Math.round(proposedKw * 10) / 10, over_cap_kw: overCapKw,
                cap_enforced: enforceCap, would_trim_by_cap: wouldTrim, trimmed_by_cap: trimmed },
      cuopt_error: cuoptError, ...supplyDetail });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "unknown";
    await logInvocation(sb, { sim_run_id: simRunIdForLog, called_at: startedAt, latency_ms: ms(),
      abstained_reason: "exception", detail: { fn_http_status: 500, error: msg } });
    return json({ error: msg }, 500);
  }
});

// Deterministic fallback: neediest → DCFC first, COMPATIBLE + north-first only.
function heuristic(vehicles: any[], stalls: any[]) {
  const byY = (a: any, b: any) => num(a.relative_y, 999) - num(b.relative_y, 999);
  const ordered = [...stalls.filter((s) => s.stall_type === "dcfc").sort(byY), ...stalls.filter((s) => s.stall_type === "l2").sort(byY)];
  const used = new Set<string>();
  const out: any[] = [];
  for (const v of vehicles) {
    const s = ordered.find((x) => !used.has(x.id) && compatible(v.inlet_type, x));
    if (!s) continue;
    used.add(s.id);
    out.push({ vehicleId: v.id, stallId: s.id, stallType: s.stall_type, soc: num(v.current_soc, 50), kw: effKw(v, s) });
  }
  return out;
}

// ── NVIDIA cuOpt LINEAR PROGRAM — min-cost bipartite assignment ──
// One 0/1 variable per COMPATIBLE (vehicle, stall) pair. Incompatible pairs have no
// variable at all, so they are structurally unselectable.
// Constraints (all "<= 1", expressed as bounds [0,1]):
//   rows 0..n-1  : vehicle i occupies at most one stall
//   rows n..n+m-1: stall j receives at most one vehicle
// The constraint matrix of a bipartite assignment is TOTALLY UNIMODULAR, so the LP
// optimum is integral — no MILP needed, and the solver terminates on OPTIMALITY.
// Objective: minimise sum((cost - R) * x), R = maxCost + 1, so every assignment has a
// negative coefficient → assign as MANY vehicles as possible, cheapest-first.
async function cuoptAssign(apiKey: string, vehicles: any[], stalls: any[], tele?: { httpStatus?: number }) {
  const n = vehicles.length, m = stalls.length;
  if (n === 0 || m === 0) return { assignments: [], solverTimeMs: 0, status: "empty", binding: null };

  const pairs: Array<{ i: number; j: number; cost: number }> = [];
  const byVeh: number[][] = Array.from({ length: n }, () => []);
  const byStall: number[][] = Array.from({ length: m }, () => []);
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < m; j++) {
      if (!compatible(vehicles[i].inlet_type, stalls[j])) continue;   // structural: no variable
      const idx = pairs.length;
      pairs.push({ i, j, cost: pairCost(vehicles[i], stalls[j]) });
      byVeh[i].push(idx);
      byStall[j].push(idx);
    }
  }
  if (pairs.length === 0) throw new Error("no compatible vehicle/stall pairs");

  const maxCost = pairs.reduce((a, p) => Math.max(a, p.cost), 0);
  const R = maxCost + 1;
  const coefficients = pairs.map((p) => p.cost - R);

  // CSR. Indices within each row are ascending because pairs are built in (i,j) order.
  const offsets: number[] = [0];
  const indices: number[] = [];
  const values: number[] = [];
  for (let i = 0; i < n; i++) { for (const k of byVeh[i]) { indices.push(k); values.push(1); } offsets.push(indices.length); }
  for (let j = 0; j < m; j++) { for (const k of byStall[j]) { indices.push(k); values.push(1); } offsets.push(indices.length); }
  const rows = n + m;

  const payload = {
    action: "cuOpt_LP",
    data: {
      csr_constraint_matrix: { offsets, indices, values },
      constraint_bounds: { lower_bounds: new Array(rows).fill(0), upper_bounds: new Array(rows).fill(1) },
      objective_data: { coefficients, scalability_factor: 1, offset: 0 },
      variable_bounds: { lower_bounds: new Array(pairs.length).fill(0), upper_bounds: new Array(pairs.length).fill(1) },
      maximize: false,
      solver_config: { time_limit: 5 },   // safety net only; LP terminates on optimality
    },
  };

  const res = await fetch(CUOPT_ENDPOINT, { method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
    body: JSON.stringify(payload) });
  if (tele) tele.httpStatus = res.status;   // v22 telemetry only
  const rawText = await res.text();
  if (!res.ok) throw new Error("HTTP " + res.status + ": " + rawText.slice(0, 220));
  let result: any;
  try { result = JSON.parse(rawText); } catch { throw new Error("non-JSON (" + res.status + "): " + rawText.slice(0, 160)); }

  const sr = result?.response?.solver_response;
  const sol = sr?.solution;
  const status = String(sr?.status ?? "unknown");
  const primal: number[] = sol?.primal_solution ?? [];
  if (!Array.isArray(primal) || primal.length !== pairs.length)
    throw new Error("LP: bad primal_solution (len " + (primal?.length ?? "nil") + " vs vars " + pairs.length + "), status=" + status);
  if (status !== "Optimal" && status !== "FeasibleFound")
    throw new Error("LP not optimal: status=" + status);

  const out: any[] = [];
  const usedVeh = new Set<number>(), usedStall = new Set<number>();
  const order = pairs.map((_, k) => k).sort((a, b) => (primal[b] ?? 0) - (primal[a] ?? 0));
  for (const k of order) {
    if ((primal[k] ?? 0) < 0.5) continue;
    const { i, j } = pairs[k];
    if (usedVeh.has(i) || usedStall.has(j)) continue;
    const v = vehicles[i], s = stalls[j];
    if (!compatible(v.inlet_type, s)) continue;          // belt-and-braces
    usedVeh.add(i); usedStall.add(j);
    out.push({ vehicleId: v.id, stallId: s.id, stallType: s.stall_type, soc: num(v.current_soc, 50), kw: effKw(v, s) });
  }
  if (out.length === 0) throw new Error("LP returned no assignments; status=" + status + " vars=" + pairs.length);

  // Dual values on the STALL rows (n..n+m-1) are shadow prices.
  const duals: number[] = sol?.dual_solution ?? [];
  let binding: unknown = null;
  if (Array.isArray(duals) && duals.length === rows) {
    let bestJ = -1, bestAbs = 0;
    for (let j = 0; j < m; j++) { const d = Math.abs(duals[n + j] ?? 0); if (d > bestAbs) { bestAbs = d; bestJ = j; } }
    if (bestJ >= 0 && bestAbs > 0) binding = { stall_type: stalls[bestJ].stall_type, shadow_price: Math.round(bestAbs * 1000) / 1000 };
  }

  return { assignments: out, solverTimeMs: Math.round(Number(sol?.solver_time ?? 0) * 1000 * 1000) / 1000, status, binding };
}
