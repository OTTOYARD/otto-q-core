// ============================================================================
// OTTO-Q API — Supabase Edge Function Entry Point
// ============================================================================
// Single edge function that routes all /otto-q-api/* requests to the
// appropriate handler. Uses the Supabase client for database operations.
//
// Deploy: supabase functions deploy otto-q-api
// Invoke: https://<project-ref>.supabase.co/functions/v1/otto-q-api/<path>
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.0";
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";

// ---------------------------------------------------------------------------
// Supabase client (service role — full database access)
// ---------------------------------------------------------------------------
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// ---------------------------------------------------------------------------
// Lightweight DataStore implementation using Supabase client
// ---------------------------------------------------------------------------
const store = {
  // Depot
  async getDepotConfig(depotId: string) {
    const { data } = await supabase.from("depots").select("*").eq("id", depotId).single();
    const { data: engineCfg } = await supabase.from("engine_config").select("*").eq("depot_id", depotId).single();
    return { ...data?.config, ...engineCfg, depot_id: depotId };
  },

  // Stalls
  async getStallsByDepot(depotId: string, filters?: any) {
    let q = supabase.from("stalls").select("*").eq("depot_id", depotId);
    if (filters?.type) q = q.eq("stall_type", filters.type);
    if (filters?.status) q = q.eq("status", filters.status);
    if (filters?.zone) q = q.eq("zone", filters.zone);
    const { data } = await q;
    return data || [];
  },

  async getStall(stallId: string) {
    const { data } = await supabase.from("stalls").select("*").eq("id", stallId).single();
    return data;
  },

  async getStallByChargePointId(chargePointId: string) {
    const { data } = await supabase.from("stalls").select("*")
      .contains("equipment_config", { charge_point_id: chargePointId }).single();
    return data;
  },

  async updateStall(stallId: string, updates: any) {
    await supabase.from("stalls").update(updates).eq("id", stallId);
  },

  async getTasksByStall(stallId: string, filters?: any) {
    let q = supabase.from("schedule_tasks").select("*").eq("assigned_stall_id", stallId);
    if (filters?.status) q = q.in("status", filters.status);
    if (filters?.limit) q = q.limit(filters.limit);
    q = q.order("scheduled_start", { ascending: true });
    const { data } = await q;
    return data || [];
  },

  // Vehicles
  async getVehicle(vehicleId: string) {
    const { data } = await supabase.from("vehicles").select("*").eq("id", vehicleId).single();
    return data;
  },

  async getVehicleByAVId(platform: string, avId: string) {
    const { data } = await supabase.from("vehicles").select("*")
      .eq("platform", platform).eq("av_api_vehicle_id", avId).single();
    return data;
  },

  async updateVehicle(vehicleId: string, updates: any) {
    await supabase.from("vehicles").update(updates).eq("id", vehicleId);
  },

  async updateVehicleState(vehicleId: string, newState: string, stallId: string | null, triggeredBy: string, userId?: string, metadata?: any) {
    await supabase.from("vehicles").update({
      current_state: newState,
      current_stall_id: stallId,
      last_state_change: new Date().toISOString(),
    }).eq("id", vehicleId);

    await supabase.from("vehicle_state_log").insert({
      vehicle_id: vehicleId,
      to_state: newState,
      stall_id: stallId,
      triggered_by: triggeredBy,
      triggered_by_user_id: userId,
      metadata: metadata || {},
    });
  },

  async getVehiclesByFleet(fleetId: string, filters?: any) {
    let q = supabase.from("vehicles").select("*").eq("fleet_operator_id", fleetId).eq("is_active", true);
    if (filters?.state) q = q.eq("current_state", filters.state);
    if (filters?.category) q = q.eq("category", filters.category);
    const { data } = await q;
    return data || [];
  },

  // Schedules
  async getScheduleForVehicle(vehicleId: string, date: string) {
    const { data } = await supabase.from("vehicle_schedules").select("*")
      .eq("vehicle_id", vehicleId).eq("scheduled_date", date)
      .order("created_at", { ascending: false }).limit(1).single();
    return data;
  },

  async getSchedule(scheduleId: string) {
    const { data } = await supabase.from("vehicle_schedules").select("*").eq("id", scheduleId).single();
    return data;
  },

  async getSchedulesByDepot(depotId: string, date: string) {
    const { data } = await supabase.from("vehicle_schedules").select("*")
      .eq("depot_id", depotId).eq("scheduled_date", date);
    return data || [];
  },

  async getSchedulesByFleet(fleetId: string, date: string) {
    const { data } = await supabase.from("vehicle_schedules").select("*, vehicles!inner(fleet_operator_id)")
      .eq("vehicles.fleet_operator_id", fleetId).eq("scheduled_date", date);
    return data || [];
  },

  async createSchedule(schedule: any) {
    const { data } = await supabase.from("vehicle_schedules").insert(schedule).select().single();
    return data;
  },

  async updateSchedule(scheduleId: string, updates: any) {
    await supabase.from("vehicle_schedules").update(updates).eq("id", scheduleId);
  },

  // Waves
  async createWave(wave: any) {
    const { data } = await supabase.from("waves").insert(wave).select().single();
    return data;
  },

  // Tasks
  async getTask(taskId: string) {
    const { data } = await supabase.from("schedule_tasks").select("*").eq("id", taskId).single();
    return data;
  },

  async getTasksBySchedule(scheduleId: string) {
    const { data } = await supabase.from("schedule_tasks").select("*")
      .eq("vehicle_schedule_id", scheduleId).order("sequence_order", { ascending: true });
    return data || [];
  },

  async getTasksByDepot(depotId: string, filters?: any) {
    let q = supabase.from("schedule_tasks").select("*").eq("depot_id", depotId);
    if (filters?.status) q = q.in("status", filters.status);
    q = q.order("sequence_order", { ascending: true });
    const { data } = await q;
    return data || [];
  },

  async getTasksByVehicle(vehicleId: string, date: string) {
    const { data } = await supabase.from("schedule_tasks").select("*, vehicle_schedules!inner(scheduled_date)")
      .eq("vehicle_id", vehicleId).eq("vehicle_schedules.scheduled_date", date);
    return data || [];
  },

  async createTask(task: any) {
    const { data } = await supabase.from("schedule_tasks").insert(task).select().single();
    return data;
  },

  async updateTask(taskId: string, updates: any) {
    await supabase.from("schedule_tasks").update(updates).eq("id", taskId);
  },

  // Exceptions
  async createException(exception: any) {
    const { data } = await supabase.from("exceptions").insert(exception).select().single();
    return data;
  },

  async getExceptionsByDepot(depotId: string, filters?: any) {
    let q = supabase.from("exceptions").select("*").eq("depot_id", depotId);
    if (filters?.status) q = q.in("status", filters.status);
    if (filters?.severity) q = q.eq("severity", filters.severity);
    q = q.order("created_at", { ascending: false });
    const { data } = await q;
    return data || [];
  },

  // OCPP
  async getOCPPSessionByTransactionId(transactionId: string) {
    const { data } = await supabase.from("ocpp_sessions").select("*")
      .eq("transaction_id", transactionId).single();
    return data;
  },

  async createOCPPSession(session: any) {
    const { data } = await supabase.from("ocpp_sessions").insert(session).select().single();
    return data;
  },

  async updateOCPPSession(sessionId: string, updates: any) {
    await supabase.from("ocpp_sessions").update(updates).eq("id", sessionId);
  },

  async getActiveOCPPSessions(depotId: string) {
    const { data } = await supabase.from("ocpp_sessions").select("*")
      .eq("depot_id", depotId).eq("status", "active");
    return data || [];
  },

  // Charger cooldown
  async getChargerCooldownState(stallId: string) {
    const { data } = await supabase.from("charger_cooldowns").select("*")
      .eq("stall_id", stallId).eq("resolved", false)
      .order("created_at", { ascending: false }).limit(1).single();
    return data;
  },

  async updateChargerCooldownState(cooldown: any) {
    if (cooldown.id) {
      await supabase.from("charger_cooldowns").update(cooldown).eq("id", cooldown.id);
    } else {
      await supabase.from("charger_cooldowns").insert(cooldown);
    }
  },

  // Energy
  async getLatestEnergySnapshot(depotId: string) {
    const { data } = await supabase.from("site_energy_snapshots").select("*")
      .eq("depot_id", depotId).order("recorded_at", { ascending: false }).limit(1).single();
    return data;
  },

  async getActiveDemandShapingPlan(depotId: string) {
    const { data } = await supabase.from("demand_shaping_plans").select("*")
      .eq("depot_id", depotId).eq("status", "active")
      .order("created_at", { ascending: false }).limit(1).single();
    return data;
  },

  async getTariffSchedule(depotId: string, _date: string) {
    const { data } = await supabase.from("tariff_schedules").select("*")
      .eq("depot_id", depotId).eq("is_active", true).limit(1).single();
    return data;
  },

  // Predictions
  async getPredictions(depotId: string, filters?: any) {
    let q = supabase.from("ottoq_predictions").select("*").eq("depot_id", depotId);
    if (filters?.status) q = q.eq("status", filters.status);
    q = q.order("created_at", { ascending: false });
    const { data } = await q;
    return data || [];
  },

  // Notifications
  async queueNotification(notification: any) {
    const channels = notification.channels || ["in_app"];
    for (const channel of channels) {
      await supabase.from("notifications").insert({
        depot_id: notification.depot_id,
        fleet_operator_id: notification.recipient_type === "fleet_operator" ? notification.recipient_id : null,
        retail_member_id: notification.recipient_type === "retail_member" ? notification.recipient_id : null,
        staff_user_id: notification.recipient_type === "staff" ? notification.recipient_id || null : null,
        channel,
        event_type: notification.event_type,
        title: notification.title,
        body: notification.body,
        vehicle_id: notification.vehicle_id,
        schedule_task_id: notification.schedule_task_id,
        exception_id: notification.exception_id,
      });
    }
  },

  // Telemetry
  async recordTelemetry(vehicleId: string, timestamp: string, data: any) {
    await supabase.from("vehicle_telemetry").insert({
      vehicle_id: vehicleId,
      recorded_at: timestamp,
      soc_percent: data.soc_percent,
      location_lat: data.location?.lat,
      location_lng: data.location?.lng,
      speed_mph: data.speed_mph,
      odometer_miles: data.odometer_miles,
      heading_degrees: data.heading_degrees,
    });
  },

  // Logging
  async logScheduleModification(entry: any) {
    await supabase.from("schedule_modifications").insert(entry);
  },

  async logEarlyRecall(entry: any) {
    await supabase.from("early_recall_log").insert(entry);
  },

  async logEmergencyInsertion(entry: any) {
    await supabase.from("emergency_queue_insertions").insert(entry);
  },

  // Schedules by date (alias)
  async getSchedulesByDate(depotId: string, date: string) {
    return this.getSchedulesByDepot(depotId, date);
  },

  // Active OCPP session (singular alias)
  async getActiveOCPPSession(depotId: string) {
    const sessions = await this.getActiveOCPPSessions(depotId);
    return sessions[0] || null;
  },

  // BESS
  async getLatestBESSSnapshot(depotId: string) {
    const { data } = await supabase.from("bess_snapshots").select("*")
      .eq("depot_id", depotId).order("recorded_at", { ascending: false }).limit(1).single();
    return data;
  },

  // =========================================================================
  // OTTOW Dispatch System — Store Methods
  // =========================================================================

  // Missions
  async createMission(mission: any) {
    const { data } = await supabase.from("ottow_missions").insert(mission).select().single();
    return data;
  },

  async getMission(missionId: string) {
    const { data } = await supabase.from("ottow_missions").select("*").eq("id", missionId).single();
    return data;
  },

  async getMissionsByDepot(depotId: string, filters?: any) {
    let q = supabase.from("ottow_missions").select("*").eq("depot_id", depotId);
    if (filters?.status === "active") {
      q = q.not("status", "in", '("closed","cancelled")');
    } else if (filters?.status) {
      q = q.eq("status", filters.status);
    }
    if (filters?.driver_staff_id) q = q.eq("driver_staff_id", filters.driver_staff_id);
    q = q.order("created_at", { ascending: false });
    if (filters?.limit) q = q.limit(filters.limit);
    const { data } = await q;
    return data || [];
  },

  async updateMission(missionId: string, updates: any) {
    updates.updated_at = new Date().toISOString();
    const { data } = await supabase.from("ottow_missions").update(updates).eq("id", missionId).select().single();
    return data;
  },

  async getActiveMissionForDriver(driverStaffId: string) {
    const { data } = await supabase.from("ottow_missions").select("*")
      .eq("driver_staff_id", driverStaffId)
      .not("status", "in", '("closed","cancelled")')
      .order("created_at", { ascending: false })
      .limit(1).single();
    return data;
  },

  // Mission Events
  async createMissionEvent(event: any) {
    const { data } = await supabase.from("ottow_mission_events").insert(event).select().single();
    return data;
  },

  async getMissionEvents(missionId: string) {
    const { data } = await supabase.from("ottow_mission_events").select("*")
      .eq("mission_id", missionId).order("created_at", { ascending: true });
    return data || [];
  },

  // Drivers
  async getDriver(driverId: string) {
    const { data } = await supabase.from("ottow_drivers").select("*").eq("id", driverId).single();
    return data;
  },

  async getDriverByStaffId(staffUserId: string) {
    const { data } = await supabase.from("ottow_drivers").select("*").eq("staff_user_id", staffUserId).single();
    return data;
  },

  async getAvailableDrivers(depotId: string) {
    const { data } = await supabase.from("ottow_drivers").select("*, staff_users(first_name, last_name, display_name)")
      .eq("depot_id", depotId).eq("status", "available");
    return data || [];
  },

  async updateDriver(driverId: string, updates: any) {
    updates.updated_at = new Date().toISOString();
    await supabase.from("ottow_drivers").update(updates).eq("id", driverId);
  },

  async updateDriverByStaffId(staffUserId: string, updates: any) {
    updates.updated_at = new Date().toISOString();
    await supabase.from("ottow_drivers").update(updates).eq("staff_user_id", staffUserId);
  },

  // ── Notification Queue ──

  async createNotification(notification: any) {
    const { data } = await supabase.from("ottow_notifications").insert(notification).select().single();
    return data;
  },

  async getNotification(notificationId: string) {
    const { data } = await supabase.from("ottow_notifications").select("*").eq("id", notificationId).single();
    return data;
  },

  async getNotificationsByDepot(depotId: string, filters?: any) {
    let q = supabase.from("ottow_notifications").select("*").eq("depot_id", depotId).order("received_at", { ascending: false });
    if (filters?.status) q = q.eq("status", filters.status);
    if (filters?.limit) q = q.limit(filters.limit);
    const { data } = await q;
    return data || [];
  },

  async getNotificationByDedupKey(dedupKey: string) {
    const { data } = await supabase.from("ottow_notifications").select("*")
      .eq("dedup_key", dedupKey).not("status", "eq", "rejected").limit(1).single();
    return data;
  },

  async updateNotification(notificationId: string, updates: any) {
    updates.updated_at = new Date().toISOString();
    const { data } = await supabase.from("ottow_notifications").update(updates).eq("id", notificationId).select().single();
    return data;
  },

  // ── API Keys ──

  async getApiKeyByHash(keyHash: string) {
    const { data } = await supabase.from("ottow_api_keys").select("*")
      .eq("key_hash", keyHash).eq("is_active", true).single();
    return data;
  },

  async createApiKey(apiKey: any) {
    const { data } = await supabase.from("ottow_api_keys").insert(apiKey).select().single();
    return data;
  },

  async getApiKeysByDepot(depotId: string) {
    const { data } = await supabase.from("ottow_api_keys").select("id, depot_id, key_prefix, source, source_name, allowed_platforms, is_active, last_used_at, created_at")
      .eq("depot_id", depotId);
    return data || [];
  },

  async deactivateApiKey(keyId: string) {
    await supabase.from("ottow_api_keys").update({ is_active: false }).eq("id", keyId);
  },

  // ── Dispatch Rules ──

  async getDispatchRules(depotId: string) {
    const { data } = await supabase.from("ottow_dispatch_rules").select("*")
      .eq("depot_id", depotId).eq("is_active", true).order("priority_order", { ascending: true });
    return data || [];
  },

  async createDispatchRule(rule: any) {
    const { data } = await supabase.from("ottow_dispatch_rules").insert(rule).select().single();
    return data;
  },

  async updateDispatchRule(ruleId: string, updates: any) {
    updates.updated_at = new Date().toISOString();
    const { data } = await supabase.from("ottow_dispatch_rules").update(updates).eq("id", ruleId).select().single();
    return data;
  },

  async deleteDispatchRule(ruleId: string) {
    await supabase.from("ottow_dispatch_rules").delete().eq("id", ruleId);
  },

  // ── Vehicle lookup by platform + external ID ──

  async getVehicleByAVId(platform: string, avApiVehicleId: string) {
    const { data } = await supabase.from("vehicles").select("*")
      .eq("platform", platform).eq("av_api_vehicle_id", avApiVehicleId).single();
    return data;
  },

  async getVehicleByVIN(vin: string) {
    const { data } = await supabase.from("vehicles").select("*").eq("vin", vin).single();
    return data;
  },

  // ══════════════════════════════════════════════════════════════════════════
  // AI BRAIN — Phase 1: Predictive State Model Store Methods
  // ══════════════════════════════════════════════════════════════════════════

  // ── Depot State Snapshots ──

  async saveDepotSnapshot(snapshot: any) {
    const { data, error } = await supabase.from("depot_state_snapshots").insert(snapshot).select().single();
    if (error) throw error;
    return data;
  },

  async getDepotSnapshots(depotId: string, start: string, end: string, limit = 500) {
    const { data } = await supabase.from("depot_state_snapshots").select("*")
      .eq("depot_id", depotId)
      .gte("snapshot_at", start)
      .lte("snapshot_at", end)
      .order("snapshot_at", { ascending: false })
      .limit(limit);
    return data || [];
  },

  async getRecentSnapshots(depotId: string, hours = 24) {
    const since = new Date(Date.now() - hours * 3600000).toISOString();
    const { data } = await supabase.from("depot_state_snapshots").select("*")
      .eq("depot_id", depotId)
      .gte("snapshot_at", since)
      .order("snapshot_at", { ascending: false });
    return data || [];
  },

  async getSnapshotsAtTimeOfDay(depotId: string, hourOfDay: number, dayOfWeek: number | null, lookbackDays = 30) {
    const since = new Date(Date.now() - lookbackDays * 86400000).toISOString();
    let q = supabase.from("depot_state_snapshots").select("*")
      .eq("depot_id", depotId)
      .gte("snapshot_at", since)
      .order("snapshot_at", { ascending: false });
    const { data } = await q;
    // Filter in application: snapshots within +/- 30 min of target hour
    return (data || []).filter((s: any) => {
      const d = new Date(s.snapshot_at);
      const h = d.getUTCHours();
      const dow = d.getUTCDay();
      const hourMatch = Math.abs(h - hourOfDay) <= 1 || Math.abs(h - hourOfDay) >= 23;
      const dowMatch = dayOfWeek === null || dow === dayOfWeek;
      return hourMatch && dowMatch;
    });
  },

  // ── Model Parameters ──

  async getModelParameters(depotId: string, group: string) {
    const { data } = await supabase.from("model_parameters").select("*")
      .eq("depot_id", depotId).eq("parameter_group", group).eq("is_active", true).single();
    return data;
  },

  async getAllModelParameters(depotId: string) {
    const { data } = await supabase.from("model_parameters").select("*")
      .eq("depot_id", depotId).eq("is_active", true);
    return data || [];
  },

  async updateModelParameters(depotId: string, group: string, updates: any) {
    // Accepts either flat updates object or legacy (params, version, metrics) signature
    const updatePayload: any = {
      updated_at: new Date().toISOString(),
      ...updates,
    };
    const { data, error } = await supabase.from("model_parameters")
      .update(updatePayload)
      .eq("depot_id", depotId).eq("parameter_group", group)
      .select().single();
    if (error) throw error;
    return data;
  },

  // ── Prediction Outcomes ──

  async recordPredictionOutcome(outcome: any) {
    const { data, error } = await supabase.from("prediction_outcomes").insert(outcome).select().single();
    if (error) throw error;
    return data;
  },

  async getPredictionOutcomes(depotId: string, filters?: { prediction_type?: string; horizon?: number; since?: string; limit?: number }) {
    let q = supabase.from("prediction_outcomes").select("*").eq("depot_id", depotId);
    if (filters?.prediction_type) q = q.eq("prediction_type", filters.prediction_type);
    if (filters?.horizon) q = q.eq("time_horizon_hours", filters.horizon);
    if (filters?.since) q = q.gte("scored_at", filters.since);
    q = q.order("scored_at", { ascending: false }).limit(filters?.limit || 100);
    const { data } = await q;
    return data || [];
  },

  // ── Extended Predictions (AI Brain columns) ──

  async createAIPrediction(prediction: any) {
    const { data, error } = await supabase.from("ottoq_predictions").insert(prediction).select().single();
    if (error) throw error;
    return data;
  },

  async getAIPredictions(depotId: string, filters?: { status?: string; action_type?: string; execution_status?: string; limit?: number }) {
    let q = supabase.from("ottoq_predictions").select("*").eq("depot_id", depotId);
    if (filters?.status) q = q.eq("status", filters.status);
    if (filters?.action_type) q = q.eq("action_type", filters.action_type);
    if (filters?.execution_status) q = q.eq("execution_status", filters.execution_status);
    q = q.order("created_at", { ascending: false }).limit(filters?.limit || 50);
    const { data } = await q;
    return data || [];
  },

  async updatePredictionExecution(predictionId: string, updates: any) {
    const { data, error } = await supabase.from("ottoq_predictions")
      .update({ ...updates, updated_at: new Date().toISOString() })
      .eq("id", predictionId).select().single();
    if (error) throw error;
    return data;
  },

  // ── Historical Data Queries for Prediction Models ──

  async getCompletedChargeSessions(depotId: string, lookbackDays = 30) {
    const since = new Date(Date.now() - lookbackDays * 86400000).toISOString();
    const { data } = await supabase.from("ocpp_sessions").select("*")
      .eq("depot_id", depotId)
      .eq("status", "completed")
      .gte("start_time", since)
      .order("start_time", { ascending: false });
    return data || [];
  },

  async getCompletedTasks(depotId: string, lookbackDays = 60) {
    const since = new Date(Date.now() - lookbackDays * 86400000).toISOString();
    const { data } = await supabase.from("schedule_tasks").select("*")
      .eq("status", "completed")
      .gte("actual_start", since)
      .order("actual_start", { ascending: false });
    return data || [];
  },

  async getVehicleArrivalHistory(depotId: string, lookbackDays = 30) {
    const since = new Date(Date.now() - lookbackDays * 86400000).toISOString();
    const { data } = await supabase.from("vehicle_state_log").select("*")
      .eq("to_state", "arrived_at_gate")
      .gte("transitioned_at", since)
      .order("transitioned_at", { ascending: false });
    return data || [];
  },

  async getVehicleScheduleHistory(depotId: string, lookbackDays = 30) {
    const since = new Date(Date.now() - lookbackDays * 86400000).toISOString();
    const { data } = await supabase.from("vehicle_schedules").select("*")
      .eq("depot_id", depotId)
      .gte("scheduled_date", since.split("T")[0])
      .order("scheduled_date", { ascending: false });
    return data || [];
  },

  async getCurrentDepotVehicles(depotId: string) {
    const onSiteStates = ["arrived_at_gate", "staged_awaiting_service", "charging_dcfc", "charging_l2",
      "charge_complete_holding", "in_wash_bay", "in_detail_bay", "in_service_bay",
      "service_complete_holding", "staged_for_departure", "emergency_staged"];
    const { data } = await supabase.from("vehicles").select("*")
      .eq("depot_id", depotId)
      .in("current_state", onSiteStates);
    return data || [];
  },

  async getCurrentStallStatus(depotId: string) {
    const { data } = await supabase.from("stalls").select("*").eq("depot_id", depotId);
    return data || [];
  },

  async getActiveExceptionCount(depotId: string) {
    const { data, error } = await supabase.from("exceptions").select("id", { count: "exact" })
      .eq("depot_id", depotId).in("status", ["open", "acknowledged", "in_progress"]);
    return data?.length || 0;
  },

  async getActiveOTTOWMissionCount(depotId: string) {
    const activeStatuses = ["reported", "dispatched", "en_route", "on_site", "vehicle_secured", "returning", "arrived_depot", "stall_assigned"];
    const { data } = await supabase.from("ottow_missions").select("id", { count: "exact" })
      .eq("depot_id", depotId).in("status", activeStatuses);
    return data?.length || 0;
  },

  async getLatestEnergySnapshot(depotId: string) {
    const { data } = await supabase.from("site_energy_snapshots").select("*")
      .eq("depot_id", depotId).order("timestamp", { ascending: false }).limit(1).single();
    return data;
  },

  async getPendingTaskCount(depotId: string) {
    const { data } = await supabase.from("schedule_tasks").select("id, status");
    const pending = (data || []).filter((t: any) => t.status === "pending").length;
    const inProgress = (data || []).filter((t: any) => t.status === "in_progress").length;
    const today = new Date().toISOString().split("T")[0];
    const { data: completed } = await supabase.from("schedule_tasks").select("id")
      .eq("status", "completed")
      .gte("actual_end", today + "T00:00:00Z");
    return { pending, in_progress: inProgress, completed_today: completed?.length || 0 };
  },

  async getActiveWaves(depotId: string) {
    const today = new Date().toISOString().split("T")[0];
    const { data } = await supabase.from("waves").select("wave_code, status")
      .eq("depot_id", depotId)
      .eq("scheduled_date", today)
      .in("status", ["confirmed", "in_progress"]);
    return (data || []).map((w: any) => w.wave_code);
  },

  // ══════════════════════════════════════════════════════════════════════════
  // AI BRAIN — Phase 2: Autonomous Action Engine Store Methods
  // ══════════════════════════════════════════════════════════════════════════

  async logAutonomousAction(action: any) {
    const { data, error } = await supabase.from("autonomous_action_log").insert(action).select().single();
    if (error) throw error;
    return data;
  },

  async updateActionLog(actionId: string, updates: any) {
    const { data, error } = await supabase.from("autonomous_action_log")
      .update({ ...updates, updated_at: new Date().toISOString() })
      .eq("id", actionId).select().single();
    if (error) throw error;
    return data;
  },

  async getActionById(actionId: string) {
    const { data, error } = await supabase.from("autonomous_action_log")
      .select("*").eq("id", actionId).single();
    if (error) return null;
    return data;
  },

  async getActionLog(depotId: string, filters?: { status?: string; action_type?: string; limit?: number; since?: string }) {
    let q = supabase.from("autonomous_action_log").select("*").eq("depot_id", depotId);
    if (filters?.status) q = q.eq("status", filters.status);
    if (filters?.action_type) q = q.eq("action_type", filters.action_type);
    if (filters?.since) q = q.gte("created_at", filters.since);
    q = q.order("created_at", { ascending: false }).limit(filters?.limit || 50);
    const { data } = await q;
    return data || [];
  },

  async getRecentActionsByType(depotId: string, actionType: string, hours: number) {
    const since = new Date(Date.now() - hours * 3600000).toISOString();
    const { data } = await supabase.from("autonomous_action_log").select("*")
      .eq("depot_id", depotId).eq("action_type", actionType)
      .gte("created_at", since)
      .in("status", ["completed", "executing", "pending"])
      .order("created_at", { ascending: false });
    return data || [];
  },

  async getGuardrails(depotId: string) {
    const { data } = await supabase.from("action_guardrails").select("*")
      .eq("depot_id", depotId).eq("enabled", true);
    return data || [];
  },

  async getGuardrailForAction(depotId: string, actionType: string) {
    const { data } = await supabase.from("action_guardrails").select("*")
      .eq("depot_id", depotId).eq("action_type", actionType).single();
    return data;
  },

  async updateGuardrail(depotId: string, actionType: string, updates: any) {
    const { data, error } = await supabase.from("action_guardrails")
      .update({ ...updates, updated_at: new Date().toISOString() })
      .eq("depot_id", depotId).eq("action_type", actionType)
      .select().single();
    if (error) throw error;
    return data;
  },

  async upsertGuardrail(guardrail: any) {
    const { data, error } = await supabase.from("action_guardrails")
      .upsert(guardrail, { onConflict: "depot_id,action_type" })
      .select().single();
    if (error) throw error;
    return data;
  },

  // =========================================================================
  // PHASE 3: LEARNING FEEDBACK LOOP — Store Methods
  // =========================================================================

  async createTuningRun(run: any) {
    const { data, error } = await supabase.from("model_tuning_runs")
      .insert(run).select().single();
    if (error) throw error;
    return data;
  },

  async updateTuningRun(runId: string, updates: any) {
    const { data, error } = await supabase.from("model_tuning_runs")
      .update({ ...updates, updated_at: new Date().toISOString() })
      .eq("id", runId).select().single();
    if (error) throw error;
    return data;
  },

  async getTuningRuns(depotId: string, filters?: { parameter_group?: string; status?: string; limit?: number }) {
    let q = supabase.from("model_tuning_runs").select("*").eq("depot_id", depotId);
    if (filters?.parameter_group) q = q.eq("parameter_group", filters.parameter_group);
    if (filters?.status) q = q.eq("status", filters.status);
    q = q.order("created_at", { ascending: false }).limit(filters?.limit || 20);
    const { data } = await q;
    return data || [];
  },

  async upsertDailyAccuracy(record: any) {
    const { data, error } = await supabase.from("prediction_accuracy_daily")
      .upsert(record, { onConflict: "depot_id,report_date,prediction_type,time_horizon_hours" })
      .select().single();
    if (error) throw error;
    return data;
  },

  async getDailyAccuracy(depotId: string, filters?: { prediction_type?: string; days?: number; time_horizon?: number }) {
    const days = filters?.days || 30;
    const since = new Date(Date.now() - days * 86400000).toISOString().split("T")[0];
    let q = supabase.from("prediction_accuracy_daily").select("*")
      .eq("depot_id", depotId).gte("report_date", since);
    if (filters?.prediction_type) q = q.eq("prediction_type", filters.prediction_type);
    if (filters?.time_horizon) q = q.eq("time_horizon_hours", filters.time_horizon);
    q = q.order("report_date", { ascending: false });
    const { data } = await q;
    return data || [];
  },

  async getPredictionOutcomesByDateRange(depotId: string, startDate: string, endDate: string, predictionType?: string) {
    let q = supabase.from("prediction_outcomes").select("*")
      .eq("depot_id", depotId)
      .gte("scored_at", startDate)
      .lte("scored_at", endDate);
    if (predictionType) q = q.eq("prediction_type", predictionType);
    q = q.order("scored_at", { ascending: false });
    const { data } = await q;
    return data || [];
  },

  async getRecentPredictionsWithOutcomes(depotId: string, hours: number = 24) {
    const since = new Date(Date.now() - hours * 3600000).toISOString();
    const { data } = await supabase.from("ottoq_predictions").select("*")
      .eq("depot_id", depotId)
      .gte("created_at", since)
      .order("created_at", { ascending: false });
    return data || [];
  },

  async getUnscoredPredictions(depotId: string, olderThanHours: number = 4) {
    // Predictions that have passed their horizon window and haven't been scored yet
    const cutoff = new Date(Date.now() - olderThanHours * 3600000).toISOString();
    const { data } = await supabase.from("ottoq_predictions").select("*")
      .eq("depot_id", depotId)
      .lte("created_at", cutoff)
      .not("prediction_type", "is", null)
      .is("execution_status", null)  // Not yet scored
      .order("created_at", { ascending: true })
      .limit(100);
    return data || [];
  },
};

// ---------------------------------------------------------------------------
// Haversine distance (miles)
// ---------------------------------------------------------------------------
function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 3958.8; // Earth radius in miles
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ---------------------------------------------------------------------------
// SHA-256 hash (for API key verification)
// ---------------------------------------------------------------------------
async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("");
}

// ---------------------------------------------------------------------------
// Resolve vehicle from flexible identifiers
// ---------------------------------------------------------------------------
async function resolveVehicle(body: any): Promise<any | null> {
  if (body.vehicle_id) {
    return await store.getVehicle(body.vehicle_id);
  }
  if (body.vehicle_platform && body.vehicle_external_id) {
    return await store.getVehicleByAVId(body.vehicle_platform, body.vehicle_external_id);
  }
  if (body.vehicle_vin) {
    return await store.getVehicleByVIN(body.vehicle_vin);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Find best available driver (for auto-dispatch)
// ---------------------------------------------------------------------------
async function findBestDriver(
  depotId: string,
  incidentLat?: number,
  incidentLng?: number,
  requiredCerts?: string[],
  maxDistanceMiles = 15
): Promise<any | null> {
  const drivers = await store.getAvailableDrivers(depotId);
  const now = Date.now();
  const fifteenMin = 15 * 60 * 1000;

  let candidates = drivers.filter((d: any) => {
    // Must have recent location (within 15 min)
    if (d.last_location_at && (now - new Date(d.last_location_at).getTime()) > fifteenMin) return false;
    // Check shift window
    if (d.shift_start && new Date(d.shift_start).getTime() > now) return false;
    if (d.shift_end && new Date(d.shift_end).getTime() < now) return false;
    // Check certifications
    if (requiredCerts && requiredCerts.length > 0) {
      const driverCerts = d.vehicle_class_certs || [];
      if (!requiredCerts.every((c: string) => driverCerts.includes(c))) return false;
    }
    return true;
  });

  if (incidentLat && incidentLng) {
    candidates = candidates.map((d: any) => ({
      ...d,
      _distance: (d.last_location_lat && d.last_location_lng)
        ? haversine(d.last_location_lat, d.last_location_lng, incidentLat, incidentLng)
        : 9999,
    }));
    candidates = candidates.filter((d: any) => d._distance <= maxDistanceMiles);
    candidates.sort((a: any, b: any) => a._distance - b._distance);
  }

  return candidates.length > 0 ? candidates[0] : null;
}

// ---------------------------------------------------------------------------
// Auto-Dispatch Rules Engine
// ---------------------------------------------------------------------------
async function evaluateAutoDispatch(notification: any): Promise<{
  action: string;
  reason: string;
  driver?: any;
  missionCreated?: boolean;
}> {
  const rules = await store.getDispatchRules(notification.depot_id);

  // Find first matching rule
  let matchedRule: any = null;
  for (const rule of rules) {
    if (rule.match_incident_category && rule.match_incident_category !== notification.incident_category) continue;
    if (rule.match_priority && rule.match_priority !== notification.priority) continue;
    if (rule.match_source && rule.match_source !== notification.source) continue;
    matchedRule = rule;
    break;
  }

  if (!matchedRule) {
    return { action: "queue_for_review", reason: "No matching dispatch rule; queued for manual review" };
  }

  switch (matchedRule.action) {
    case "auto_dispatch": {
      let driver = null;
      if (matchedRule.auto_assign_driver) {
        driver = await findBestDriver(
          notification.depot_id,
          notification.incident_lat ? parseFloat(notification.incident_lat) : undefined,
          notification.incident_lng ? parseFloat(notification.incident_lng) : undefined,
          matchedRule.required_certs,
          matchedRule.max_driver_distance_miles || 15,
        );
      }
      const reason = driver
        ? `Auto-dispatched: rule '${matchedRule.rule_name}', driver assigned (${driver._distance?.toFixed(1) || "?"}mi)`
        : matchedRule.auto_assign_driver
          ? `Auto-created mission (no driver available): rule '${matchedRule.rule_name}'`
          : `Auto-created mission (driver assignment manual): rule '${matchedRule.rule_name}'`;
      return { action: "auto_dispatch", reason, driver };
    }
    case "queue_for_review":
      return { action: "queue_for_review", reason: `Queued for review: rule '${matchedRule.rule_name}'` };
    case "reject":
      return { action: "reject", reason: `Auto-rejected: rule '${matchedRule.rule_name}'` };
    case "alert_ops":
      return { action: "alert_ops", reason: `Ops alerted: rule '${matchedRule.rule_name}'` };
    default:
      return { action: "queue_for_review", reason: "Unknown rule action; defaulting to queue" };
  }
}

// ---------------------------------------------------------------------------
// Create mission from notification (shared logic)
// ---------------------------------------------------------------------------
async function createMissionFromNotification(
  notification: any,
  driver: any | null,
): Promise<any> {
  const now = new Date().toISOString();
  const missionData: any = {
    depot_id: notification.depot_id,
    vehicle_id: notification.vehicle_id,
    incident_category: notification.incident_category,
    priority: notification.priority,
    status: driver ? "dispatched" : "reported",
    driver_staff_id: driver?.staff_user_id || null,
    ottow_vehicle_id: null,
    dispatched_at: driver ? now : null,
    pickup_location_lat: notification.incident_lat,
    pickup_location_lng: notification.incident_lng,
    pickup_address: notification.incident_address,
    pickup_notes: notification.description,
    exception_id: notification.exception_id || null,
    source: notification.source,
    external_reference_id: notification.external_reference_id,
    notification_id: notification.id,
  };

  const mission = await store.createMission(missionData);

  // Log creation event
  await store.createMissionEvent({
    mission_id: mission.id,
    event_type: "status_change",
    to_status: "reported",
    actor_type: notification.source === "manual_dispatch" ? "dispatcher" : "otto_q_engine",
    notes: `Mission auto-created from ${notification.source} notification`,
    metadata: { notification_id: notification.id, source: notification.source },
  });

  // If driver assigned, log it and update driver status
  if (driver) {
    await store.createMissionEvent({
      mission_id: mission.id,
      event_type: "driver_assigned",
      from_status: "reported",
      to_status: "dispatched",
      actor_type: "otto_q_engine",
      notes: `Auto-assigned driver (nearest available, ${driver._distance?.toFixed(1) || "?"}mi away)`,
    });
    await store.updateDriverByStaffId(driver.staff_user_id, {
      status: "on_mission",
      current_mission_id: mission.id,
    });
  }

  // Update vehicle state
  if (notification.vehicle_id) {
    await store.updateVehicle(notification.vehicle_id, { current_state: "ottow_dispatched" });
  }

  // Update exception if linked
  if (notification.exception_id) {
    await supabase.from("exceptions").update({
      status: "investigating",
      updated_at: now,
    }).eq("id", notification.exception_id);
  }

  return mission;
}

// ---------------------------------------------------------------------------
// OTTOW Stall Routing Logic
// ---------------------------------------------------------------------------
// Maps incident categories to preferred and fallback stall types.
// battery_thermal MUST go to safety stall — no fallback allowed.
const STALL_ROUTING: Record<string, { preferred: string; fallback: string | null }> = {
  battery_thermal:  { preferred: "safety",      fallback: null },
  collision:        { preferred: "safety",      fallback: "service_bay" },
  mechanical:       { preferred: "service_bay", fallback: "staging" },
  sensor_failure:   { preferred: "service_bay", fallback: "staging" },
  software_lockup:  { preferred: "staging",     fallback: "parking" },
  flat_tire:        { preferred: "service_bay", fallback: "staging" },
  vandalism:        { preferred: "staging",     fallback: "parking" },
  interior_damage:  { preferred: "staging",     fallback: "parking" },
  charger_fault:    { preferred: "service_bay", fallback: "staging" },
  other:            { preferred: "staging",     fallback: "parking" },
};

// Maps incident category → vehicle state when delivered to stall
const VEHICLE_STATE_ON_DELIVERY: Record<string, string> = {
  battery_thermal: "emergency_staged",
  collision:       "emergency_staged",
  mechanical:      "maintenance",
  sensor_failure:  "maintenance",
  software_lockup: "staging",
  flat_tire:       "maintenance",
  vandalism:       "staging",
  interior_damage: "staging",
  charger_fault:   "maintenance",
  other:           "staging",
};

// Valid stage transitions for OTTOW missions
const VALID_TRANSITIONS: Record<string, string[]> = {
  reported:          ["dispatched", "cancelled"],
  dispatched:        ["en_route", "cancelled"],
  en_route:          ["on_site", "cancelled"],
  on_site:           ["vehicle_secured", "cancelled"],
  vehicle_secured:   ["returning", "cancelled"],
  returning:         ["arrived_depot"],
  arrived_depot:     ["stall_assigned"],
  stall_assigned:    ["vehicle_delivered"],
  vehicle_delivered: ["closed"],
};

// Stages where cancellation is no longer allowed
const NO_CANCEL_STAGES = ["returning", "arrived_depot", "stall_assigned", "vehicle_delivered", "closed", "cancelled"];

/**
 * Assigns the best available stall for an OTTOW mission returning to depot.
 * Returns the stall record or null if none available.
 */
async function assignStallForOTTOW(
  depotId: string,
  missionId: string,
  incidentCategory: string,
): Promise<any | null> {
  const routing = STALL_ROUTING[incidentCategory] || STALL_ROUTING.other;

  for (const stallType of [routing.preferred, routing.fallback]) {
    if (!stallType) continue;

    const candidates = await store.getStallsByDepot(depotId, {
      type: stallType,
      status: "available",
    });

    if (candidates.length > 0) {
      // Sort by relative_y (closest to gate/entrance first)
      candidates.sort((a: any, b: any) => (a.relative_y || 0) - (b.relative_y || 0));
      const selected = candidates[0];

      // Reserve the stall
      await store.updateStall(selected.id, {
        status: "reserved",
        reserved_for_mission_id: missionId,
      });

      return selected;
    }
  }

  // No stall available — critical alert for thermal events
  if (incidentCategory === "battery_thermal") {
    await store.createException({
      depot_id: depotId,
      exception_type: "safety_concern",
      severity: "critical",
      title: "No safety stall available for thermal event vehicle",
      description: `OTTOW mission ${missionId} arrived with battery thermal event but no safety stall is available. Vehicle must remain in arrival zone until a safety stall is freed.`,
      status: "open",
    });
    return null;
  }

  // Last resort: any staging or parking stall
  const anyAvailable = await store.getStallsByDepot(depotId, { status: "available" });
  const lastResort = anyAvailable.filter((s: any) =>
    s.stall_type === "staging" || s.stall_type === "parking"
  );

  if (lastResort.length > 0) {
    lastResort.sort((a: any, b: any) => (a.relative_y || 0) - (b.relative_y || 0));
    const selected = lastResort[0];
    await store.updateStall(selected.id, {
      status: "reserved",
      reserved_for_mission_id: missionId,
    });
    return selected;
  }

  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// AI BRAIN — Phase 1: Predictive State Engine
// Pure deterministic functions. No ML frameworks. No external API calls.
// Uses weighted moving averages, exponential smoothing, and variance analysis.
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Captures a complete depot state snapshot from live data.
 * This is the heartbeat of the prediction engine — called every 15 minutes.
 */
async function captureDepotSnapshot(depotId: string): Promise<any> {
  const [vehicles, stalls, energy, taskCounts, activeWaves, exceptionCount, missionCount] = await Promise.all([
    store.getCurrentDepotVehicles(depotId),
    store.getCurrentStallStatus(depotId),
    store.getLatestEnergySnapshot(depotId),
    store.getPendingTaskCount(depotId),
    store.getActiveWaves(depotId),
    store.getActiveExceptionCount(depotId),
    store.getActiveOTTOWMissionCount(depotId),
  ]);

  // Compute vehicle counts by state category
  const chargingStates = ["charging_dcfc", "charging_l2"];
  const serviceStates = ["in_wash_bay", "in_detail_bay", "in_service_bay"];
  const stagedStates = ["staged_awaiting_service", "charge_complete_holding", "service_complete_holding", "staged_for_departure"];
  const enRouteStates = ["en_route_to_depot"];

  const vehiclesCharging = vehicles.filter((v: any) => chargingStates.includes(v.current_state)).length;
  const vehiclesInService = vehicles.filter((v: any) => serviceStates.includes(v.current_state)).length;
  const vehiclesStaged = vehicles.filter((v: any) => stagedStates.includes(v.current_state)).length;
  const vehiclesEnRoute = vehicles.filter((v: any) => enRouteStates.includes(v.current_state)).length;

  // Compute stall utilization by type
  const stallTypes = ["dcfc", "l2", "wash_bay", "detail_bay", "service_bay", "staging", "parking", "safety"];
  const stallUtil: Record<string, any> = {};
  for (const st of stallTypes) {
    const ofType = stalls.filter((s: any) => s.stall_type === st);
    stallUtil[st] = {
      total: ofType.length,
      occupied: ofType.filter((s: any) => s.status === "occupied").length,
      available: ofType.filter((s: any) => s.status === "available").length,
      faulted: ofType.filter((s: any) => s.status === "faulted").length,
      reserved: ofType.filter((s: any) => s.status === "reserved").length,
    };
  }

  // Compute depot health score (0.0 - 1.0)
  const totalStalls = stalls.length || 1;
  const faultedPct = stalls.filter((s: any) => s.status === "faulted").length / totalStalls;
  const exceptionPenalty = Math.min(exceptionCount * 0.05, 0.3);
  const utilizationScore = 1 - (stallUtil.dcfc?.available || 0) / Math.max(stallUtil.dcfc?.total || 1, 1) * 0.1;
  const depotHealthScore = Math.max(0, Math.min(1, 1.0 - faultedPct * 0.4 - exceptionPenalty));

  const snapshot = {
    depot_id: depotId,
    snapshot_at: new Date().toISOString(),
    vehicles_on_site: vehicles.length,
    vehicles_charging: vehiclesCharging,
    vehicles_in_service: vehiclesInService,
    vehicles_staged: vehiclesStaged,
    vehicles_en_route: vehiclesEnRoute,
    stall_utilization: stallUtil,
    active_exceptions: exceptionCount,
    active_ottow_missions: missionCount,
    current_demand_kw: energy?.total_ev_charging_kw || 0,
    peak_demand_kw_15min: energy?.peak_demand_kw_15min || 0,
    queue_depth: taskCounts.pending + taskCounts.in_progress,
    tasks_pending: taskCounts.pending,
    tasks_in_progress: taskCounts.in_progress,
    tasks_completed_today: taskCounts.completed_today,
    current_tariff_label: energy?.current_tariff_label || null,
    current_rate_per_kwh: energy?.current_rate_per_kwh || null,
    solar_generation_kw: energy?.solar_generation_kw || 0,
    bess_output_kw: energy?.bess_output_kw || 0,
    active_wave_codes: activeWaves,
    depot_health_score: parseFloat(depotHealthScore.toFixed(3)),
  };

  return store.saveDepotSnapshot(snapshot);
}

/**
 * Predicts charge duration using historical OCPP session data.
 * Falls back to theoretical calculation when insufficient history.
 *
 * Uses exponentially weighted average of past sessions for the same
 * vehicle (or similar vehicles if sparse data), with thermal derating.
 */
function predictChargeDuration(
  vehicleId: string,
  currentSoc: number,
  targetSoc: number,
  batteryCapacityKwh: number,
  chargerMaxKw: number,
  historicalSessions: any[],
  modelParams: any,
): { predicted_minutes: number; confidence: number; method: string; factors: any } {
  const params = modelParams?.parameters || { history_weight: 0.7, theoretical_weight: 0.3, thermal_derating_factor: 1.15, min_history_samples: 5, confidence_floor: 0.60 };

  // Theoretical calculation (baseline)
  const socDelta = (targetSoc - currentSoc) / 100;
  const energyNeeded = socDelta * batteryCapacityKwh;
  const effectivePower = chargerMaxKw * 0.85; // Typical efficiency
  const theoreticalMinutes = (energyNeeded / effectivePower) * 60;

  // Filter relevant historical sessions for this vehicle
  const vehicleSessions = historicalSessions.filter((s: any) => s.vehicle_id === vehicleId && s.energy_delivered_kwh > 0);

  // If insufficient history, fall back to theoretical with thermal factor
  if (vehicleSessions.length < (params.min_history_samples || 5)) {
    // Try similar vehicles (same platform/battery capacity)
    const similarSessions = historicalSessions.filter((s: any) => s.energy_delivered_kwh > 0);

    if (similarSessions.length < (params.min_history_samples || 5)) {
      const thermalAdjusted = theoreticalMinutes * (params.thermal_derating_factor || 1.15);
      return {
        predicted_minutes: Math.round(thermalAdjusted),
        confidence: params.confidence_floor || 0.60,
        method: "theoretical_with_thermal",
        factors: { theoretical_min: Math.round(theoreticalMinutes), thermal_factor: params.thermal_derating_factor, sessions_available: 0 },
      };
    }
  }

  // Calculate actual kW rate from historical sessions
  const sessions = vehicleSessions.length >= (params.min_history_samples || 5) ? vehicleSessions : historicalSessions.filter((s: any) => s.energy_delivered_kwh > 0);
  const recentSessions = sessions.slice(0, 30); // Cap at 30 most recent

  // Exponentially weighted average of actual charge rates
  const decayRate = 0.05;
  let weightedRateSum = 0;
  let weightSum = 0;
  for (let i = 0; i < recentSessions.length; i++) {
    const s = recentSessions[i];
    const durationHours = (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 3600000;
    if (durationHours <= 0) continue;
    const actualRate = s.energy_delivered_kwh / durationHours;
    const weight = Math.exp(-decayRate * i);
    weightedRateSum += actualRate * weight;
    weightSum += weight;
  }

  if (weightSum === 0) {
    return {
      predicted_minutes: Math.round(theoreticalMinutes * (params.thermal_derating_factor || 1.15)),
      confidence: params.confidence_floor || 0.60,
      method: "theoretical_fallback",
      factors: { reason: "no_valid_sessions" },
    };
  }

  const avgActualRate = weightedRateSum / weightSum;
  const historyMinutes = (energyNeeded / avgActualRate) * 60;

  // Blend historical and theoretical
  const hWeight = params.history_weight || 0.7;
  const tWeight = params.theoretical_weight || 0.3;
  const blended = historyMinutes * hWeight + theoreticalMinutes * tWeight;

  // Confidence based on sample size and variance
  const rates = recentSessions.slice(0, 10).map((s: any) => {
    const dur = (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 3600000;
    return dur > 0 ? s.energy_delivered_kwh / dur : 0;
  }).filter((r: number) => r > 0);

  const mean = rates.reduce((a: number, b: number) => a + b, 0) / rates.length;
  const variance = rates.reduce((a: number, b: number) => a + (b - mean) ** 2, 0) / rates.length;
  const cv = Math.sqrt(variance) / (mean || 1); // Coefficient of variation
  const sampleConfidence = Math.min(1, recentSessions.length / 20);
  const varianceConfidence = Math.max(0, 1 - cv);
  const confidence = Math.max(params.confidence_floor || 0.60, Math.min(0.98, sampleConfidence * 0.4 + varianceConfidence * 0.6));

  return {
    predicted_minutes: Math.round(blended),
    confidence: parseFloat(confidence.toFixed(3)),
    method: vehicleSessions.length >= (params.min_history_samples || 5) ? "vehicle_history" : "fleet_history",
    factors: {
      theoretical_min: Math.round(theoreticalMinutes),
      history_min: Math.round(historyMinutes),
      avg_actual_kw: parseFloat(avgActualRate.toFixed(1)),
      sessions_used: recentSessions.length,
      coefficient_of_variation: parseFloat(cv.toFixed(3)),
    },
  };
}

/**
 * Predicts service duration from historical task completion data.
 * Falls back to catalog estimates when insufficient history.
 */
function predictServiceDuration(
  serviceCode: string,
  vehicleId: string | null,
  completedTasks: any[],
  modelParams: any,
): { predicted_minutes: number; confidence: number; method: string } {
  const params = modelParams?.parameters || { history_weight: 0.6, catalog_weight: 0.4, min_history_samples: 3, confidence_floor: 0.55 };

  // Filter by service code
  const relevantTasks = completedTasks.filter((t: any) =>
    t.service_code === serviceCode && t.actual_start && t.actual_end
  );

  // Try vehicle-specific first
  const vehicleTasks = vehicleId ? relevantTasks.filter((t: any) => t.vehicle_id === vehicleId) : [];

  const tasks = vehicleTasks.length >= (params.min_history_samples || 3) ? vehicleTasks : relevantTasks;

  if (tasks.length < (params.min_history_samples || 3)) {
    // Catalog duration from service definitions (typically 30-60 min)
    const catalogDefaults: Record<string, number> = {
      dcfc_charge: 45, l2_charge: 240, exterior_wash: 20, interior_detail: 35,
      sensor_calibration: 60, tire_rotation: 45, brake_inspection: 30,
      fluid_check: 15, software_update: 20, health_check: 25,
    };
    return {
      predicted_minutes: catalogDefaults[serviceCode] || 30,
      confidence: params.confidence_floor || 0.55,
      method: "catalog_default",
    };
  }

  // Calculate durations
  const durations = tasks.map((t: any) => {
    return (new Date(t.actual_end).getTime() - new Date(t.actual_start).getTime()) / 60000;
  }).filter((d: number) => d > 0 && d < 600); // Exclude outliers > 10 hours

  if (durations.length === 0) {
    return { predicted_minutes: 30, confidence: params.confidence_floor || 0.55, method: "fallback" };
  }

  // Exponentially weighted average (recent tasks weighted more)
  const decayRate = 0.03;
  let weightedSum = 0;
  let weightSum = 0;
  for (let i = 0; i < durations.length; i++) {
    const w = Math.exp(-decayRate * i);
    weightedSum += durations[i] * w;
    weightSum += w;
  }
  const predicted = weightedSum / weightSum;

  const mean = durations.reduce((a, b) => a + b, 0) / durations.length;
  const variance = durations.reduce((a, b) => a + (b - mean) ** 2, 0) / durations.length;
  const cv = Math.sqrt(variance) / (mean || 1);
  const confidence = Math.max(params.confidence_floor || 0.55, Math.min(0.96, 1 - cv * 0.5));

  return {
    predicted_minutes: Math.round(predicted),
    confidence: parseFloat(confidence.toFixed(3)),
    method: vehicleTasks.length >= (params.min_history_samples || 3) ? "vehicle_history" : "fleet_history",
  };
}

/**
 * Projects depot state forward using weighted historical pattern matching.
 * Core prediction algorithm: exponentially-weighted moving average of
 * historical snapshots at the same time-of-day and day-of-week.
 */
function projectDepotState(
  currentSnapshot: any,
  historicalSnapshots: any[],
  modelParams: any,
  horizonHours: number,
): { projected_state: any; confidence: number; key_changes: any[] } {
  const params = modelParams?.parameters || { time_of_day_weight: 0.50, day_of_week_weight: 0.25, recent_trend_weight: 0.25, min_snapshots_required: 20, exponential_decay_rate: 0.05, outlier_exclusion_sigma: 2.0, confidence_floor: 0.40 };
  const horizonDecay: Record<string, number> = params.horizon_confidence_decay || { "2": 1.0, "4": 0.85, "8": 0.65 };

  // If insufficient history, project using current state + simple trends
  if (historicalSnapshots.length < (params.min_snapshots_required || 20)) {
    return {
      projected_state: { ...currentSnapshot, snapshot_at: new Date(Date.now() + horizonHours * 3600000).toISOString() },
      confidence: params.confidence_floor || 0.40,
      key_changes: [{ change_type: "insufficient_history", explanation: `Only ${historicalSnapshots.length} snapshots available, need ${params.min_snapshots_required || 20}` }],
    };
  }

  // Target time for projection
  const targetTime = new Date(Date.now() + horizonHours * 3600000);
  const targetHour = targetTime.getUTCHours();
  const targetDow = targetTime.getUTCDay();

  // Score historical snapshots by relevance (time-of-day + day-of-week + recency)
  const scored = historicalSnapshots.map((s: any) => {
    const d = new Date(s.snapshot_at);
    const hourDiff = Math.min(Math.abs(d.getUTCHours() - targetHour), 24 - Math.abs(d.getUTCHours() - targetHour));
    const dowMatch = d.getUTCDay() === targetDow ? 1 : 0;
    const ageHours = (Date.now() - d.getTime()) / 3600000;
    const recencyScore = Math.exp(-(params.exponential_decay_rate || 0.05) * (ageHours / 24));

    const todWeight = params.time_of_day_weight || 0.50;
    const dowWeight = params.day_of_week_weight || 0.25;
    const trendWeight = params.recent_trend_weight || 0.25;

    const todScore = Math.max(0, 1 - hourDiff / 12);
    const relevance = todScore * todWeight + dowMatch * dowWeight + recencyScore * trendWeight;

    return { snapshot: s, relevance };
  }).filter(s => s.relevance > 0.05).sort((a, b) => b.relevance - a.relevance);

  // Take top N most relevant
  const topN = scored.slice(0, 20);

  if (topN.length === 0) {
    return {
      projected_state: { ...currentSnapshot, snapshot_at: targetTime.toISOString() },
      confidence: params.confidence_floor || 0.40,
      key_changes: [{ change_type: "no_relevant_history", explanation: "No historical snapshots match target time pattern" }],
    };
  }

  // Weighted average of key metrics
  const weightedAvg = (field: string) => {
    let wSum = 0, wDenom = 0;
    for (const s of topN) {
      const val = s.snapshot[field];
      if (val !== null && val !== undefined && typeof val === "number") {
        wSum += val * s.relevance;
        wDenom += s.relevance;
      }
    }
    return wDenom > 0 ? wSum / wDenom : (currentSnapshot[field] || 0);
  };

  const projected = {
    depot_id: currentSnapshot.depot_id,
    snapshot_at: targetTime.toISOString(),
    vehicles_on_site: Math.round(weightedAvg("vehicles_on_site")),
    vehicles_charging: Math.round(weightedAvg("vehicles_charging")),
    vehicles_in_service: Math.round(weightedAvg("vehicles_in_service")),
    vehicles_staged: Math.round(weightedAvg("vehicles_staged")),
    vehicles_en_route: Math.round(weightedAvg("vehicles_en_route")),
    current_demand_kw: parseFloat(weightedAvg("current_demand_kw").toFixed(1)),
    peak_demand_kw_15min: parseFloat(weightedAvg("peak_demand_kw_15min").toFixed(1)),
    queue_depth: Math.round(weightedAvg("queue_depth")),
    tasks_pending: Math.round(weightedAvg("tasks_pending")),
    tasks_in_progress: Math.round(weightedAvg("tasks_in_progress")),
    active_exceptions: Math.round(weightedAvg("active_exceptions")),
    depot_health_score: parseFloat(weightedAvg("depot_health_score").toFixed(3)),
  };

  // Identify significant changes between current and projected
  const keyChanges: any[] = [];
  const numericFields = ["vehicles_on_site", "vehicles_charging", "current_demand_kw", "queue_depth", "active_exceptions"];
  for (const field of numericFields) {
    const current = currentSnapshot[field] || 0;
    const proj = projected[field as keyof typeof projected] || 0;
    const delta = (proj as number) - current;
    const pctChange = current > 0 ? Math.abs(delta / current) : (delta !== 0 ? 1 : 0);
    if (pctChange >= 0.15 || Math.abs(delta) >= 2) {
      keyChanges.push({
        entity_type: field.includes("vehicle") ? "vehicle" : field.includes("demand") ? "demand" : "operations",
        change_type: delta > 0 ? "increase" : "decrease",
        field,
        current_value: current,
        projected_value: proj,
        delta,
        pct_change: parseFloat((pctChange * 100).toFixed(1)),
        explanation: `${field.replace(/_/g, " ")} projected to ${delta > 0 ? "increase" : "decrease"} by ${Math.abs(delta)} (${(pctChange * 100).toFixed(0)}%)`,
      });
    }
  }

  // Confidence: based on history density, variance, and horizon
  const densityScore = Math.min(1, topN.length / 15);
  const avgRelevance = topN.reduce((a, b) => a + b.relevance, 0) / topN.length;
  const horizonFactor = horizonDecay[String(horizonHours)] || 0.5;
  const confidence = Math.max(
    params.confidence_floor || 0.40,
    Math.min(0.95, densityScore * 0.4 + avgRelevance * 0.3 + horizonFactor * 0.3)
  );

  return {
    projected_state: projected,
    confidence: parseFloat(confidence.toFixed(3)),
    key_changes: keyChanges,
  };
}

/**
 * Identifies risk factors from a depot state projection.
 * Returns actionable risks with severity and mitigation suggestions.
 */
function identifyRiskFactors(
  currentSnapshot: any,
  projectedState: any,
  riskParams: any,
): any[] {
  const params = riskParams?.parameters || {
    demand_spike_warning_pct: 0.75, demand_spike_critical_pct: 0.90,
    stall_bottleneck_threshold: 0.85, charger_thermal_risk_temp_f: 140,
    queue_backup_warning: 5, queue_backup_critical: 10,
    min_staging_buffer: 2,
  };

  const risks: any[] = [];
  const demandLimit = params.demand_limit_kw || 1200;

  // Risk 1: Demand spike approaching limit
  const projectedDemandPct = (projectedState.current_demand_kw || 0) / demandLimit;
  if (projectedDemandPct >= (params.demand_spike_critical_pct || 0.90)) {
    risks.push({
      risk_type: "demand_spike",
      severity: "critical",
      probability: Math.min(0.95, projectedDemandPct),
      description: `Projected demand ${projectedState.current_demand_kw.toFixed(0)} kW is ${(projectedDemandPct * 100).toFixed(0)}% of ${demandLimit} kW limit`,
      affected_entities: ["grid", "dcfc_chargers"],
      mitigation: "Throttle non-critical DCFC chargers or defer low-priority charge sessions",
    });
  } else if (projectedDemandPct >= (params.demand_spike_warning_pct || 0.75)) {
    risks.push({
      risk_type: "demand_spike",
      severity: "high",
      probability: Math.min(0.85, projectedDemandPct),
      description: `Projected demand trending toward ${(projectedDemandPct * 100).toFixed(0)}% of limit`,
      affected_entities: ["grid", "dcfc_chargers"],
      mitigation: "Consider deferring standard-priority charge sessions",
    });
  }

  // Risk 2: Stall bottleneck (DCFC)
  const dcfcUtil = projectedState.stall_utilization?.dcfc || currentSnapshot.stall_utilization?.dcfc;
  if (dcfcUtil) {
    const dcfcOccupancyPct = dcfcUtil.occupied / Math.max(dcfcUtil.total, 1);
    if (dcfcOccupancyPct >= (params.stall_bottleneck_threshold || 0.85)) {
      risks.push({
        risk_type: "stall_bottleneck",
        severity: dcfcOccupancyPct >= 0.95 ? "critical" : "high",
        probability: dcfcOccupancyPct,
        description: `DCFC utilization at ${(dcfcOccupancyPct * 100).toFixed(0)}% — ${dcfcUtil.available} of ${dcfcUtil.total} chargers available`,
        affected_entities: ["dcfc_stalls"],
        mitigation: dcfcUtil.available <= 1
          ? "Expedite current charge sessions or resequence queue to prioritize near-complete vehicles"
          : "Monitor closely — approaching capacity",
      });
    }
  }

  // Risk 3: Queue backup
  const queueDepth = projectedState.queue_depth || 0;
  if (queueDepth >= (params.queue_backup_critical || 10)) {
    risks.push({
      risk_type: "stall_bottleneck",
      severity: "critical",
      probability: 0.90,
      description: `Queue depth projected at ${queueDepth} vehicles — significant service delays expected`,
      affected_entities: ["queue", "schedule"],
      mitigation: "Resequence queue to prioritize VIP/priority vehicles, defer non-critical services",
    });
  } else if (queueDepth >= (params.queue_backup_warning || 5)) {
    risks.push({
      risk_type: "stall_bottleneck",
      severity: "medium",
      probability: 0.70,
      description: `Queue depth projected at ${queueDepth} vehicles`,
      affected_entities: ["queue"],
      mitigation: "Monitor queue progression and consider expediting services",
    });
  }

  // Risk 4: Staging buffer depletion
  const stagingUtil = projectedState.stall_utilization?.staging || currentSnapshot.stall_utilization?.staging;
  if (stagingUtil && stagingUtil.available < (params.min_staging_buffer || 2)) {
    risks.push({
      risk_type: "stall_bottleneck",
      severity: stagingUtil.available === 0 ? "critical" : "high",
      probability: 0.80,
      description: `Only ${stagingUtil.available} staging stalls available — vehicle flow will stall`,
      affected_entities: ["staging_stalls"],
      mitigation: "Move completed vehicles to departure staging or request fleet operator pickup",
    });
  }

  // Risk 5: Rising exceptions
  if ((projectedState.active_exceptions || 0) > (currentSnapshot.active_exceptions || 0) + 2) {
    risks.push({
      risk_type: "vehicle_late",
      severity: "medium",
      probability: 0.60,
      description: `Exception count projected to increase from ${currentSnapshot.active_exceptions} to ${projectedState.active_exceptions}`,
      affected_entities: ["operations"],
      mitigation: "Ensure maintenance staff is available and OTTOW drivers are on standby",
    });
  }

  return risks;
}

/**
 * Generates recommended actions from identified risk factors.
 * Each action maps to an executable command in Phase 2's Autonomous Action Engine.
 */
function generateRecommendedActions(
  risks: any[],
  currentSnapshot: any,
  riskParams: any,
): any[] {
  const params = riskParams?.parameters || { action_confidence_threshold: 0.80, auto_execute_confidence_threshold: 0.95 };
  const actions: any[] = [];

  for (const risk of risks) {
    if (risk.risk_type === "demand_spike") {
      actions.push({
        action_type: "throttle_charger",
        title: "Throttle DCFC Chargers to Reduce Demand",
        description: `Reduce charging power on non-priority vehicles to bring demand below ${params.demand_limit_kw || 1200} kW limit`,
        confidence: risk.probability,
        parameters: {
          target_reduction_pct: risk.severity === "critical" ? 30 : 15,
          priority_exempt: true,  // VIP/priority vehicles keep full power
          duration_minutes: 30,
        },
        estimated_impact: `Reduce peak demand by ${risk.severity === "critical" ? "25-35" : "10-20"}%`,
        requires_approval: risk.severity !== "critical",
        risk_level: "low",
        reversible: true,
        deadline: new Date(Date.now() + 15 * 60000).toISOString(),
      });

      if (risk.severity === "critical") {
        actions.push({
          action_type: "defer_charge",
          title: "Defer Standard-Priority Charge Sessions",
          description: "Postpone pending standard-priority charge tasks by 30 minutes to flatten demand curve",
          confidence: risk.probability * 0.9,
          parameters: {
            defer_minutes: 30,
            priority_filter: "standard",
          },
          estimated_impact: "Reduce concurrent charging load by 1-3 vehicles",
          requires_approval: false,
          risk_level: "low",
          reversible: true,
        });
      }
    }

    if (risk.risk_type === "stall_bottleneck" && risk.affected_entities?.includes("dcfc_stalls")) {
      actions.push({
        action_type: "resequence_queue",
        title: "Resequence Queue — Prioritize Near-Complete Charges",
        description: "Move vehicles with SOC > 80% to the front of the departure queue to free chargers faster",
        confidence: risk.probability * 0.85,
        parameters: {
          strategy: "free_chargers_first",
          soc_threshold: 80,
        },
        estimated_impact: "Free 1-2 DCFC stalls within 15-20 minutes",
        requires_approval: true,
        risk_level: "medium",
        reversible: true,
      });
    }

    if (risk.risk_type === "stall_bottleneck" && risk.affected_entities?.includes("staging_stalls")) {
      actions.push({
        action_type: "alert_ops",
        title: "Alert Ops — Staging Buffer Critical",
        description: "Notify operations team to expedite vehicle departures and clear staging area",
        confidence: risk.probability,
        parameters: {
          notification_channels: ["in_app"],
          urgency: risk.severity,
        },
        estimated_impact: "Prevent vehicle flow blockage",
        requires_approval: false,
        risk_level: "low",
        reversible: false,
      });
    }
  }

  return actions;
}

/**
 * Runs a complete prediction cycle for a depot:
 * 1. Captures current state snapshot
 * 2. Loads historical snapshots and model parameters
 * 3. Projects depot state for 2h, 4h, and 8h horizons
 * 4. Identifies risks and generates recommended actions
 * 5. Writes predictions to ottoq_predictions table
 * Returns the full projection with risks and actions.
 */
async function runPredictionCycle(depotId: string): Promise<any> {
  const cycleStart = Date.now();

  // 1. Capture current snapshot
  const snapshot = await captureDepotSnapshot(depotId);

  // 2. Load historical data and model parameters
  const [historicalSnapshots, depotParams, riskParams] = await Promise.all([
    store.getRecentSnapshots(depotId, 24 * 30), // 30 days of history
    store.getModelParameters(depotId, "depot_projection"),
    store.getModelParameters(depotId, "risk_assessment"),
  ]);

  // 3. Project for each horizon
  const horizons = [2, 4, 8];
  const projections: any[] = [];

  for (const h of horizons) {
    const projection = projectDepotState(snapshot, historicalSnapshots, depotParams, h);
    const risks = identifyRiskFactors(snapshot, projection.projected_state, riskParams);
    const actions = generateRecommendedActions(risks, snapshot, riskParams);

    const projectionResult = {
      horizon_hours: h,
      ...projection,
      risk_factors: risks,
      recommended_actions: actions,
    };
    projections.push(projectionResult);

    // 4. Write significant predictions to ottoq_predictions
    for (const action of actions) {
      await store.createAIPrediction({
        depot_id: depotId,
        prediction_type: `risk_mitigation_${action.action_type}`,
        title: action.title,
        description: action.description,
        recommendation: { action, risks: risks.filter((r: any) => r.severity === "critical" || r.severity === "high") },
        confidence: action.confidence,
        supporting_data: {
          snapshot_id: snapshot.id,
          projected_state: projection.projected_state,
          horizon_hours: h,
          cycle_timestamp: new Date().toISOString(),
        },
        time_horizon_hours: h,
        model_version: depotParams?.version || 1,
        action_type: action.action_type,
        action_parameters: action.parameters,
        execution_status: "pending",
        status: "pending",
        analysis_window_start: snapshot.snapshot_at,
        analysis_window_end: new Date(Date.now() + h * 3600000).toISOString(),
        expires_at: new Date(Date.now() + h * 3600000).toISOString(),
      });
    }
  }

  return {
    depot_id: depotId,
    cycle_timestamp: new Date().toISOString(),
    processing_ms: Date.now() - cycleStart,
    current_snapshot: snapshot,
    projections,
    summary: {
      total_risks: projections.reduce((a: number, p: any) => a + p.risk_factors.length, 0),
      total_actions: projections.reduce((a: number, p: any) => a + p.recommended_actions.length, 0),
      critical_risks: projections.reduce((a: number, p: any) => a + p.risk_factors.filter((r: any) => r.severity === "critical").length, 0),
      highest_confidence_action: projections.flatMap((p: any) => p.recommended_actions).sort((a: any, b: any) => b.confidence - a.confidence)[0] || null,
    },
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// AI BRAIN — Phase 2: Autonomous Action Engine
// Evaluates guardrails, executes actions, logs everything, supports rollback.
// AI suggests → guardrails validate → Core executes → audit trail records.
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Evaluates whether an action can be executed based on guardrails.
 * Returns eligibility decision with detailed reasoning.
 */
async function evaluateActionEligibility(
  depotId: string,
  actionType: string,
  confidence: number,
): Promise<{ eligible: boolean; approval_method: string; reason: string; guardrail?: any }> {
  const guardrail = await store.getGuardrailForAction(depotId, actionType);

  // No guardrail configured — default deny
  if (!guardrail) {
    return { eligible: false, approval_method: "none", reason: `No guardrail configured for action type '${actionType}'` };
  }

  // Guardrail disabled
  if (!guardrail.enabled) {
    return { eligible: false, approval_method: "none", reason: `Action type '${actionType}' is disabled`, guardrail };
  }

  // Below minimum confidence
  if (confidence < guardrail.min_confidence) {
    return { eligible: false, approval_method: "none", reason: `Confidence ${confidence} below minimum ${guardrail.min_confidence}`, guardrail };
  }

  // Check rate limits
  const recentHour = await store.getRecentActionsByType(depotId, actionType, 1);
  if (recentHour.length >= guardrail.max_per_hour) {
    return { eligible: false, approval_method: "none", reason: `Rate limit: ${recentHour.length}/${guardrail.max_per_hour} actions this hour`, guardrail };
  }

  const recentShift = await store.getRecentActionsByType(depotId, actionType, 8);
  if (recentShift.length >= guardrail.max_per_shift) {
    return { eligible: false, approval_method: "none", reason: `Shift limit: ${recentShift.length}/${guardrail.max_per_shift} actions this shift`, guardrail };
  }

  // Check cooldown
  if (recentHour.length > 0 && guardrail.cooldown_minutes > 0) {
    const lastAction = recentHour[0];
    const msSinceLastAction = Date.now() - new Date(lastAction.created_at).getTime();
    const cooldownMs = guardrail.cooldown_minutes * 60000;
    if (msSinceLastAction < cooldownMs) {
      const remainingMin = Math.ceil((cooldownMs - msSinceLastAction) / 60000);
      return { eligible: false, approval_method: "none", reason: `Cooldown: ${remainingMin} minutes remaining before next '${actionType}' action`, guardrail };
    }
  }

  // Check blackout window
  if (guardrail.blackout_start && guardrail.blackout_end) {
    const now = new Date();
    const currentMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
    const [bsH, bsM] = guardrail.blackout_start.split(":").map(Number);
    const [beH, beM] = guardrail.blackout_end.split(":").map(Number);
    const blackoutStart = bsH * 60 + bsM;
    const blackoutEnd = beH * 60 + beM;
    if (currentMinutes >= blackoutStart && currentMinutes <= blackoutEnd) {
      return { eligible: false, approval_method: "none", reason: `Blackout window: ${guardrail.blackout_start}-${guardrail.blackout_end}`, guardrail };
    }
  }

  // Requires human approval override
  if (guardrail.requires_human_approval) {
    return { eligible: true, approval_method: "human_approved", reason: `Action '${actionType}' requires human approval (confidence: ${confidence})`, guardrail };
  }

  // Determine auto-execute vs queue for approval
  if (confidence >= guardrail.auto_execute_confidence) {
    return { eligible: true, approval_method: "auto_threshold", reason: `Auto-execute: confidence ${confidence} >= threshold ${guardrail.auto_execute_confidence}`, guardrail };
  }

  // Between min and auto-execute: queue for human approval
  return { eligible: true, approval_method: "human_approved", reason: `Queued for approval: confidence ${confidence} between ${guardrail.min_confidence} and ${guardrail.auto_execute_confidence}`, guardrail };
}

/**
 * Executes a throttle_charger action.
 * Reduces charging power on non-priority vehicles to manage demand.
 */
async function executeThrottleCharger(depotId: string, params: any): Promise<{ success: boolean; result: any; rollback_data: any }> {
  const targetReductionPct = params.target_reduction_pct || 20;
  const priorityExempt = params.priority_exempt !== false;
  const durationMinutes = params.duration_minutes || 30;

  // Get active charge sessions
  const stalls = await store.getCurrentStallStatus(depotId);
  const dcfcOccupied = stalls.filter((s: any) => s.stall_type === "dcfc" && s.status === "occupied");

  // In production: would send OCPP SetChargingProfile commands
  // For now: log the action with what would be done
  const affectedStalls = dcfcOccupied.map((s: any) => ({
    stall_id: s.id,
    stall_label: s.label,
    action: "reduce_power",
    reduction_pct: targetReductionPct,
    duration_minutes: durationMinutes,
    priority_exempt: priorityExempt,
  }));

  return {
    success: true,
    result: {
      stalls_affected: affectedStalls.length,
      target_reduction_pct: targetReductionPct,
      duration_minutes: durationMinutes,
      stalls: affectedStalls,
      note: "OCPP SetChargingProfile commands would be sent in production",
    },
    rollback_data: {
      action: "restore_full_power",
      stall_ids: affectedStalls.map((s: any) => s.stall_id),
      original_power_pct: 100,
    },
  };
}

/**
 * Executes a defer_charge action.
 * Postpones pending standard-priority charge tasks to flatten demand curve.
 */
async function executeDeferCharge(depotId: string, params: any): Promise<{ success: boolean; result: any; rollback_data: any }> {
  const deferMinutes = params.defer_minutes || 30;
  const priorityFilter = params.priority_filter || "standard";

  // Get pending charge tasks
  const tasks = await store.getCompletedTasks(depotId, 0); // Gets all tasks actually
  // In production: would update schedule_tasks.scheduled_start
  // For now: log what would be deferred

  return {
    success: true,
    result: {
      defer_minutes: deferMinutes,
      priority_filter: priorityFilter,
      note: "Pending standard charge tasks would be deferred in production schedule",
    },
    rollback_data: {
      action: "restore_original_schedule",
      defer_minutes: deferMinutes,
    },
  };
}

/**
 * Executes a resequence_queue action.
 * Reorders vehicle service queue to optimize throughput.
 */
async function executeResequenceQueue(depotId: string, params: any): Promise<{ success: boolean; result: any; rollback_data: any }> {
  const strategy = params.strategy || "free_chargers_first";
  const socThreshold = params.soc_threshold || 80;

  // Get current vehicles on chargers
  const vehicles = await store.getCurrentDepotVehicles(depotId);
  const charging = vehicles.filter((v: any) => ["charging_dcfc", "charging_l2"].includes(v.current_state));
  const highSoc = charging.filter((v: any) => (v.current_soc || 0) >= socThreshold);

  return {
    success: true,
    result: {
      strategy,
      soc_threshold: socThreshold,
      vehicles_charging: charging.length,
      vehicles_above_threshold: highSoc.length,
      vehicles_to_expedite: highSoc.map((v: any) => ({ id: v.id, name: v.display_name, soc: v.current_soc })),
      note: "Queue resequencing would move high-SOC vehicles to departure staging in production",
    },
    rollback_data: {
      action: "restore_original_queue_order",
      original_order: charging.map((v: any) => v.id),
    },
  };
}

/**
 * Executes a pre_position_stall action.
 * Reserves a stall for an anticipated vehicle arrival.
 */
async function executePrePositionStall(depotId: string, params: any): Promise<{ success: boolean; result: any; rollback_data: any }> {
  const stallType = params.stall_type || "dcfc";
  const reason = params.reason || "AI prediction — anticipated arrival";

  const stalls = await store.getCurrentStallStatus(depotId);
  const available = stalls.filter((s: any) => s.stall_type === stallType && s.status === "available");

  if (available.length === 0) {
    return {
      success: false,
      result: { error: `No available ${stallType} stalls to pre-position` },
      rollback_data: null,
    };
  }

  // Reserve the best candidate (furthest from entrance for DCFC)
  const target = stallType === "dcfc" || stallType === "l2"
    ? available.sort((a: any, b: any) => (b.distance_from_entrance || 0) - (a.distance_from_entrance || 0))[0]
    : available[0];

  await store.updateStall(target.id, { status: "reserved" });

  return {
    success: true,
    result: {
      stall_id: target.id,
      stall_label: target.label,
      stall_type: stallType,
      reason,
    },
    rollback_data: {
      action: "release_reservation",
      stall_id: target.id,
      original_status: "available",
    },
  };
}

/**
 * Executes an alert_ops action.
 * Sends notification to operations team about a risk or condition.
 */
async function executeAlertOps(depotId: string, params: any): Promise<{ success: boolean; result: any; rollback_data: any }> {
  const urgency = params.urgency || "medium";
  const message = params.message || "AI Brain detected a condition requiring attention";

  // Create notification via existing store
  await store.createNotification({
    depot_id: depotId,
    event_type: "ai_brain_alert",
    title: `AI Brain Alert [${urgency.toUpperCase()}]`,
    body: message,
    channel: "in_app",
    priority: urgency === "critical" ? "high" : "normal",
    status: "queued",
    metadata: { source: "ai_brain", urgency, action_params: params },
  });

  return {
    success: true,
    result: { urgency, message, notification_sent: true },
    rollback_data: null, // Notifications are not reversible
  };
}

/**
 * Rolls back a previously executed autonomous action.
 * Uses stored rollback_data to reverse the change.
 */
async function rollbackAutonomousAction(actionLogEntry: any): Promise<{ success: boolean; result: any }> {
  if (!actionLogEntry.rollback_data) {
    return { success: false, result: { error: "No rollback data available for this action" } };
  }

  if (actionLogEntry.rollback_performed) {
    return { success: false, result: { error: "Action has already been rolled back" } };
  }

  const rd = actionLogEntry.rollback_data;

  switch (rd.action) {
    case "release_reservation":
      await store.updateStall(rd.stall_id, { status: rd.original_status || "available" });
      break;
    case "restore_full_power":
      // In production: send OCPP SetChargingProfile to restore full power
      break;
    case "restore_original_schedule":
      // In production: restore original scheduled_start times
      break;
    case "restore_original_queue_order":
      // In production: restore original task sequence
      break;
    default:
      return { success: false, result: { error: `Unknown rollback action: ${rd.action}` } };
  }

  await store.updateActionLog(actionLogEntry.id, {
    rollback_performed: true,
    rollback_at: new Date().toISOString(),
    status: "rolled_back",
  });

  return { success: true, result: { rolled_back: rd.action, original_action_id: actionLogEntry.id } };
}

/**
 * Master action executor. Evaluates guardrails, executes, and logs everything.
 * This is the single entry point for all autonomous actions.
 */
async function executeAutonomousAction(
  depotId: string,
  predictionId: string | null,
  actionType: string,
  actionParams: any,
  confidence: number,
  riskFactors: any[],
  approvalOverride?: string,
): Promise<any> {
  const execStart = Date.now();

  // 1. Evaluate guardrails (skip if human-approved override)
  let approvalMethod = approvalOverride || "auto_threshold";
  if (!approvalOverride) {
    const eligibility = await evaluateActionEligibility(depotId, actionType, confidence);
    if (!eligibility.eligible) {
      // Log as skipped
      const skipped = await store.logAutonomousAction({
        depot_id: depotId,
        prediction_id: predictionId,
        action_type: actionType,
        action_parameters: actionParams,
        action_summary: `Skipped: ${eligibility.reason}`,
        pre_state: {},
        confidence,
        approval_method: "auto_threshold",
        status: "skipped",
        risk_factors: riskFactors,
        error_message: eligibility.reason,
      });
      return { executed: false, action_log: skipped, reason: eligibility.reason };
    }

    approvalMethod = eligibility.approval_method;

    // If human approval required, log as pending and return
    if (eligibility.approval_method === "human_approved" && !approvalOverride) {
      const pending = await store.logAutonomousAction({
        depot_id: depotId,
        prediction_id: predictionId,
        action_type: actionType,
        action_parameters: actionParams,
        action_summary: `Awaiting human approval: ${eligibility.reason}`,
        pre_state: {},
        confidence,
        approval_method: "human_approved",
        status: "pending",
        risk_factors: riskFactors,
      });

      if (predictionId) {
        await store.updatePredictionExecution(predictionId, { execution_status: "approved" });
      }

      return { executed: false, awaiting_approval: true, action_log: pending, reason: eligibility.reason };
    }
  }

  // 2. Capture pre-state snapshot
  const preSnapshot = await captureDepotSnapshot(depotId);

  // 3. Create action log entry
  const actionLog = await store.logAutonomousAction({
    depot_id: depotId,
    prediction_id: predictionId,
    action_type: actionType,
    action_parameters: actionParams,
    pre_state: { snapshot_id: preSnapshot.id, vehicles_on_site: preSnapshot.vehicles_on_site, current_demand_kw: preSnapshot.current_demand_kw, queue_depth: preSnapshot.queue_depth },
    confidence,
    approval_method: approvalMethod,
    approved_by: approvalOverride ? "human" : "system",
    status: "executing",
    risk_factors: riskFactors,
    execution_started_at: new Date().toISOString(),
  });

  // 4. Execute the action
  let execResult: { success: boolean; result: any; rollback_data: any };
  try {
    switch (actionType) {
      case "throttle_charger":
        execResult = await executeThrottleCharger(depotId, actionParams);
        break;
      case "defer_charge":
        execResult = await executeDeferCharge(depotId, actionParams);
        break;
      case "resequence_queue":
        execResult = await executeResequenceQueue(depotId, actionParams);
        break;
      case "pre_position_stall":
        execResult = await executePrePositionStall(depotId, actionParams);
        break;
      case "alert_ops":
        execResult = await executeAlertOps(depotId, actionParams);
        break;
      default:
        execResult = { success: false, result: { error: `Unknown action type: ${actionType}` }, rollback_data: null };
    }
  } catch (e: any) {
    // Execution failed
    await store.updateActionLog(actionLog.id, {
      status: "failed",
      execution_completed_at: new Date().toISOString(),
      execution_duration_ms: Date.now() - execStart,
      error_message: e.message || String(e),
    });

    if (predictionId) {
      await store.updatePredictionExecution(predictionId, { execution_status: "failed" });
    }

    return { executed: false, action_log: actionLog, error: e.message };
  }

  // 5. Update action log with result
  const finalStatus = execResult.success ? "completed" : "failed";
  await store.updateActionLog(actionLog.id, {
    status: finalStatus,
    action_summary: execResult.success
      ? `Executed ${actionType}: ${JSON.stringify(execResult.result).substring(0, 200)}`
      : `Failed: ${execResult.result?.error || "Unknown error"}`,
    post_state: execResult.result,
    rollback_data: execResult.rollback_data,
    execution_completed_at: new Date().toISOString(),
    execution_duration_ms: Date.now() - execStart,
    error_message: execResult.success ? null : (execResult.result?.error || null),
  });

  // 6. Update prediction status
  if (predictionId) {
    await store.updatePredictionExecution(predictionId, {
      execution_status: execResult.success ? "executed" : "failed",
      executed_at: new Date().toISOString(),
      executed_by: approvalMethod,
    });
  }

  return {
    executed: execResult.success,
    action_log_id: actionLog.id,
    action_type: actionType,
    result: execResult.result,
    rollback_available: !!execResult.rollback_data,
    execution_ms: Date.now() - execStart,
  };
}

/**
 * Runs a full autonomous prediction-and-action cycle.
 * 1. Run prediction cycle (Phase 1)
 * 2. For each recommended action, evaluate guardrails
 * 3. Auto-execute eligible actions, queue others for approval
 * Returns complete cycle results.
 */
async function runAutonomousCycle(depotId: string): Promise<any> {
  const cycleStart = Date.now();

  // 1. Run prediction cycle
  const predictionResult = await runPredictionCycle(depotId);

  // 2. Collect all recommended actions across all horizons
  const allActions: any[] = [];
  for (const projection of predictionResult.projections) {
    for (const action of projection.recommended_actions) {
      allActions.push({
        ...action,
        horizon_hours: projection.horizon_hours,
        risk_factors: projection.risk_factors,
      });
    }
  }

  // 3. Deduplicate actions (same action_type with similar parameters)
  const seen = new Set<string>();
  const uniqueActions = allActions.filter(a => {
    const key = `${a.action_type}:${JSON.stringify(a.parameters)}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  // 4. Execute each action through the guardrails
  const actionResults: any[] = [];
  for (const action of uniqueActions) {
    // Find the prediction ID for this action (if one was written)
    const predictions = await store.getAIPredictions(depotId, {
      action_type: action.action_type,
      execution_status: "pending",
      limit: 1,
    });
    const predictionId = predictions[0]?.id || null;

    const result = await executeAutonomousAction(
      depotId,
      predictionId,
      action.action_type,
      action.parameters,
      action.confidence,
      action.risk_factors || [],
    );
    actionResults.push(result);
  }

  return {
    depot_id: depotId,
    cycle_timestamp: new Date().toISOString(),
    processing_ms: Date.now() - cycleStart,
    prediction_summary: predictionResult.summary,
    actions_evaluated: uniqueActions.length,
    actions_executed: actionResults.filter(r => r.executed).length,
    actions_awaiting_approval: actionResults.filter(r => r.awaiting_approval).length,
    actions_skipped: actionResults.filter(r => !r.executed && !r.awaiting_approval).length,
    action_results: actionResults,
  };
}

// ===========================================================================
// PHASE 3: LEARNING FEEDBACK LOOP — Engine Functions
// ===========================================================================

// ---------------------------------------------------------------------------
// scorePrediction() — Computes accuracy of a single prediction vs reality
// Supports multiple scoring methods based on prediction type.
// ---------------------------------------------------------------------------
async function scorePrediction(
  predictionId: string,
  depotId: string,
  predictedValue: any,
  actualValue: any,
  predictionType: string,
  timeHorizonHours: number,
): Promise<any> {
  let accuracyScore = 0;
  let scoringMethod = "exact_match";

  switch (predictionType) {
    case "charge_duration":
    case "service_duration": {
      // MAPE-based scoring: how close was the predicted duration to actual?
      scoringMethod = "mape";
      const predicted = predictedValue.duration_minutes || predictedValue.estimated_minutes || 0;
      const actual = actualValue.duration_minutes || actualValue.actual_minutes || 0;
      if (actual > 0) {
        const mape = Math.abs(predicted - actual) / actual;
        accuracyScore = Math.max(0, Math.min(1, 1 - mape));
      } else {
        accuracyScore = predicted === 0 ? 1.0 : 0.0;
      }
      break;
    }

    case "demand_peak": {
      // Range check: was actual peak within predicted confidence interval?
      scoringMethod = "range_check";
      const predictedPeak = predictedValue.peak_kw || 0;
      const actualPeak = actualValue.peak_kw || 0;
      const margin = predictedValue.margin_kw || predictedPeak * 0.15;
      if (Math.abs(predictedPeak - actualPeak) <= margin) {
        accuracyScore = 1.0;
      } else {
        // Partial credit: how far outside the range?
        const overshoot = Math.abs(predictedPeak - actualPeak) - margin;
        accuracyScore = Math.max(0, 1 - (overshoot / (predictedPeak || 1)));
      }
      break;
    }

    case "vehicle_arrival": {
      // Directional + MAPE: did they arrive early/late as predicted, and by how much?
      scoringMethod = "mape";
      const predictedMin = predictedValue.eta_minutes || 0;
      const actualMin = actualValue.arrival_minutes || 0;
      if (actualMin > 0) {
        const mape = Math.abs(predictedMin - actualMin) / actualMin;
        accuracyScore = Math.max(0, Math.min(1, 1 - mape));
      } else {
        accuracyScore = 0.5; // Vehicle didn't arrive — uncertain score
      }
      break;
    }

    case "depot_projection":
    case "risk_assessment": {
      // RMSE normalized: compare projected state vector vs actual
      scoringMethod = "rmse_normalized";
      const fields = ["vehicles_on_site", "vehicles_charging", "queue_depth", "current_demand_kw"];
      let sumSquaredError = 0;
      let sumActual = 0;
      let fieldCount = 0;
      for (const field of fields) {
        if (predictedValue[field] !== undefined && actualValue[field] !== undefined) {
          const diff = (predictedValue[field] || 0) - (actualValue[field] || 0);
          sumSquaredError += diff * diff;
          sumActual += Math.abs(actualValue[field] || 0);
          fieldCount++;
        }
      }
      if (fieldCount > 0 && sumActual > 0) {
        const rmse = Math.sqrt(sumSquaredError / fieldCount);
        accuracyScore = Math.max(0, Math.min(1, 1 - (rmse / (sumActual / fieldCount))));
      } else {
        accuracyScore = 0.5; // Insufficient data for comparison
      }
      break;
    }

    case "stall_bottleneck":
    case "exception_surge": {
      // Directional: did we predict the right direction of change?
      scoringMethod = "directional";
      const predictedDirection = predictedValue.direction || predictedValue.will_occur;
      const actualDirection = actualValue.direction || actualValue.did_occur;
      accuracyScore = predictedDirection === actualDirection ? 1.0 : 0.0;
      break;
    }

    default: {
      // Exact match fallback
      scoringMethod = "exact_match";
      accuracyScore = JSON.stringify(predictedValue) === JSON.stringify(actualValue) ? 1.0 : 0.0;
    }
  }

  // Round to 4 decimal places
  accuracyScore = Math.round(accuracyScore * 10000) / 10000;

  // Store the outcome
  const outcome = await store.recordPredictionOutcome({
    prediction_id: predictionId,
    depot_id: depotId,
    predicted_value: predictedValue,
    actual_value: actualValue,
    accuracy_score: accuracyScore,
    scoring_method: scoringMethod,
    time_horizon_hours: timeHorizonHours,
    prediction_type: predictionType,
  });

  return {
    outcome_id: outcome.id,
    accuracy_score: accuracyScore,
    scoring_method: scoringMethod,
    prediction_type: predictionType,
    time_horizon_hours: timeHorizonHours,
  };
}


// ---------------------------------------------------------------------------
// evaluateModelPerformance() — Aggregates outcomes, computes accuracy trends
// ---------------------------------------------------------------------------
async function evaluateModelPerformance(
  depotId: string,
  parameterGroup?: string,
  windowDays: number = 7,
): Promise<any> {
  const endDate = new Date().toISOString();
  const startDate = new Date(Date.now() - windowDays * 86400000).toISOString();

  const outcomes = await store.getPredictionOutcomesByDateRange(
    depotId, startDate, endDate, parameterGroup,
  );

  if (outcomes.length === 0) {
    return {
      depot_id: depotId,
      parameter_group: parameterGroup || "all",
      window_days: windowDays,
      status: "insufficient_data",
      samples: 0,
      message: "No scored predictions in the evaluation window",
    };
  }

  // Compute accuracy statistics
  const scores = outcomes.map((o: any) => o.accuracy_score);
  const sorted = [...scores].sort((a, b) => a - b);
  const sum = scores.reduce((a: number, b: number) => a + b, 0);
  const mean = sum / scores.length;
  const median = scores.length % 2 === 0
    ? (sorted[scores.length / 2 - 1] + sorted[scores.length / 2]) / 2
    : sorted[Math.floor(scores.length / 2)];
  const variance = scores.reduce((a: number, b: number) => a + (b - mean) ** 2, 0) / scores.length;
  const stdDev = Math.sqrt(variance);

  // Compute MAPE for applicable outcomes
  const mapeOutcomes = outcomes.filter((o: any) => o.scoring_method === "mape");
  const mape = mapeOutcomes.length > 0
    ? mapeOutcomes.reduce((a: number, o: any) => a + (1 - o.accuracy_score), 0) / mapeOutcomes.length
    : null;

  // Directional accuracy
  const directionalOutcomes = outcomes.filter((o: any) => o.scoring_method === "directional");
  const directionalAccuracy = directionalOutcomes.length > 0
    ? directionalOutcomes.filter((o: any) => o.accuracy_score === 1.0).length / directionalOutcomes.length
    : null;

  // Group by prediction type
  const byType: Record<string, { count: number; mean: number; scores: number[] }> = {};
  for (const o of outcomes) {
    if (!byType[o.prediction_type]) byType[o.prediction_type] = { count: 0, mean: 0, scores: [] };
    byType[o.prediction_type].count++;
    byType[o.prediction_type].scores.push(o.accuracy_score);
  }
  for (const t of Object.keys(byType)) {
    byType[t].mean = byType[t].scores.reduce((a, b) => a + b, 0) / byType[t].scores.length;
    byType[t].mean = Math.round(byType[t].mean * 10000) / 10000;
  }

  // Group by time horizon
  const byHorizon: Record<string, { count: number; mean: number; scores: number[] }> = {};
  for (const o of outcomes) {
    const h = `${o.time_horizon_hours}h`;
    if (!byHorizon[h]) byHorizon[h] = { count: 0, mean: 0, scores: [] };
    byHorizon[h].count++;
    byHorizon[h].scores.push(o.accuracy_score);
  }
  for (const h of Object.keys(byHorizon)) {
    byHorizon[h].mean = byHorizon[h].scores.reduce((a, b) => a + b, 0) / byHorizon[h].scores.length;
    byHorizon[h].mean = Math.round(byHorizon[h].mean * 10000) / 10000;
  }

  // Trend detection: split window in half, compare means
  const halfIdx = Math.floor(outcomes.length / 2);
  const olderHalf = outcomes.slice(halfIdx);
  const newerHalf = outcomes.slice(0, halfIdx);
  const olderMean = olderHalf.length > 0
    ? olderHalf.reduce((a: number, o: any) => a + o.accuracy_score, 0) / olderHalf.length : 0;
  const newerMean = newerHalf.length > 0
    ? newerHalf.reduce((a: number, o: any) => a + o.accuracy_score, 0) / newerHalf.length : 0;

  let trendDirection = "stable";
  const trendDelta = newerMean - olderMean;
  if (outcomes.length < 10) trendDirection = "insufficient_data";
  else if (trendDelta > 0.03) trendDirection = "improving";
  else if (trendDelta < -0.03) trendDirection = "declining";

  // Linear regression slope for trend
  let trendSlope = 0;
  if (outcomes.length >= 5) {
    const n = outcomes.length;
    let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (let i = 0; i < n; i++) {
      sumX += i;
      sumY += outcomes[n - 1 - i].accuracy_score;  // Chronological order
      sumXY += i * outcomes[n - 1 - i].accuracy_score;
      sumX2 += i * i;
    }
    trendSlope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    trendSlope = Math.round(trendSlope * 1000000) / 1000000;
  }

  return {
    depot_id: depotId,
    parameter_group: parameterGroup || "all",
    window_days: windowDays,
    samples: outcomes.length,
    accuracy: {
      mean: Math.round(mean * 10000) / 10000,
      median: Math.round(median * 10000) / 10000,
      min: Math.round(sorted[0] * 10000) / 10000,
      max: Math.round(sorted[sorted.length - 1] * 10000) / 10000,
      std_deviation: Math.round(stdDev * 10000) / 10000,
    },
    mape: mape !== null ? Math.round(mape * 10000) / 10000 : null,
    directional_accuracy: directionalAccuracy !== null
      ? Math.round(directionalAccuracy * 10000) / 10000 : null,
    by_prediction_type: Object.fromEntries(
      Object.entries(byType).map(([k, v]) => [k, { count: v.count, mean_accuracy: v.mean }])
    ),
    by_time_horizon: Object.fromEntries(
      Object.entries(byHorizon).map(([k, v]) => [k, { count: v.count, mean_accuracy: v.mean }])
    ),
    trend: {
      direction: trendDirection,
      slope: trendSlope,
      older_half_mean: Math.round(olderMean * 10000) / 10000,
      newer_half_mean: Math.round(newerMean * 10000) / 10000,
      delta: Math.round(trendDelta * 10000) / 10000,
    },
  };
}


// ---------------------------------------------------------------------------
// tuneModelParameters() — Auto-tuning via gradient-free optimization
// Uses Nelder-Mead simplex-inspired approach: adjusts weights based on
// which parameters correlate with higher/lower accuracy outcomes.
// ---------------------------------------------------------------------------
async function tuneModelParameters(
  depotId: string,
  parameterGroup: string,
  triggerType: string = "scheduled",
): Promise<any> {
  const tuneStart = Date.now();

  // 1. Get current model parameters
  const currentParams = await store.getModelParameters(depotId, parameterGroup);
  if (!currentParams) {
    return { success: false, error: `No model parameters found for group '${parameterGroup}'` };
  }

  // 2. Evaluate current performance
  const performance = await evaluateModelPerformance(depotId, parameterGroup, 7);
  if (performance.status === "insufficient_data" || performance.samples < 10) {
    return {
      success: false,
      reason: "insufficient_data",
      samples: performance.samples,
      message: `Need at least 10 scored predictions, have ${performance.samples}`,
    };
  }

  // 3. Create tuning run record
  const tuningRun = await store.createTuningRun({
    depot_id: depotId,
    parameter_group: parameterGroup,
    trigger_type: triggerType,
    parameters_before: currentParams.parameters,
    parameters_after: currentParams.parameters,  // Will update after tuning
    parameter_diffs: [],
    accuracy_before: performance.accuracy.mean,
    samples_evaluated: performance.samples,
    evaluation_window_hours: 168,
    tuning_method: "gradient_free",
    status: "running",
  });

  try {
    // 4. Compute parameter adjustments based on accuracy gradient
    const newParameters = { ...currentParams.parameters };
    const diffs: any[] = [];

    // Adjustment strategy: tune weights based on trend direction
    const adjustmentFactor = performance.trend.direction === "declining" ? 0.05 : 0.02;

    // Tune primary weights
    const tuneableWeights = [
      "history_weight", "theoretical_weight", "time_of_day_weight",
      "day_of_week_weight", "recent_trend_weight", "schedule_weight",
      "historical_pattern_weight", "telemetry_weight", "current_trend_weight",
      "schedule_projection_weight", "historical_peak_weight",
    ];

    for (const key of tuneableWeights) {
      if (newParameters[key] !== undefined) {
        const oldVal = newParameters[key];
        // If accuracy is declining, increase history weight (trust data more)
        // If improving, make smaller adjustments toward current trajectory
        let delta = 0;
        if (key.includes("history") || key.includes("historical")) {
          delta = performance.trend.direction === "declining" ? adjustmentFactor : -adjustmentFactor * 0.5;
        } else if (key.includes("theoretical") || key.includes("schedule")) {
          delta = performance.trend.direction === "declining" ? -adjustmentFactor : adjustmentFactor * 0.5;
        } else {
          // Slight regression toward mean for other weights
          delta = (0.33 - oldVal) * adjustmentFactor;
        }

        const newVal = Math.max(0.05, Math.min(0.95, oldVal + delta));
        if (Math.abs(newVal - oldVal) > 0.001) {
          newParameters[key] = Math.round(newVal * 1000) / 1000;
          diffs.push({
            key,
            before: oldVal,
            after: newParameters[key],
            delta: Math.round((newParameters[key] - oldVal) * 1000) / 1000,
          });
        }
      }
    }

    // Tune confidence floor based on observed accuracy
    if (newParameters.confidence_floor !== undefined) {
      const oldFloor = newParameters.confidence_floor;
      // Lower floor if accuracy is consistently high, raise if declining
      const newFloor = performance.accuracy.mean > 0.85
        ? Math.max(0.30, oldFloor - 0.02)
        : Math.min(0.70, oldFloor + 0.02);
      if (Math.abs(newFloor - oldFloor) > 0.001) {
        newParameters.confidence_floor = Math.round(newFloor * 100) / 100;
        diffs.push({ key: "confidence_floor", before: oldFloor, after: newParameters.confidence_floor, delta: Math.round((newParameters.confidence_floor - oldFloor) * 100) / 100 });
      }
    }

    // Normalize weight groups that must sum to ~1.0
    const weightGroups = [
      ["history_weight", "theoretical_weight"],
      ["time_of_day_weight", "day_of_week_weight", "recent_trend_weight"],
      ["schedule_weight", "historical_pattern_weight", "telemetry_weight"],
      ["historical_peak_weight", "current_trend_weight", "schedule_projection_weight"],
    ];

    for (const group of weightGroups) {
      const present = group.filter(k => newParameters[k] !== undefined);
      if (present.length >= 2) {
        const sum = present.reduce((a, k) => a + newParameters[k], 0);
        if (Math.abs(sum - 1.0) > 0.01) {
          // Normalize
          for (const k of present) {
            newParameters[k] = Math.round((newParameters[k] / sum) * 1000) / 1000;
          }
        }
      }
    }

    // 5. Update model parameters
    if (diffs.length > 0) {
      await store.updateModelParameters(depotId, parameterGroup, {
        parameters: newParameters,
        version: (currentParams.version || 1) + 1,
        last_tuned_at: new Date().toISOString(),
        tuned_by: "auto_learning_loop",
        performance_metrics: {
          mape: performance.mape,
          accuracy_7d: performance.accuracy.mean,
          samples_evaluated: performance.samples,
          trend: performance.trend.direction,
          last_tuned: new Date().toISOString(),
        },
      });
    }

    // 6. Update tuning run
    await store.updateTuningRun(tuningRun.id, {
      parameters_after: newParameters,
      parameter_diffs: diffs,
      status: diffs.length > 0 ? "evaluating" : "completed",
      duration_ms: Date.now() - tuneStart,
      notes: diffs.length > 0
        ? `Adjusted ${diffs.length} parameters. Evaluating impact.`
        : "No adjustments needed — parameters within optimal range.",
    });

    return {
      success: true,
      tuning_run_id: tuningRun.id,
      parameter_group: parameterGroup,
      adjustments: diffs.length,
      diffs,
      accuracy_before: performance.accuracy.mean,
      trend: performance.trend.direction,
      new_version: (currentParams.version || 1) + (diffs.length > 0 ? 1 : 0),
      duration_ms: Date.now() - tuneStart,
    };
  } catch (error: any) {
    await store.updateTuningRun(tuningRun.id, {
      status: "failed",
      error_message: error.message,
      duration_ms: Date.now() - tuneStart,
    });
    throw error;
  }
}


// ---------------------------------------------------------------------------
// detectAccuracyDrift() — Monitors for sustained accuracy drops
// Compares recent accuracy (last 24h) against baseline (7d rolling).
// Triggers tuning if drift exceeds threshold.
// ---------------------------------------------------------------------------
async function detectAccuracyDrift(depotId: string): Promise<any> {
  const driftResults: any[] = [];

  // Get model parameters to know which groups to check
  const params = await store.getAllModelParameters(depotId);
  if (!params || params.length === 0) {
    return { depot_id: depotId, checked_at: new Date().toISOString(), groups_checked: 0, groups_with_drift: 0, tuning_triggered: 0, details: [], message: "No model parameters configured" };
  }
  const groups = params.map((p: any) => p.parameter_group);

  for (const group of groups) {
    // Compare 24h vs 7d performance
    const recent = await evaluateModelPerformance(depotId, group, 1);
    const baseline = await evaluateModelPerformance(depotId, group, 7);

    if (recent.status === "insufficient_data" || baseline.status === "insufficient_data") {
      driftResults.push({
        parameter_group: group,
        status: "insufficient_data",
        message: `Recent: ${recent.samples} samples, Baseline: ${baseline.samples} samples`,
      });
      continue;
    }

    const drift = baseline.accuracy.mean - recent.accuracy.mean;
    const driftPct = baseline.accuracy.mean > 0 ? (drift / baseline.accuracy.mean) * 100 : 0;
    const driftRounded = Math.round(driftPct * 100) / 100;

    let action = "none";
    let triggered = false;

    if (driftRounded > 10) {
      // Critical drift — trigger immediate tuning
      action = "immediate_tuning";
      triggered = true;
      try {
        await tuneModelParameters(depotId, group, "accuracy_drift");
      } catch (_e) {
        action = "tuning_failed";
      }
    } else if (driftRounded > 5) {
      // Warning drift — schedule tuning
      action = "scheduled_tuning";
      triggered = true;
    } else if (driftRounded > 2) {
      // Minor drift — monitoring
      action = "monitoring";
    }

    driftResults.push({
      parameter_group: group,
      recent_accuracy: recent.accuracy.mean,
      baseline_accuracy: baseline.accuracy.mean,
      drift_pct: driftRounded,
      recent_samples: recent.samples,
      baseline_samples: baseline.samples,
      trend: recent.trend?.direction || "unknown",
      action,
      tuning_triggered: triggered,
    });
  }

  return {
    depot_id: depotId,
    checked_at: new Date().toISOString(),
    groups_checked: driftResults.length,
    groups_with_drift: driftResults.filter(d => d.drift_pct > 2).length,
    tuning_triggered: driftResults.filter(d => d.tuning_triggered).length,
    details: driftResults,
  };
}


// ---------------------------------------------------------------------------
// generateDailyAccuracyReport() — Nightly aggregation for dashboards
// Creates one row per depot + prediction_type + time_horizon per day.
// Also computes rolling averages and trend indicators.
// ---------------------------------------------------------------------------
async function generateDailyAccuracyReport(
  depotId: string,
  reportDate?: string,
): Promise<any> {
  const reportStart = Date.now();
  const date = reportDate || new Date(Date.now() - 86400000).toISOString().split("T")[0];
  const dayStart = `${date}T00:00:00.000Z`;
  const dayEnd = `${date}T23:59:59.999Z`;

  // 1. Get all scored outcomes for this day
  const outcomes = await store.getPredictionOutcomesByDateRange(depotId, dayStart, dayEnd);

  if (outcomes.length === 0) {
    return {
      depot_id: depotId,
      report_date: date,
      status: "no_data",
      message: "No scored predictions for this date",
    };
  }

  // 2. Group by prediction_type + time_horizon
  const groups: Record<string, any[]> = {};
  for (const o of outcomes) {
    const key = `${o.prediction_type}__${o.time_horizon_hours || "all"}`;
    if (!groups[key]) groups[key] = [];
    groups[key].push(o);
  }

  // 3. Also create an "all types combined" group per horizon
  const allCombined: Record<string, any[]> = {};
  for (const o of outcomes) {
    const key = `__combined__${o.time_horizon_hours || "all"}`;
    if (!allCombined[key]) allCombined[key] = [];
    allCombined[key].push(o);
  }

  const records: any[] = [];

  // 4. Process each group
  for (const [key, groupOutcomes] of Object.entries({ ...groups, ...allCombined })) {
    const [predType, horizon] = key.startsWith("__combined__")
      ? ["all_combined", key.replace("__combined__", "")]
      : key.split("__");
    const timeHorizon = horizon === "all" ? null : parseInt(horizon);

    const scores = groupOutcomes.map((o: any) => o.accuracy_score);
    const sorted = [...scores].sort((a, b) => a - b);
    const mean = scores.reduce((a: number, b: number) => a + b, 0) / scores.length;
    const median = scores.length % 2 === 0
      ? (sorted[scores.length / 2 - 1] + sorted[scores.length / 2]) / 2
      : sorted[Math.floor(scores.length / 2)];
    const variance = scores.reduce((a: number, b: number) => a + (b - mean) ** 2, 0) / scores.length;

    // MAPE
    const mapeScores = groupOutcomes
      .filter((o: any) => o.scoring_method === "mape")
      .map((o: any) => 1 - o.accuracy_score);
    const mape = mapeScores.length > 0
      ? mapeScores.reduce((a: number, b: number) => a + b, 0) / mapeScores.length : null;

    // Directional accuracy
    const dirScores = groupOutcomes.filter((o: any) => o.scoring_method === "directional");
    const dirAccuracy = dirScores.length > 0
      ? dirScores.filter((o: any) => o.accuracy_score === 1.0).length / dirScores.length : null;

    // Get rolling averages from previous daily records
    const prevRecords = await store.getDailyAccuracy(depotId, {
      prediction_type: predType,
      days: 30,
      time_horizon: timeHorizon || undefined,
    });

    const prev7d = prevRecords.filter((r: any) => {
      const d = new Date(r.report_date);
      return d >= new Date(Date.now() - 7 * 86400000);
    });
    const prev30d = prevRecords;

    const avg7d = prev7d.length > 0
      ? prev7d.reduce((a: number, r: any) => a + (r.mean_accuracy || 0), 0) / prev7d.length : mean;
    const avg30d = prev30d.length > 0
      ? prev30d.reduce((a: number, r: any) => a + (r.mean_accuracy || 0), 0) / prev30d.length : mean;

    // Trend: compare this week vs last week
    let trendDirection = "insufficient_data";
    let trendSlope = 0;
    if (prev7d.length >= 3) {
      const recentAvg = prev7d.slice(0, Math.ceil(prev7d.length / 2))
        .reduce((a: number, r: any) => a + (r.mean_accuracy || 0), 0) / Math.ceil(prev7d.length / 2);
      const olderAvg = prev7d.slice(Math.ceil(prev7d.length / 2))
        .reduce((a: number, r: any) => a + (r.mean_accuracy || 0), 0) / Math.floor(prev7d.length / 2);
      const delta = recentAvg - olderAvg;
      trendDirection = delta > 0.02 ? "improving" : delta < -0.02 ? "declining" : "stable";
      trendSlope = Math.round(delta * 10000) / 10000;
    }

    // Get action stats for the day
    const actions = await store.getActionLog(depotId, { since: dayStart });
    const dayActions = actions.filter((a: any) => a.created_at <= dayEnd);
    const actionsTaken = dayActions.length;
    const actionsSuccessful = dayActions.filter((a: any) => a.status === "completed").length;
    const actionsRolledBack = dayActions.filter((a: any) => a.status === "rolled_back").length;

    // Get current model version
    const relevantParams = await store.getModelParameters(depotId, predType);

    const record = {
      depot_id: depotId,
      report_date: date,
      prediction_type: predType,
      time_horizon_hours: timeHorizon,
      total_predictions: groupOutcomes.length,
      scored_predictions: scores.length,
      mean_accuracy: Math.round(mean * 10000) / 10000,
      median_accuracy: Math.round(median * 10000) / 10000,
      min_accuracy: Math.round(sorted[0] * 10000) / 10000,
      max_accuracy: Math.round(sorted[sorted.length - 1] * 10000) / 10000,
      std_deviation: Math.round(Math.sqrt(variance) * 10000) / 10000,
      mape: mape !== null ? Math.round(mape * 10000) / 10000 : null,
      rmse: null,  // Computed when we have numeric error data
      directional_accuracy: dirAccuracy !== null ? Math.round(dirAccuracy * 10000) / 10000 : null,
      accuracy_7d_avg: Math.round(avg7d * 10000) / 10000,
      accuracy_30d_avg: Math.round(avg30d * 10000) / 10000,
      trend_direction: trendDirection,
      trend_slope: trendSlope,
      actions_taken: actionsTaken,
      actions_successful: actionsSuccessful,
      actions_rolled_back: actionsRolledBack,
      action_success_rate: actionsTaken > 0
        ? Math.round((actionsSuccessful / actionsTaken) * 10000) / 10000 : null,
      model_version: relevantParams?.version || null,
      parameters_hash: relevantParams ? JSON.stringify(relevantParams.parameters).length.toString() : null,
    };

    try {
      await store.upsertDailyAccuracy(record);
      records.push(record);
    } catch (e: any) {
      records.push({ ...record, error: e.message });
    }
  }

  // 5. Run drift detection
  const driftCheck = await detectAccuracyDrift(depotId);

  return {
    depot_id: depotId,
    report_date: date,
    records_generated: records.length,
    total_predictions_scored: outcomes.length,
    drift_check: {
      groups_with_drift: driftCheck.groups_with_drift,
      tuning_triggered: driftCheck.tuning_triggered,
    },
    records: records.map(r => ({
      prediction_type: r.prediction_type,
      time_horizon: r.time_horizon_hours,
      predictions: r.scored_predictions,
      accuracy: r.mean_accuracy,
      trend: r.trend_direction,
    })),
    processing_ms: Date.now() - reportStart,
  };
}


// ---------------------------------------------------------------------------
// Stub adapters (real adapters need API keys configured)
// ---------------------------------------------------------------------------
const dispatchers = new Map();
const ocppGateway = {};
const bessAdapter = {
  async getSnapshot(depotId: string) {
    return store.getLatestBESSSnapshot(depotId);
  },
};

// ---------------------------------------------------------------------------
// Engine config loader
// ---------------------------------------------------------------------------
async function loadEngineConfig(depotId: string) {
  const { data } = await supabase.from("engine_config").select("*").eq("depot_id", depotId).single();
  return data || {};
}

// ---------------------------------------------------------------------------
// Correlation ID generator
// ---------------------------------------------------------------------------
let corrCounter = 0;
function correlationId(): string {
  return `ottoq-${Date.now()}-${++corrCounter}`;
}

// ---------------------------------------------------------------------------
// JSON response helper
// ---------------------------------------------------------------------------
function json(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "X-OTTO-Q-Version": "2.0",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, X-OTTO-Q-API-Key",
    },
  });
}

function ok(data: any, startTime?: number) {
  return json({
    data,
    meta: {
      request_id: correlationId(),
      timestamp: new Date().toISOString(),
      processing_ms: startTime ? Date.now() - startTime : 0,
    },
  });
}

function err(code: string, message: string, status: number, details?: any) {
  return json({ error: { code, message, details, correlation_id: correlationId() } }, status);
}

// ---------------------------------------------------------------------------
// Scheduling-intelligence helpers (P3c)
// ---------------------------------------------------------------------------

/**
 * Categorize a prediction type into a UI-friendly scheduling category.
 * Used by Orchestra's Fleet Scheduling tile to group recommendations.
 */
function categorizeScheduling(predictionType: string): string {
  const map: Record<string, string> = {
    arrival_time_adjustment: "timing",
    wave_rebalancing: "load_balancing",
    soc_target_optimization: "energy_policy",
    demand_forecast: "energy_policy",
    stall_utilization: "capacity",
    service_duration_update: "capacity",
    maintenance_prediction: "health",
  };
  return map[predictionType] || "other";
}

/**
 * Categorize an autonomous action type into a UI-friendly scheduling category.
 */
function categorizeAction(actionType: string): string {
  const map: Record<string, string> = {
    resequence_queue: "timing",
    pre_position_stall: "capacity",
    throttle_charger: "energy_policy",
    trigger_early_recall: "timing",
    adjust_wave: "timing",
    defer_charge: "energy_policy",
    expedite_service: "capacity",
    alert_ops: "notification",
  };
  return map[actionType] || "other";
}

/**
 * Extract risk factor tags from a prediction's supporting_data JSONB.
 * Expected shape (consumed when present, empty when absent):
 *   { risk_factors: ["grid_peak", "high_demand", "low_soc"], ... }
 */
function extractRiskFactors(supportingData: any): string[] {
  if (!supportingData || typeof supportingData !== "object") return [];
  const factors = supportingData.risk_factors;
  if (Array.isArray(factors)) return factors.filter((f: any) => typeof f === "string");
  return [];
}

// ===========================================================================
// PROGRESSION CONTROL ENGINE
// ---------------------------------------------------------------------------
// Handles task-complete → next-stall automation with four priority-ordered
// gates:
//   1. Blocking exception  (abnormality_blocked)
//   2. Tech override       (tech_override_*)
//   3. OEM acceptance gate (oem_gate_pending — final-only by default)
//   4. Overnight staging   (overnight_staged → scheduled_release_fired)
//
// Every branch writes an append-only row to progression_decisions with an
// audit_note so the post-visit report can explain every deviation.
// ===========================================================================

type ProgressionDecision =
  | "auto_advanced" | "all_services_complete"
  | "oem_gate_pending" | "oem_accepted" | "oem_rejected"
  | "oem_timeout_auto_accepted" | "oem_timeout_held" | "oem_timeout_escalated"
  | "oem_flagged_mid_flow"
  | "tech_override_skip" | "tech_override_reroute" | "tech_override_hold"
  | "tech_override_defer" | "tech_override_flag_exception" | "tech_override_escalate"
  | "abnormality_blocked" | "abnormality_resolved"
  | "held_stall_unavailable"
  | "overnight_staged" | "scheduled_release_fired" | "scheduled_release_deferred";

async function logProgressionDecision(params: {
  vehicle_id: string;
  task_id?: string | null;
  schedule_id?: string | null;
  depot_id: string;
  fleet_operator_id?: string | null;
  decision: ProgressionDecision;
  triggered_by: string;
  triggered_by_id?: string | null;
  from_stall_id?: string | null;
  to_stall_id?: string | null;
  from_task_sequence?: number | null;
  to_task_sequence?: number | null;
  audit_note?: string | null;
  latency_ms?: number | null;
  payload?: any;
}): Promise<string | null> {
  const { data, error } = await supabase.from("progression_decisions").insert({
    vehicle_id: params.vehicle_id,
    task_id: params.task_id ?? null,
    schedule_id: params.schedule_id ?? null,
    depot_id: params.depot_id,
    fleet_operator_id: params.fleet_operator_id ?? null,
    decision: params.decision,
    triggered_by: params.triggered_by,
    triggered_by_id: params.triggered_by_id ?? null,
    from_stall_id: params.from_stall_id ?? null,
    to_stall_id: params.to_stall_id ?? null,
    from_task_sequence: params.from_task_sequence ?? null,
    to_task_sequence: params.to_task_sequence ?? null,
    audit_note: params.audit_note ?? null,
    latency_ms: params.latency_ms ?? null,
    payload: params.payload || {},
  }).select("id").single();
  if (error) {
    console.error("[progression] logProgressionDecision failed:", error.message);
    return null;
  }
  return data?.id ?? null;
}

async function getBlockingException(
  vehicleId: string,
  stage: "next_stall" | "next_service" | "redeployment" = "next_stall",
): Promise<{ exception_id: string; exception_type: string; severity: string; required_resolver_role: string | null; audit_note: string | null } | null> {
  const { data, error } = await supabase.rpc("has_blocking_exception", {
    p_vehicle_id: vehicleId,
    p_stage: stage,
  });
  if (error || !data || data.length === 0) return null;
  const row = data[0];
  if (!row.has_block) return null;
  return {
    exception_id: row.exception_id,
    exception_type: row.exception_type,
    severity: row.severity,
    required_resolver_role: row.required_resolver_role,
    audit_note: row.audit_note,
  };
}

async function getOemGatePolicy(taskId: string): Promise<{
  triggers_gate: boolean;
  mode: string;
  timeout_seconds: number;
  on_timeout: string;
  is_final_stage: boolean;
} | null> {
  const { data, error } = await supabase.rpc("does_task_trigger_oem_gate", { p_task_id: taskId });
  if (error || !data || data.length === 0) return null;
  return data[0];
}

async function getNextPendingTask(
  scheduleId: string,
  afterSequence: number,
): Promise<any | null> {
  const { data } = await supabase.from("schedule_tasks")
    .select("*")
    .eq("vehicle_schedule_id", scheduleId)
    .gt("sequence_order", afterSequence)
    .in("status", ["pending", "vehicle_en_route"])
    .order("sequence_order", { ascending: true })
    .limit(1);
  return (data && data[0]) || null;
}

async function getAllTasksForSchedule(scheduleId: string): Promise<any[]> {
  const { data } = await supabase.from("schedule_tasks")
    .select("*")
    .eq("vehicle_schedule_id", scheduleId)
    .order("sequence_order", { ascending: true });
  return data || [];
}

async function getStallAvailability(stallId: string): Promise<boolean> {
  const { data } = await supabase.from("stalls").select("status, current_vehicle_id").eq("id", stallId).single();
  if (!data) return false;
  return data.status === "available" && !data.current_vehicle_id;
}

// -----------------------------------------------------------------------
// Main orchestrator — called on task complete / OCPP stop / OEM accept /
// abnormality resolve / tech override resolve.
// -----------------------------------------------------------------------
async function runProgressionForTask(params: {
  task: any;
  vehicle: any;
  triggered_by: string;
  triggered_by_id?: string | null;
  audit_note?: string | null;
  started_at?: number;
}): Promise<{
  decision: ProgressionDecision;
  next_stall_id: string | null;
  next_task_id: string | null;
  vehicle_state: string;
  oem_gate?: { expires_at: string; mode: string; callback_url: string } | null;
  decision_id: string | null;
}> {
  const { task, vehicle } = params;
  const startedAt = params.started_at ?? Date.now();

  // Load fleet operator (for OEM policy lookup and notification target).
  let fleet_operator: any = null;
  if (vehicle.fleet_operator_id) {
    const { data } = await supabase.from("fleet_operators").select("*").eq("id", vehicle.fleet_operator_id).single();
    fleet_operator = data;
  }
  const fleet_operator_id = fleet_operator?.id || null;

  // -------------------------------------------------------------------
  // GATE 1 — Blocking exception?
  // -------------------------------------------------------------------
  const block = await getBlockingException(vehicle.id, "next_stall");
  if (block) {
    const decisionId = await logProgressionDecision({
      vehicle_id: vehicle.id,
      task_id: task.id,
      schedule_id: task.vehicle_schedule_id,
      depot_id: task.depot_id,
      fleet_operator_id,
      decision: "abnormality_blocked",
      triggered_by: params.triggered_by,
      triggered_by_id: params.triggered_by_id ?? null,
      from_stall_id: vehicle.current_stall_id,
      from_task_sequence: task.sequence_order,
      audit_note: block.audit_note || params.audit_note || `Blocked by exception ${block.exception_type} (${block.severity})`,
      latency_ms: Date.now() - startedAt,
      payload: { exception_id: block.exception_id, exception_type: block.exception_type, severity: block.severity, required_resolver_role: block.required_resolver_role },
    });
    return { decision: "abnormality_blocked", next_stall_id: null, next_task_id: null, vehicle_state: vehicle.current_state, decision_id: decisionId };
  }

  // -------------------------------------------------------------------
  // GATE 2 — Tech override present on this task?
  // (Overrides already apply at their own endpoints; this branch handles
  // re-entry if task is resumed after an override was cleared.)
  // -------------------------------------------------------------------
  // No-op here — tech_override_* decisions are written by the override
  // endpoints. We just respect the final task.status and tech_override_action
  // when we walk the chain.

  // -------------------------------------------------------------------
  // Find next task in chain
  // -------------------------------------------------------------------
  const nextTask = await getNextPendingTask(task.vehicle_schedule_id, task.sequence_order);

  // -------------------------------------------------------------------
  // No more tasks → either overnight stage or final redeploy gate
  // -------------------------------------------------------------------
  if (!nextTask) {
    // Check vehicle_schedule for overnight staging: if departure_time > now + 30min
    // AND there's no immediate redeploy, route to overnight stage.
    const { data: sched } = await supabase.from("vehicle_schedules").select("*").eq("id", task.vehicle_schedule_id).single();
    const departureAt = sched?.departure_time ? new Date(sched.departure_time) : null;
    const now = new Date();
    // Overnight / scheduled-release path kicks in when departure is >= 2 hours out.
    // Under 2 hours = treat as immediate redeploy (OEM gate applies if configured).
    const OVERNIGHT_THRESHOLD_MS = 2 * 60 * 60 * 1000;
    const isOvernight = departureAt && (departureAt.getTime() - now.getTime()) > OVERNIGHT_THRESHOLD_MS;

    if (isOvernight) {
      // Pick a staging stall (first available staged_awaiting_service / stage stall)
      const { data: stagingStalls } = await supabase.from("stalls").select("id,stall_code").eq("depot_id", task.depot_id)
        .in("stall_type", ["stage", "staging", "park", "parking"]).eq("status", "available").limit(1);
      const stagingStallId = stagingStalls?.[0]?.id || null;

      // Mark the current task (last completed) as overnight stage anchor
      await supabase.from("schedule_tasks").update({
        is_overnight_stage: true,
        scheduled_release_at: departureAt!.toISOString(),
      }).eq("id", task.id);

      if (stagingStallId) {
        await store.updateVehicleState(vehicle.id, "staged_for_departure", stagingStallId, "otto_q_engine");
      } else {
        await store.updateVehicleState(vehicle.id, "staged_for_departure", null, "otto_q_engine");
      }

      const decisionId = await logProgressionDecision({
        vehicle_id: vehicle.id,
        task_id: task.id,
        schedule_id: task.vehicle_schedule_id,
        depot_id: task.depot_id,
        fleet_operator_id,
        decision: "overnight_staged",
        triggered_by: params.triggered_by,
        triggered_by_id: params.triggered_by_id ?? null,
        from_stall_id: vehicle.current_stall_id,
        to_stall_id: stagingStallId,
        from_task_sequence: task.sequence_order,
        audit_note: params.audit_note || `Vehicle staged until scheduled departure ${departureAt!.toISOString()}`,
        latency_ms: Date.now() - startedAt,
        payload: { scheduled_release_at: departureAt!.toISOString() },
      });
      return { decision: "overnight_staged", next_stall_id: stagingStallId, next_task_id: null, vehicle_state: "staged_for_departure", decision_id: decisionId };
    }

    // Not overnight — this is final redeploy.
    // Check OEM gate (applies to final stage under 'oem_webhook_final_only' or 'oem_webhook_required')
    const gate = await getOemGatePolicy(task.id);
    if (gate?.triggers_gate) {
      return await requestOemAcceptance({
        task, vehicle, fleet_operator, gate,
        next_task: null,  // null = final redeploy
        triggered_by: params.triggered_by,
        triggered_by_id: params.triggered_by_id ?? null,
        started_at: startedAt,
      });
    }

    // No gate → immediate deploy state.
    await store.updateVehicleState(vehicle.id, "staged_for_departure", null, "otto_q_engine");
    const decisionId = await logProgressionDecision({
      vehicle_id: vehicle.id,
      task_id: task.id,
      schedule_id: task.vehicle_schedule_id,
      depot_id: task.depot_id,
      fleet_operator_id,
      decision: "all_services_complete",
      triggered_by: params.triggered_by,
      triggered_by_id: params.triggered_by_id ?? null,
      from_stall_id: vehicle.current_stall_id,
      from_task_sequence: task.sequence_order,
      audit_note: null,
      latency_ms: Date.now() - startedAt,
      payload: {},
    });
    return { decision: "all_services_complete", next_stall_id: null, next_task_id: null, vehicle_state: "staged_for_departure", decision_id: decisionId };
  }

  // -------------------------------------------------------------------
  // There IS a next task. Check OEM gate (only fires under required mode
  // on intermediate transitions; final_only mode won't trigger here).
  // -------------------------------------------------------------------
  const gate = await getOemGatePolicy(task.id);
  if (gate?.triggers_gate) {
    return await requestOemAcceptance({
      task, vehicle, fleet_operator, gate,
      next_task: nextTask,
      triggered_by: params.triggered_by,
      triggered_by_id: params.triggered_by_id ?? null,
      started_at: startedAt,
    });
  }

  // -------------------------------------------------------------------
  // Auto-advance — move vehicle to next stall if available.
  // -------------------------------------------------------------------
  const targetStallId = nextTask.assigned_stall_id;
  const stallFree = targetStallId ? await getStallAvailability(targetStallId) : false;

  if (targetStallId && stallFree) {
    // Map service type → vehicle_state
    const nextState = serviceToVehicleState(nextTask);
    await store.updateVehicleState(vehicle.id, nextState, targetStallId, "otto_q_engine");
    await supabase.from("schedule_tasks").update({
      status: "in_progress",
      actual_start: new Date().toISOString(),
      actual_stall_id: targetStallId,
    }).eq("id", nextTask.id);

    const decisionId = await logProgressionDecision({
      vehicle_id: vehicle.id,
      task_id: task.id,
      schedule_id: task.vehicle_schedule_id,
      depot_id: task.depot_id,
      fleet_operator_id,
      decision: "auto_advanced",
      triggered_by: params.triggered_by,
      triggered_by_id: params.triggered_by_id ?? null,
      from_stall_id: vehicle.current_stall_id,
      to_stall_id: targetStallId,
      from_task_sequence: task.sequence_order,
      to_task_sequence: nextTask.sequence_order,
      audit_note: null,
      latency_ms: Date.now() - startedAt,
      payload: { next_task_id: nextTask.id, next_service_id: nextTask.service_definition_id },
    });
    return { decision: "auto_advanced", next_stall_id: targetStallId, next_task_id: nextTask.id, vehicle_state: nextState, decision_id: decisionId };
  }

  // Next stall busy → hold in place or move to staging
  const decisionId = await logProgressionDecision({
    vehicle_id: vehicle.id,
    task_id: task.id,
    schedule_id: task.vehicle_schedule_id,
    depot_id: task.depot_id,
    fleet_operator_id,
    decision: "held_stall_unavailable",
    triggered_by: params.triggered_by,
    triggered_by_id: params.triggered_by_id ?? null,
    from_stall_id: vehicle.current_stall_id,
    from_task_sequence: task.sequence_order,
    to_task_sequence: nextTask.sequence_order,
    audit_note: `Next stall ${targetStallId || 'unassigned'} not available`,
    latency_ms: Date.now() - startedAt,
    payload: { blocked_stall_id: targetStallId, next_task_id: nextTask.id },
  });
  return { decision: "held_stall_unavailable", next_stall_id: null, next_task_id: nextTask.id, vehicle_state: vehicle.current_state, decision_id: decisionId };
}

function serviceToVehicleState(task: any): string {
  // Best-effort mapping based on service_definition_id or task notes.
  // For production, service_definitions has a target_vehicle_state column you'd join.
  const hint = (task.service_type || task.notes || "").toLowerCase();
  if (hint.includes("dcfc") || hint.includes("dc_fast")) return "charging_dcfc";
  if (hint.includes("l2") || hint.includes("level_2") || hint.includes("charg")) return "charging_l2";
  if (hint.includes("wash")) return "in_wash_bay";
  if (hint.includes("detail")) return "in_detail_bay";
  if (hint.includes("service") || hint.includes("maint") || hint.includes("inspect") || hint.includes("calib")) return "in_service_bay";
  if (hint.includes("stage") || hint.includes("stag") || hint.includes("park")) return "staged_for_departure";
  return "staged_awaiting_service";
}

async function requestOemAcceptance(params: {
  task: any;
  vehicle: any;
  fleet_operator: any;
  gate: { mode: string; timeout_seconds: number; on_timeout: string; is_final_stage: boolean };
  next_task: any | null;
  triggered_by: string;
  triggered_by_id?: string | null;
  started_at: number;
}): Promise<{
  decision: ProgressionDecision;
  next_stall_id: string | null;
  next_task_id: string | null;
  vehicle_state: string;
  oem_gate: { expires_at: string; mode: string; callback_url: string };
  decision_id: string | null;
}> {
  const { task, vehicle, fleet_operator, gate } = params;
  const requestedAt = new Date();
  const expiresAt = new Date(requestedAt.getTime() + gate.timeout_seconds * 1000);

  await supabase.from("schedule_tasks").update({
    oem_acceptance_state: "pending",
    oem_acceptance_requested_at: requestedAt.toISOString(),
    oem_acceptance_expires_at: expiresAt.toISOString(),
  }).eq("id", task.id);

  const callback_url = `${Deno.env.get("PUBLIC_API_BASE") || "https://YOUR_PROJECT.supabase.co/functions/v1/otto-q-api"}/api/v1/tasks/${task.id}/oem-accept`;

  // Fire-and-forget webhook to OEM if configured (delivery adapter stub).
  if (fleet_operator?.webhook_url) {
    try {
      const payload = {
        task_id: task.id,
        vehicle_id: vehicle.id,
        vehicle_external_id: vehicle.av_api_vehicle_id,
        depot_id: task.depot_id,
        sequence_order: task.sequence_order,
        is_final_stage: gate.is_final_stage,
        current_service: task.service_type || null,
        next_service: params.next_task ? (params.next_task.service_type || null) : null,
        current_soc: vehicle.current_soc,
        expires_at: expiresAt.toISOString(),
        callback_url,
      };
      // Best-effort fire-and-forget; failures are tolerated (scheduler handles timeout).
      fetch(`${fleet_operator.webhook_url}/progression-accept`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      }).catch(() => {});
    } catch { /* swallow */ }
  }

  const decisionId = await logProgressionDecision({
    vehicle_id: vehicle.id,
    task_id: task.id,
    schedule_id: task.vehicle_schedule_id,
    depot_id: task.depot_id,
    fleet_operator_id: fleet_operator?.id || null,
    decision: "oem_gate_pending",
    triggered_by: params.triggered_by,
    triggered_by_id: params.triggered_by_id ?? null,
    from_stall_id: vehicle.current_stall_id,
    from_task_sequence: task.sequence_order,
    to_task_sequence: params.next_task?.sequence_order ?? null,
    audit_note: `OEM acceptance requested (mode=${gate.mode}, timeout=${gate.timeout_seconds}s, on_timeout=${gate.on_timeout})`,
    latency_ms: Date.now() - params.started_at,
    payload: { mode: gate.mode, is_final_stage: gate.is_final_stage, expires_at: expiresAt.toISOString(), callback_url },
  });

  return {
    decision: "oem_gate_pending",
    next_stall_id: null,
    next_task_id: params.next_task?.id ?? null,
    vehicle_state: vehicle.current_state,
    oem_gate: { expires_at: expiresAt.toISOString(), mode: gate.mode, callback_url },
    decision_id: decisionId,
  };
}

// Generate post-visit automated report for a completed schedule.
async function generateVisitReport(scheduleId: string): Promise<any | null> {
  const { data: sched } = await supabase.from("vehicle_schedules").select("*").eq("id", scheduleId).single();
  if (!sched) return null;
  const tasks = await getAllTasksForSchedule(scheduleId);
  const { data: decisions } = await supabase.from("progression_decisions").select("*").eq("schedule_id", scheduleId).order("decided_at", { ascending: true });
  const { data: exceptions } = await supabase.from("exceptions").select("*").eq("vehicle_schedule_id", scheduleId);
  const { data: vehicle } = await supabase.from("vehicles").select("*").eq("id", sched.vehicle_id).single();

  const planned_sequence = tasks.map((t: any) => ({
    sequence_order: t.original_sequence_order ?? t.sequence_order,
    service: t.service_type || t.service_definition_id,
    assigned_stall_id: t.assigned_stall_id,
    scheduled_start: t.scheduled_start,
    scheduled_end: t.scheduled_end,
    target_soc: t.target_soc,
  }));
  const actual_sequence = tasks.filter((t: any) => t.actual_start).map((t: any) => ({
    sequence_order: t.sequence_order,
    original_sequence_order: t.original_sequence_order ?? t.sequence_order,
    service: t.service_type || t.service_definition_id,
    actual_stall_id: t.actual_stall_id,
    actual_start: t.actual_start,
    actual_end: t.actual_end,
    soc_at_end: t.soc_at_end,
    confirmed_by_role: t.confirmed_by_role,
    tech_override_action: t.tech_override_action,
    tech_override_audit_note: t.tech_override_audit_note,
    abnormality_flagged: t.abnormality_flagged,
  }));

  const overrides_applied = (decisions || []).filter((d: any) => d.decision.startsWith("tech_override_")).map((d: any) => ({
    action: d.decision.replace("tech_override_", ""),
    task_id: d.task_id,
    reason: d.audit_note,
    audit_note: d.audit_note,
    by_role: d.triggered_by,
    at: d.decided_at,
  }));
  const abnormalities = tasks.filter((t: any) => t.abnormality_flagged).map((t: any) => ({
    task_id: t.id,
    flagged_by_role: t.abnormality_flagged_by_role,
    flagged_at: t.abnormality_flagged_at,
    resolved_by_role: t.abnormality_resolved_by_role,
    resolved_at: t.abnormality_resolved_at,
    note: t.abnormality_resolution_note,
    exception_id: t.exception_id,
  }));
  const oem_interactions = (decisions || []).filter((d: any) =>
    d.decision.startsWith("oem_") || d.decision.startsWith("oem_timeout")
  ).map((d: any) => ({ event: d.decision, at: d.decided_at, latency_ms: d.latency_ms, payload: d.payload, audit_note: d.audit_note }));
  const exceptions_raised = (exceptions || []).map((e: any) => ({
    id: e.id, type: e.exception_type, severity: e.severity, status: e.status,
    blocks_progression: e.blocks_progression, audit_note: e.audit_note,
    created_at: e.created_at, resolved_at: e.resolved_at,
  }));

  const plan_duration_min = sched.departure_time && sched.arrival_time
    ? (new Date(sched.departure_time).getTime() - new Date(sched.arrival_time).getTime()) / 60000
    : null;
  const actual_duration_min = sched.actual_arrival && sched.actual_departure
    ? (new Date(sched.actual_departure).getTime() - new Date(sched.actual_arrival).getTime()) / 60000
    : null;

  let redeployment_status = "incomplete";
  if (vehicle?.current_state === "deployed" || vehicle?.current_state === "en_route_to_deployment") redeployment_status = "redeployed";
  else if (vehicle?.current_state === "out_of_service") redeployment_status = "maintenance_required";
  else if (vehicle?.current_state === "emergency_staged") redeployment_status = "sequestered";
  else if (sched.status === "completed") redeployment_status = "held";

  const audit_trail_complete = overrides_applied.every((o: any) => !!o.audit_note) && abnormalities.every((a: any) => !!a.note || a.resolved_at === null);

  const report = {
    vehicle_id: sched.vehicle_id,
    schedule_id: scheduleId,
    depot_id: sched.depot_id,
    fleet_operator_id: vehicle?.fleet_operator_id || null,
    visit_started_at: sched.actual_arrival || sched.arrival_time,
    visit_completed_at: sched.actual_departure,
    planned_sequence,
    actual_sequence,
    deviation_count: overrides_applied.length + abnormalities.length + (oem_interactions.filter((i: any) => i.event === "oem_rejected" || i.event === "oem_flagged_mid_flow").length),
    overrides_applied,
    abnormalities,
    oem_interactions,
    exceptions_raised,
    planned_duration_min: plan_duration_min,
    actual_duration_min,
    variance_minutes: plan_duration_min != null && actual_duration_min != null ? actual_duration_min - plan_duration_min : null,
    redeployment_status,
    audit_trail_complete,
    payload: {},
  };

  // UPSERT on schedule_id
  const { data: existing } = await supabase.from("depot_visit_reports").select("id").eq("schedule_id", scheduleId).maybeSingle();
  if (existing?.id) {
    await supabase.from("depot_visit_reports").update({ ...report, generated_at: new Date().toISOString() }).eq("id", existing.id);
    return { id: existing.id, ...report };
  }
  const { data: inserted } = await supabase.from("depot_visit_reports").insert(report).select("id").single();
  return { id: inserted?.id, ...report };
}

// Fire scheduled release for overnight staged vehicles whose release time has passed.
async function fireScheduledReleases(depotId?: string): Promise<{ released: number; deferred: number; details: any[] }> {
  const now = new Date().toISOString();
  let q = supabase.from("schedule_tasks").select("*")
    .eq("is_overnight_stage", true)
    .is("scheduled_release_fired_at", null)
    .lte("scheduled_release_at", now);
  if (depotId) q = q.eq("depot_id", depotId);
  const { data: dueTasks } = await q;

  const details: any[] = [];
  let released = 0, deferred = 0;
  for (const t of dueTasks || []) {
    const { data: vehicle } = await supabase.from("vehicles").select("*").eq("id", t.vehicle_id).single();
    if (!vehicle) continue;

    // Still must pass the blocking-exception gate.
    const block = await getBlockingException(vehicle.id, "redeployment");
    if (block) {
      await logProgressionDecision({
        vehicle_id: vehicle.id, task_id: t.id, schedule_id: t.vehicle_schedule_id, depot_id: t.depot_id,
        fleet_operator_id: vehicle.fleet_operator_id,
        decision: "scheduled_release_deferred",
        triggered_by: "scheduler",
        audit_note: `Release deferred: blocking exception ${block.exception_type} (${block.severity})`,
        payload: { exception_id: block.exception_id },
      });
      deferred += 1;
      details.push({ task_id: t.id, status: "deferred", reason: "blocking_exception", exception_id: block.exception_id });
      continue;
    }

    await supabase.from("schedule_tasks").update({ scheduled_release_fired_at: new Date().toISOString() }).eq("id", t.id);
    await store.updateVehicleState(vehicle.id, "en_route_to_deployment", null, "ottoq_scheduler");

    await logProgressionDecision({
      vehicle_id: vehicle.id, task_id: t.id, schedule_id: t.vehicle_schedule_id, depot_id: t.depot_id,
      fleet_operator_id: vehicle.fleet_operator_id,
      decision: "scheduled_release_fired",
      triggered_by: "scheduler",
      from_stall_id: vehicle.current_stall_id,
      audit_note: `Overnight release fired at scheduled departure`,
      payload: { scheduled_release_at: t.scheduled_release_at },
    });
    released += 1;
    details.push({ task_id: t.id, vehicle_id: vehicle.id, status: "released" });

    // Kick off visit report generation for the completed schedule.
    generateVisitReport(t.vehicle_schedule_id).catch(() => {});
  }
  return { released, deferred, details };
}

// Scheduler — resolve OEM acceptance timeouts.
async function resolveOemAcceptanceTimeouts(depotId?: string): Promise<{ resolved: number; details: any[] }> {
  const now = new Date().toISOString();
  let q = supabase.from("schedule_tasks").select("*")
    .eq("oem_acceptance_state", "pending")
    .lte("oem_acceptance_expires_at", now);
  if (depotId) q = q.eq("depot_id", depotId);
  const { data: expired } = await q;

  const details: any[] = [];
  for (const t of expired || []) {
    const { data: vehicle } = await supabase.from("vehicles").select("*").eq("id", t.vehicle_id).single();
    if (!vehicle) continue;
    const { data: fo } = vehicle.fleet_operator_id
      ? await supabase.from("fleet_operators").select("*").eq("id", vehicle.fleet_operator_id).single()
      : { data: null };

    const onTimeout = fo?.oem_acceptance_on_timeout || "auto_accept";
    let newState: "auto_accepted_on_timeout" | "held_on_timeout" | "escalated_on_timeout";
    let decision: ProgressionDecision;

    if (onTimeout === "auto_accept") { newState = "auto_accepted_on_timeout"; decision = "oem_timeout_auto_accepted"; }
    else if (onTimeout === "escalate") { newState = "escalated_on_timeout"; decision = "oem_timeout_escalated"; }
    else { newState = "held_on_timeout"; decision = "oem_timeout_held"; }

    await supabase.from("schedule_tasks").update({
      oem_acceptance_state: newState,
      oem_accepted_at: onTimeout === "auto_accept" ? new Date().toISOString() : null,
      oem_accepted_by: onTimeout === "auto_accept" ? "webhook:auto_timeout" : null,
    }).eq("id", t.id);

    await logProgressionDecision({
      vehicle_id: vehicle.id, task_id: t.id, schedule_id: t.vehicle_schedule_id, depot_id: t.depot_id,
      fleet_operator_id: vehicle.fleet_operator_id,
      decision,
      triggered_by: "scheduler",
      audit_note: `OEM gate ${newState} after ${fo?.oem_acceptance_timeout_seconds ?? 180}s`,
      payload: { on_timeout: onTimeout },
    });

    if (onTimeout === "auto_accept") {
      // Resume progression.
      await runProgressionForTask({ task: t, vehicle, triggered_by: "scheduler", audit_note: "resumed after oem timeout auto-accept" });
    }
    details.push({ task_id: t.id, vehicle_id: vehicle.id, resolution: newState });
  }
  return { resolved: details.length, details };
}

// ---------------------------------------------------------------------------
// Route handler
// ---------------------------------------------------------------------------
serve(async (req: Request) => {
  const url = new URL(req.url);
  const method = req.method.toUpperCase();

  // Strip the edge function prefix to get the API path
  // URL comes in as /otto-q-api/api/v1/...
  const fullPath = url.pathname;
  const path = fullPath.replace(/^\/otto-q-api/, "") || "/";

  // CORS preflight
  if (method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, X-OTTO-Q-API-Key, x-client-info",
        "Access-Control-Max-Age": "86400",
      },
    });
  }

  const startTime = Date.now();

  // ── API Key Authentication (for external webhook sources) ──
  let authenticatedSource: { source: string; depot_id: string; source_name: string } | null = null;
  const apiKeyHeader = req.headers.get("X-OTTO-Q-API-Key");
  if (apiKeyHeader) {
    const keyHash = await sha256(apiKeyHeader);
    const keyRecord = await store.getApiKeyByHash(keyHash);
    if (keyRecord) {
      authenticatedSource = {
        source: keyRecord.source,
        depot_id: keyRecord.depot_id,
        source_name: keyRecord.source_name,
      };
      // Update last_used_at (fire-and-forget)
      supabase.from("ottow_api_keys").update({ last_used_at: new Date().toISOString() }).eq("id", keyRecord.id);
    }
  }

  try {
    // -----------------------------------------------------------------------
    // Health check
    // -----------------------------------------------------------------------
    if (path === "/" || path === "/health") {
      const { count } = await supabase.from("vehicles").select("*", { count: "exact", head: true });
      return ok({
        status: "healthy",
        version: "2.0.0",
        vehicles_in_system: count,
        timestamp: new Date().toISOString(),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/tasks/queue
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/tasks/queue") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const tasks = await store.getTasksByDepot(depotId, {
        status: ["pending", "vehicle_en_route", "in_progress"],
      });

      const enriched = await Promise.all(tasks.map(async (task: any) => {
        const vehicle = await store.getVehicle(task.vehicle_id);
        const stall = task.assigned_stall_id ? await store.getStall(task.assigned_stall_id) : null;
        return {
          ...task,
          vehicle_display_name: vehicle?.display_name || vehicle?.vin,
          vehicle_soc: vehicle?.current_soc,
          stall_code: stall?.stall_code,
          stall_type: stall?.stall_type,
        };
      }));

      return ok({ depot_id: depotId, tasks: enriched, count: enriched.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/start
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/start$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => ({}));
      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);

      if (task.status !== "pending" && task.status !== "vehicle_en_route") {
        return err("CONFLICT", `Task is ${task.status}, expected pending or vehicle_en_route`, 409);
      }

      await store.updateTask(taskId, {
        status: "in_progress",
        actual_start: new Date().toISOString(),
      });

      return ok({ task_id: taskId, status: "in_progress" }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/complete
    // Tech-facing: mark this task complete, then run the progression engine
    // to advance the vehicle to the next stall / next service / final deploy.
    //   Gates applied in order: blocking exception → tech override → OEM
    //   acceptance (final only by default) → overnight stage → auto-advance.
    // Body: { soc_at_end?, notes?, confirmed_by_user_id?, confirmed_by_role?, audit_note? }
    // Returns: { task_id, status, progression: { decision, next_stall_id, next_task_id, vehicle_state, oem_gate? } }
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/complete$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => ({}));
      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);

      if (task.status !== "in_progress" && task.status !== "pending" && task.status !== "vehicle_en_route") {
        return err("CONFLICT", `Task is ${task.status}; expected in_progress/pending/vehicle_en_route`, 409);
      }

      const vehicle = await store.getVehicle(task.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${task.vehicle_id} not found`, 404);

      await store.updateTask(taskId, {
        status: "completed",
        actual_end: new Date().toISOString(),
        soc_at_end: body.soc_at_end,
        notes: body.notes,
        confirmed_by_user_id: body.confirmed_by_user_id,
        confirmed_by_role: body.confirmed_by_role,
        confirmation_timestamp: new Date().toISOString(),
      });

      // Refetch updated task so progression engine sees completed state
      const completedTask = { ...task, status: "completed", actual_end: new Date().toISOString() };

      const progression = await runProgressionForTask({
        task: completedTask,
        vehicle,
        triggered_by: body.confirmed_by_role ? "tech_confirm" : (body.triggered_by || "tech_confirm"),
        triggered_by_id: body.confirmed_by_user_id || null,
        audit_note: body.audit_note || null,
        started_at: startTime,
      });

      return ok({ task_id: taskId, status: "completed", progression }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/oem-accept
    // OEM/Fleet callback — responds to the acceptance gate request. Also
    // usable from OEM console or virtual driver.
    // Body: { accepted: bool, accepted_by: "oem_console:<user> | virtual_driver:<session> | webhook:<svc>", reason?: string }
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/oem-accept$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body || typeof body.accepted !== "boolean") {
        return err("BAD_REQUEST", "Body must include { accepted: boolean, accepted_by: string, reason?: string }", 400);
      }

      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);
      if (task.oem_acceptance_state !== "pending") {
        return err("CONFLICT", `Task oem_acceptance_state is ${task.oem_acceptance_state}; expected pending`, 409);
      }
      const vehicle = await store.getVehicle(task.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", `Vehicle not found`, 404);

      if (body.accepted) {
        await supabase.from("schedule_tasks").update({
          oem_acceptance_state: "accepted",
          oem_accepted_at: new Date().toISOString(),
          oem_accepted_by: body.accepted_by || "oem_webhook",
        }).eq("id", taskId);

        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: "oem_accepted",
          triggered_by: "oem_webhook",
          triggered_by_id: body.accepted_by || null,
          audit_note: null,
          payload: { accepted_by: body.accepted_by },
        });

        // Resume progression — re-run to advance now that gate is cleared.
        const progression = await runProgressionForTask({
          task, vehicle,
          triggered_by: "oem_webhook",
          triggered_by_id: body.accepted_by || null,
          audit_note: "resumed after oem_accepted",
          started_at: startTime,
        });
        return ok({ task_id: taskId, oem_state: "accepted", progression }, startTime);
      }

      // Rejected — require reason per contract.
      if (!body.reason || typeof body.reason !== "string" || body.reason.length < 3) {
        return err("BAD_REQUEST", "Rejection requires a reason string (min 3 chars) for audit trail", 400);
      }
      await supabase.from("schedule_tasks").update({
        oem_acceptance_state: "rejected",
        oem_rejection_reason: body.reason,
      }).eq("id", taskId);

      await logProgressionDecision({
        vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
        fleet_operator_id: vehicle.fleet_operator_id,
        decision: "oem_rejected",
        triggered_by: "oem_webhook",
        triggered_by_id: body.accepted_by || null,
        audit_note: `OEM rejected: ${body.reason}`,
        payload: { reason: body.reason, accepted_by: body.accepted_by },
      });

      // Hold vehicle; route to emergency_staged if current state is transitional.
      await store.updateVehicleState(vehicle.id, "emergency_staged", null, "oem_webhook");
      return ok({ task_id: taskId, oem_state: "rejected", vehicle_state: "emergency_staged", reason: body.reason }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/tech-override
    // Body: {
    //   action: "skip"|"reroute"|"hold"|"flag_exception"|"defer"|"escalate",
    //   next_stall_id?: uuid      // for reroute
    //   defer_in_favor_of_task_id?: uuid  // for defer (the task to run first)
    //   exception_type?, severity?  // for flag_exception
    //   blocks_progression?: bool  // for flag_exception; default true
    //   audit_note: string (REQUIRED, min 3 chars)
    //   by_user_id?: uuid
    // }
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/tech-override$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body || !body.action) return err("BAD_REQUEST", "Body must include { action, audit_note, ... }", 400);
      if (!body.audit_note || typeof body.audit_note !== "string" || body.audit_note.trim().length < 3) {
        return err("BAD_REQUEST", "audit_note is required (min 3 chars) for every override", 400);
      }
      const validActions = ["skip", "reroute", "hold", "flag_exception", "defer", "escalate"];
      if (!validActions.includes(body.action)) return err("BAD_REQUEST", `action must be one of ${validActions.join(",")}`, 400);

      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);
      const vehicle = await store.getVehicle(task.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", `Vehicle not found`, 404);

      // Common: record override on task row
      await supabase.from("schedule_tasks").update({
        tech_override_action: body.action,
        tech_override_reason: body.reason || null,
        tech_override_audit_note: body.audit_note,
        tech_override_by_user_id: body.by_user_id || null,
        tech_override_at: new Date().toISOString(),
      }).eq("id", taskId);

      const decisionMap: Record<string, ProgressionDecision> = {
        skip: "tech_override_skip",
        reroute: "tech_override_reroute",
        hold: "tech_override_hold",
        flag_exception: "tech_override_flag_exception",
        defer: "tech_override_defer",
        escalate: "tech_override_escalate",
      };

      // Dispatch per action
      if (body.action === "skip") {
        await supabase.from("schedule_tasks").update({ status: "skipped" }).eq("id", taskId);
        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: decisionMap[body.action],
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          from_task_sequence: task.sequence_order,
          audit_note: body.audit_note,
          payload: { reason: body.reason || null },
        });
        // Advance past this skipped task
        const progression = await runProgressionForTask({
          task: { ...task, status: "skipped", actual_end: new Date().toISOString() },
          vehicle,
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          audit_note: body.audit_note,
          started_at: startTime,
        });
        return ok({ task_id: taskId, action: "skip", progression }, startTime);
      }

      if (body.action === "reroute") {
        if (!body.next_stall_id) return err("BAD_REQUEST", "reroute requires next_stall_id", 400);
        const stall = await store.getStall(body.next_stall_id);
        if (!stall) return err("NOT_FOUND", `Stall ${body.next_stall_id} not found`, 404);
        await supabase.from("schedule_tasks").update({
          tech_override_next_stall_id: body.next_stall_id,
          status: "completed",  // This task closes; reroute means the vehicle moves to the override stall
          actual_end: new Date().toISOString(),
        }).eq("id", taskId);

        const nextState = stall.stall_type === "stage" || stall.stall_type === "park" ? "staged_for_departure" :
                          stall.stall_type === "charging_dcfc" ? "charging_dcfc" :
                          stall.stall_type === "charging_l2" ? "charging_l2" :
                          stall.stall_type === "wash" ? "in_wash_bay" :
                          stall.stall_type === "detail" ? "in_detail_bay" :
                          stall.stall_type === "service" ? "in_service_bay" :
                          "staged_awaiting_service";
        await store.updateVehicleState(vehicle.id, nextState, body.next_stall_id, "tech_override");

        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: decisionMap[body.action],
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          from_stall_id: vehicle.current_stall_id,
          to_stall_id: body.next_stall_id,
          from_task_sequence: task.sequence_order,
          audit_note: body.audit_note,
          payload: { override_stall_type: stall.stall_type, reason: body.reason || null },
        });
        return ok({ task_id: taskId, action: "reroute", next_stall_id: body.next_stall_id, vehicle_state: nextState }, startTime);
      }

      if (body.action === "hold") {
        // Vehicle stays in current stall; task reverts/stays in_progress. No advance.
        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: decisionMap[body.action],
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          from_stall_id: vehicle.current_stall_id,
          from_task_sequence: task.sequence_order,
          audit_note: body.audit_note,
          payload: { reason: body.reason || null },
        });
        return ok({ task_id: taskId, action: "hold", vehicle_state: vehicle.current_state }, startTime);
      }

      if (body.action === "flag_exception") {
        const blocks = body.blocks_progression !== false;
        const exception = await store.createException({
          depot_id: task.depot_id,
          vehicle_id: task.vehicle_id,
          schedule_task_id: taskId,
          exception_type: body.exception_type || "other",
          severity: body.severity || "high",
          title: body.title || `Tech-flagged: ${body.exception_type || "abnormality"}`,
          description: body.description || body.audit_note,
          status: "open",
          reported_by_user_id: body.by_user_id || "",
        });
        if (exception?.id) {
          await supabase.from("exceptions").update({
            blocks_progression: blocks,
            resolution_required_before: body.resolution_required_before || "next_stall",
            required_resolver_role: "tech",  // Tech-flagged → tech resolves per Chase's rule
            audit_note: body.audit_note,
          }).eq("id", exception.id);
        }
        await supabase.from("schedule_tasks").update({
          status: "exception",
          exception_id: exception?.id,
          abnormality_flagged: true,
          abnormality_flagged_at: new Date().toISOString(),
          abnormality_flagged_by_role: "tech",
          abnormality_flagged_by_id: body.by_user_id || null,
        }).eq("id", taskId);

        if (body.severity === "critical" || body.severity === "high") {
          await store.updateVehicleState(vehicle.id, "emergency_staged", null, "tech_override");
        }

        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: decisionMap[body.action],
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          from_task_sequence: task.sequence_order,
          audit_note: body.audit_note,
          payload: { exception_id: exception?.id, severity: body.severity, blocks_progression: blocks },
        });
        return ok({ task_id: taskId, action: "flag_exception", exception_id: exception?.id, blocks_progression: blocks }, startTime);
      }

      if (body.action === "defer") {
        // Reorder: swap this task's sequence_order with a later task's.
        // The chain is preserved — nothing is dropped; the original order is
        // captured in `original_sequence_order` on both rows so the post-visit
        // report can explain the reorder.
        if (!body.defer_in_favor_of_task_id) {
          return err("BAD_REQUEST", "defer requires defer_in_favor_of_task_id (the task that should run first)", 400);
        }
        const { data: favorTask } = await supabase.from("schedule_tasks").select("*").eq("id", body.defer_in_favor_of_task_id).single();
        if (!favorTask) return err("NOT_FOUND", `defer_in_favor_of_task_id ${body.defer_in_favor_of_task_id} not found`, 404);
        if (favorTask.vehicle_schedule_id !== task.vehicle_schedule_id) {
          return err("BAD_REQUEST", "defer_in_favor_of_task_id must belong to the same vehicle schedule", 400);
        }

        // Capture originals if not set, then swap sequence_order.
        const origA = task.original_sequence_order ?? task.sequence_order;
        const origB = favorTask.original_sequence_order ?? favorTask.sequence_order;
        const swapAt = new Date().toISOString();

        await supabase.from("schedule_tasks").update({
          sequence_order: favorTask.sequence_order,
          original_sequence_order: origA,
          reordered_at: swapAt,
        }).eq("id", taskId);
        await supabase.from("schedule_tasks").update({
          sequence_order: task.sequence_order,
          original_sequence_order: origB,
          reordered_at: swapAt,
        }).eq("id", body.defer_in_favor_of_task_id);

        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: decisionMap[body.action],
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          from_task_sequence: task.sequence_order,
          to_task_sequence: favorTask.sequence_order,
          audit_note: body.audit_note,
          payload: {
            deferred_task_id: taskId,
            run_first_task_id: body.defer_in_favor_of_task_id,
            original_sequence_order_deferred: origA,
            original_sequence_order_run_first: origB,
          },
        });
        return ok({
          task_id: taskId, action: "defer",
          deferred_task: { id: taskId, new_sequence_order: favorTask.sequence_order, original_sequence_order: origA },
          run_first_task: { id: body.defer_in_favor_of_task_id, new_sequence_order: task.sequence_order, original_sequence_order: origB },
        }, startTime);
      }

      if (body.action === "escalate") {
        // Create a tracking exception and notify depot lead (best-effort).
        const exception = await store.createException({
          depot_id: task.depot_id,
          vehicle_id: task.vehicle_id,
          schedule_task_id: taskId,
          exception_type: "other",
          severity: body.severity || "medium",
          title: body.title || "Tech-escalated to depot lead",
          description: body.audit_note,
          status: "escalated",
          reported_by_user_id: body.by_user_id || "",
        });
        if (exception?.id) {
          await supabase.from("exceptions").update({
            blocks_progression: true,
            resolution_required_before: "next_stall",
            required_resolver_role: "tech",
            audit_note: body.audit_note,
          }).eq("id", exception.id);
        }

        await logProgressionDecision({
          vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
          fleet_operator_id: vehicle.fleet_operator_id,
          decision: decisionMap[body.action],
          triggered_by: "tech_confirm",
          triggered_by_id: body.by_user_id || null,
          from_task_sequence: task.sequence_order,
          audit_note: body.audit_note,
          payload: { exception_id: exception?.id, severity: body.severity || "medium" },
        });
        return ok({ task_id: taskId, action: "escalate", exception_id: exception?.id }, startTime);
      }

      return err("INTERNAL", "Unhandled override action", 500);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/flag-abnormality
    // Body: {
    //   flagged_by_role: "tech" | "oem" (required),
    //   flagged_by_id: string (required),
    //   exception_type: string,
    //   severity: "low"|"medium"|"high"|"critical",
    //   blocks_progression: bool (default true),
    //   resolution_required_before: "next_stall"|"next_service"|"redeployment",
    //   audit_note: string (REQUIRED, min 3 chars)
    // }
    // Tech-flagged → tech resolves. OEM-flagged → either can resolve.
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/flag-abnormality$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Body required", 400);
      if (!["tech", "oem"].includes(body.flagged_by_role)) return err("BAD_REQUEST", "flagged_by_role must be tech or oem", 400);
      if (!body.flagged_by_id) return err("BAD_REQUEST", "flagged_by_id required", 400);
      if (!body.audit_note || body.audit_note.trim().length < 3) return err("BAD_REQUEST", "audit_note required (min 3 chars)", 400);

      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);
      const vehicle = await store.getVehicle(task.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", "Vehicle not found", 404);

      const blocks = body.blocks_progression !== false;
      const exception = await store.createException({
        depot_id: task.depot_id,
        vehicle_id: task.vehicle_id,
        schedule_task_id: taskId,
        exception_type: body.exception_type || "other",
        severity: body.severity || "medium",
        title: body.title || `${body.flagged_by_role}-flagged abnormality`,
        description: body.description || body.audit_note,
        status: "open",
        reported_by_user_id: body.flagged_by_role === "tech" ? body.flagged_by_id : "",
      });
      if (exception?.id) {
        await supabase.from("exceptions").update({
          blocks_progression: blocks,
          resolution_required_before: body.resolution_required_before || "next_stall",
          required_resolver_role: body.flagged_by_role === "tech" ? "tech" : "either",
          audit_note: body.audit_note,
        }).eq("id", exception.id);
      }
      await supabase.from("schedule_tasks").update({
        abnormality_flagged: true,
        abnormality_flagged_at: new Date().toISOString(),
        abnormality_flagged_by_role: body.flagged_by_role,
        abnormality_flagged_by_id: body.flagged_by_id,
        exception_id: exception?.id,
      }).eq("id", taskId);

      await logProgressionDecision({
        vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
        fleet_operator_id: vehicle.fleet_operator_id,
        decision: "abnormality_blocked",
        triggered_by: body.flagged_by_role === "tech" ? "tech_confirm" : "oem_console",
        triggered_by_id: body.flagged_by_id,
        from_task_sequence: task.sequence_order,
        audit_note: body.audit_note,
        payload: {
          exception_id: exception?.id,
          flagged_by_role: body.flagged_by_role,
          severity: body.severity,
          blocks_progression: blocks,
          resolution_required_before: body.resolution_required_before || "next_stall",
        },
      });

      return ok({
        task_id: taskId,
        exception_id: exception?.id,
        abnormality_flagged: true,
        flagged_by_role: body.flagged_by_role,
        required_resolver_role: body.flagged_by_role === "tech" ? "tech" : "either",
        blocks_progression: blocks,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/resolve-abnormality
    // Body: {
    //   resolved_by_role: "tech" | "oem",
    //   resolved_by_id: string,
    //   resolution_note: string (REQUIRED, min 3 chars),
    //   resume: bool (default true — re-run progression after resolve)
    // }
    // Enforces: tech-flagged → only tech resolves; OEM-flagged → either.
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/resolve-abnormality$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Body required", 400);
      if (!["tech", "oem"].includes(body.resolved_by_role)) return err("BAD_REQUEST", "resolved_by_role must be tech or oem", 400);
      if (!body.resolved_by_id) return err("BAD_REQUEST", "resolved_by_id required", 400);
      if (!body.resolution_note || body.resolution_note.trim().length < 3) return err("BAD_REQUEST", "resolution_note required (min 3 chars)", 400);

      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);
      if (!task.abnormality_flagged) return err("CONFLICT", "No abnormality is flagged on this task", 409);
      const vehicle = await store.getVehicle(task.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", "Vehicle not found", 404);

      // Enforce resolver role rules
      const flaggedBy = task.abnormality_flagged_by_role;
      const allowed = flaggedBy === "tech" ? ["tech"] : ["tech", "oem"];
      if (!allowed.includes(body.resolved_by_role)) {
        return err("FORBIDDEN", `Abnormality flagged by ${flaggedBy} can only be resolved by: ${allowed.join(", ")}`, 403);
      }

      await supabase.from("schedule_tasks").update({
        abnormality_resolved_at: new Date().toISOString(),
        abnormality_resolved_by_role: body.resolved_by_role,
        abnormality_resolution_note: body.resolution_note,
      }).eq("id", taskId);

      // Resolve the linked exception
      if (task.exception_id) {
        await supabase.from("exceptions").update({
          status: "resolved",
          resolved_at: new Date().toISOString(),
          resolved_by_user_id: body.resolved_by_id,
          resolved_by_role: body.resolved_by_role,
          resolution_notes: body.resolution_note,
        }).eq("id", task.exception_id);
      }

      await logProgressionDecision({
        vehicle_id: vehicle.id, task_id: taskId, schedule_id: task.vehicle_schedule_id, depot_id: task.depot_id,
        fleet_operator_id: vehicle.fleet_operator_id,
        decision: "abnormality_resolved",
        triggered_by: body.resolved_by_role === "tech" ? "tech_confirm" : "oem_console",
        triggered_by_id: body.resolved_by_id,
        from_task_sequence: task.sequence_order,
        audit_note: body.resolution_note,
        payload: { resolved_by_role: body.resolved_by_role, exception_id: task.exception_id },
      });

      // Optionally resume progression now that block is cleared.
      let progression = null;
      if (body.resume !== false && task.status === "completed") {
        progression = await runProgressionForTask({
          task, vehicle,
          triggered_by: body.resolved_by_role === "tech" ? "tech_confirm" : "oem_console",
          triggered_by_id: body.resolved_by_id,
          audit_note: `resumed after abnormality resolved by ${body.resolved_by_role}`,
          started_at: startTime,
        });
      }

      return ok({ task_id: taskId, abnormality_resolved: true, resolved_by_role: body.resolved_by_role, progression }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/vehicles/:id/oem-flag
    // Inbound from OEM (any time, not tied to a transition gate). Creates a
    // blocking exception and pauses the vehicle. Separate from oem-accept.
    // Body: {
    //   flag_type: "examine"|"sequester"|"recall"|"hold_for_update",
    //   reason: string (required, ≥3),
    //   severity?: "low"|"medium"|"high"|"critical",
    //   required_resolver: "tech"|"oem"|"either" (default "either"),
    //   flagged_by: string (OEM-side id, required),
    //   audit_note?: string (if omitted, falls back to reason)
    // }
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/vehicles\/[^/]+\/oem-flag$/.test(path)) {
      const vehicleId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Body required", 400);
      const validFlags = ["examine", "sequester", "recall", "hold_for_update"];
      if (!validFlags.includes(body.flag_type)) return err("BAD_REQUEST", `flag_type must be one of ${validFlags.join(",")}`, 400);
      if (!body.reason || body.reason.trim().length < 3) return err("BAD_REQUEST", "reason required (min 3 chars)", 400);
      if (!body.flagged_by) return err("BAD_REQUEST", "flagged_by required (OEM-side id)", 400);

      const vehicle = await store.getVehicle(vehicleId);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${vehicleId} not found`, 404);

      const severity = body.severity || (body.flag_type === "sequester" || body.flag_type === "recall" ? "high" : "medium");
      const note = body.audit_note || body.reason;

      const exception = await store.createException({
        depot_id: vehicle.current_depot_id || vehicle.home_depot_id,
        vehicle_id: vehicleId,
        schedule_task_id: null,
        exception_type: "other",
        severity,
        title: `OEM flag: ${body.flag_type}`,
        description: body.reason,
        status: "open",
        reported_by_user_id: "",
      });
      if (exception?.id) {
        await supabase.from("exceptions").update({
          blocks_progression: true,
          resolution_required_before: body.flag_type === "sequester" ? "redeployment" : "next_stall",
          required_resolver_role: body.required_resolver || "either",
          audit_note: note,
          metadata: {
            oem_flag_type: body.flag_type,
            oem_flagged_by: body.flagged_by,
          },
        }).eq("id", exception.id);
      }

      // Pause vehicle if in-flight
      if (!["deployed", "en_route_to_deployment", "offline", "out_of_service"].includes(vehicle.current_state)) {
        await store.updateVehicleState(vehicleId, "emergency_staged", null, "oem_console", undefined, { oem_flag_type: body.flag_type, reason: body.reason });
      }

      const decisionId = await logProgressionDecision({
        vehicle_id: vehicleId,
        depot_id: vehicle.current_depot_id || vehicle.home_depot_id,
        fleet_operator_id: vehicle.fleet_operator_id,
        decision: "oem_flagged_mid_flow",
        triggered_by: "oem_console",
        triggered_by_id: body.flagged_by,
        audit_note: note,
        payload: { flag_type: body.flag_type, severity, exception_id: exception?.id, required_resolver: body.required_resolver || "either" },
      });

      return ok({
        vehicle_id: vehicleId,
        exception_id: exception?.id,
        progression_decision_id: decisionId,
        vehicle_state: "emergency_staged",
        flag_type: body.flag_type,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/tasks/:id/progression-status
    // Returns everything a client needs to render the current state of a task's
    // progression: OEM gate info, override state, blocking exceptions, next stall.
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/tasks\/[^/]+\/progression-status$/.test(path)) {
      const taskId = path.split("/")[4];
      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);
      const vehicle = await store.getVehicle(task.vehicle_id);
      const gate = await getOemGatePolicy(taskId);
      const block = await getBlockingException(task.vehicle_id, "next_stall");
      const nextTask = await getNextPendingTask(task.vehicle_schedule_id, task.sequence_order);
      const { data: recent } = await supabase.from("progression_decisions")
        .select("id, decision, triggered_by, audit_note, decided_at, payload")
        .eq("schedule_id", task.vehicle_schedule_id)
        .order("decided_at", { ascending: false })
        .limit(10);

      return ok({
        task_id: taskId,
        task_status: task.status,
        sequence_order: task.sequence_order,
        original_sequence_order: task.original_sequence_order,
        oem_gate: {
          acceptance_mode: gate?.mode,
          state: task.oem_acceptance_state,
          is_final_stage: gate?.is_final_stage,
          triggers_gate: gate?.triggers_gate,
          requested_at: task.oem_acceptance_requested_at,
          expires_at: task.oem_acceptance_expires_at,
          accepted_at: task.oem_accepted_at,
          accepted_by: task.oem_accepted_by,
          rejection_reason: task.oem_rejection_reason,
          on_timeout: gate?.on_timeout,
        },
        tech_override: task.tech_override_action ? {
          action: task.tech_override_action,
          next_stall_id: task.tech_override_next_stall_id,
          audit_note: task.tech_override_audit_note,
          by_user_id: task.tech_override_by_user_id,
          at: task.tech_override_at,
        } : null,
        abnormality: task.abnormality_flagged ? {
          flagged: true,
          flagged_by_role: task.abnormality_flagged_by_role,
          flagged_by_id: task.abnormality_flagged_by_id,
          flagged_at: task.abnormality_flagged_at,
          resolved_at: task.abnormality_resolved_at,
          resolved_by_role: task.abnormality_resolved_by_role,
          resolution_note: task.abnormality_resolution_note,
          exception_id: task.exception_id,
        } : { flagged: false },
        blocking_exception: block,
        next_task: nextTask ? {
          id: nextTask.id,
          sequence_order: nextTask.sequence_order,
          assigned_stall_id: nextTask.assigned_stall_id,
          scheduled_start: nextTask.scheduled_start,
        } : null,
        overnight_stage: task.is_overnight_stage ? {
          scheduled_release_at: task.scheduled_release_at,
          scheduled_release_fired_at: task.scheduled_release_fired_at,
        } : null,
        vehicle_state: vehicle?.current_state,
        current_stall_id: vehicle?.current_stall_id,
        recent_decisions: recent || [],
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/visit-reports/:schedule_id
    // Returns the post-visit automated report for a vehicle schedule. If it
    // doesn't exist yet but the schedule is completed, generates it on demand.
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/visit-reports\/[^/]+$/.test(path)) {
      const scheduleId = path.split("/")[4];
      const { data: existing } = await supabase.from("depot_visit_reports").select("*").eq("schedule_id", scheduleId).maybeSingle();
      if (existing) return ok(existing, startTime);

      // Lazy-generate if schedule exists
      const { data: sched } = await supabase.from("vehicle_schedules").select("id,status").eq("id", scheduleId).maybeSingle();
      if (!sched) return err("NOT_FOUND", `Schedule ${scheduleId} not found`, 404);
      const report = await generateVisitReport(scheduleId);
      if (!report) return err("INTERNAL", "Failed to generate visit report", 500);
      return ok(report, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/visit-reports/:schedule_id/generate
    // Regenerate or force-create the post-visit report.
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/visit-reports\/[^/]+\/generate$/.test(path)) {
      const scheduleId = path.split("/")[4];
      const report = await generateVisitReport(scheduleId);
      if (!report) return err("INTERNAL", "Failed to generate visit report", 500);
      return ok(report, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/vehicles/:id/visit-history
    // List of past visit reports for a vehicle (OEM / fleet backlog).
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/vehicles\/[^/]+\/visit-history$/.test(path)) {
      const vehicleId = path.split("/")[4];
      const limit = parseInt(url.searchParams.get("limit") || "50", 10);
      const { data } = await supabase.from("depot_visit_reports")
        .select("id, schedule_id, depot_id, visit_started_at, visit_completed_at, deviation_count, redeployment_status, variance_minutes, audit_trail_complete, generated_at")
        .eq("vehicle_id", vehicleId)
        .order("generated_at", { ascending: false })
        .limit(limit);
      return ok({ vehicle_id: vehicleId, count: (data || []).length, reports: data || [] }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/scheduler/fire-scheduled-releases
    // Cron-triggered — releases overnight-staged vehicles whose scheduled
    // release time has passed AND no blocking exception.
    // Body: { depot_id?: uuid }
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/scheduler/fire-scheduled-releases") {
      const body = await req.json().catch(() => ({}));
      const result = await fireScheduledReleases(body.depot_id || undefined);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/scheduler/resolve-oem-timeouts
    // Cron-triggered — handles OEM gate timeouts per fleet_operators.oem_acceptance_on_timeout
    // Body: { depot_id?: uuid }
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/scheduler/resolve-oem-timeouts") {
      const body = await req.json().catch(() => ({}));
      const result = await resolveOemAcceptanceTimeouts(body.depot_id || undefined);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/progression-decisions
    // Audit query: filter by vehicle_id / schedule_id / depot_id / decision / since.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/progression-decisions") {
      let q = supabase.from("progression_decisions").select("*").order("decided_at", { ascending: false }).limit(parseInt(url.searchParams.get("limit") || "100", 10));
      const vId = url.searchParams.get("vehicle_id");
      const sId = url.searchParams.get("schedule_id");
      const dId = url.searchParams.get("depot_id");
      const dec = url.searchParams.get("decision");
      const since = url.searchParams.get("since");
      if (vId) q = q.eq("vehicle_id", vId);
      if (sId) q = q.eq("schedule_id", sId);
      if (dId) q = q.eq("depot_id", dId);
      if (dec) q = q.eq("decision", dec);
      if (since) q = q.gte("decided_at", since);
      const { data } = await q;
      return ok({ count: (data || []).length, decisions: data || [] }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tasks/:id/exception
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/tasks\/[^/]+\/exception$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);

      const vehicle = await store.getVehicle(task.vehicle_id);

      const exception = await store.createException({
        depot_id: task.depot_id,
        vehicle_id: task.vehicle_id,
        schedule_task_id: taskId,
        exception_type: body.exception_type,
        severity: body.severity,
        title: body.title,
        description: body.description || "",
        status: "open",
        reported_by_user_id: body.reported_by_user_id || "",
      });

      await store.updateTask(taskId, { status: "exception" });

      if (body.severity === "critical" || body.severity === "high") {
        await store.updateVehicleState(task.vehicle_id, "emergency_staged", null, "otto_q_engine");
      }

      return ok({
        exception_id: exception?.id,
        severity: body.severity,
        vehicle_state: (body.severity === "critical" || body.severity === "high")
          ? "emergency_staged" : vehicle?.current_state,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/stalls/status
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/stalls/status") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const stalls = await store.getStallsByDepot(depotId);

      const enriched = await Promise.all(stalls.map(async (stall: any) => {
        let currentVehicle = null;
        if (stall.current_vehicle_id) {
          const v = await store.getVehicle(stall.current_vehicle_id);
          if (v) {
            currentVehicle = {
              id: v.id,
              display_name: v.display_name || v.vin,
              state: v.current_state,
              soc: v.current_soc,
              category: v.category,
            };
          }
        }

        return {
          id: stall.id,
          stall_code: stall.stall_code,
          stall_type: stall.stall_type,
          zone: stall.zone,
          status: stall.status,
          relative_x: stall.relative_x,
          relative_y: stall.relative_y,
          heading_degrees: stall.heading_degrees,
          current_vehicle: currentVehicle,
        };
      }));

      return ok({
        depot_id: depotId,
        stalls: enriched,
        summary: {
          total: enriched.length,
          available: enriched.filter((s: any) => s.status === "available").length,
          occupied: enriched.filter((s: any) => s.status === "occupied").length,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/exceptions/active
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/exceptions/active") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const exceptions = await store.getExceptionsByDepot(depotId, {
        status: ["open", "investigating", "escalated"],
      });

      return ok({ depot_id: depotId, exceptions, count: exceptions.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/vehicles/:id/transition
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/vehicles\/[^/]+\/transition$/.test(path)) {
      const vehicleId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const vehicle = await store.getVehicle(vehicleId);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${vehicleId} not found`, 404);

      await store.updateVehicleState(
        vehicleId,
        body.target_state,
        body.target_stall_id || null,
        body.triggered_by,
        body.trigger_user_id,
        body.metadata,
      );

      return ok({
        vehicle_id: vehicleId,
        previous_state: vehicle.current_state,
        new_state: body.target_state,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/fleet/:id/vehicles
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/fleet\/[^/]+\/vehicles$/.test(path)) {
      const fleetId = path.split("/")[4];
      const vehicles = await store.getVehiclesByFleet(fleetId);

      return ok({
        fleet_id: fleetId,
        vehicles: vehicles.map((v: any) => ({
          id: v.id,
          vin: v.vin,
          display_name: v.display_name,
          category: v.category,
          platform: v.platform,
          current_state: v.current_state,
          current_soc: v.current_soc,
          make: v.make,
          model: v.model,
          year: v.year,
        })),
        count: vehicles.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/fleet/:id/schedule
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/fleet\/[^/]+\/schedule$/.test(path)) {
      const fleetId = path.split("/")[4];
      const date = url.searchParams.get("date") || new Date().toISOString().split("T")[0];
      const schedules = await store.getSchedulesByFleet(fleetId, date);

      return ok({
        fleet_id: fleetId,
        date,
        schedules,
        count: schedules.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/vehicles/:id/health  (P1: Vehicle Health)
    // Computes health from state log, recent tasks, exceptions, SOC
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/vehicles\/[^/]+\/health$/.test(path)) {
      const vehicleId = path.split("/")[4];
      const vehicle = await store.getVehicle(vehicleId);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${vehicleId} not found`, 404);

      const today = new Date().toISOString().split("T")[0];
      const tasks = await store.getTasksByVehicle(vehicleId, today);
      const exceptions = await store.getExceptionsByDepot(vehicle.depot_id || "", {});
      const vehicleExceptions = (exceptions || []).filter((e: any) => e.vehicle_id === vehicleId);
      const openExceptions = vehicleExceptions.filter((e: any) => e.status !== "resolved");
      const recentExceptions = vehicleExceptions.slice(0, 10);

      // Compute health score (0-100)
      let healthScore = 100;
      if (openExceptions.length > 0) healthScore -= openExceptions.length * 15;
      if (vehicle.current_state === "emergency_staged") healthScore -= 30;
      if (vehicle.current_state === "out_of_service") healthScore -= 50;
      if ((vehicle.current_soc || 0) < 20) healthScore -= 10;
      healthScore = Math.max(0, Math.min(100, healthScore));

      const completedTasks = tasks.filter((t: any) => t.status === "completed");
      const exceptionTasks = tasks.filter((t: any) => t.status === "exception");

      return ok({
        vehicle_id: vehicleId,
        display_name: vehicle.display_name || vehicle.vin,
        make: vehicle.make,
        model: vehicle.model,
        year: vehicle.year,
        health_score: healthScore,
        current_state: vehicle.current_state,
        current_soc: vehicle.current_soc,
        target_soc: vehicle.target_soc,
        last_state_change: vehicle.last_state_change,
        todays_tasks: {
          total: tasks.length,
          completed: completedTasks.length,
          exceptions: exceptionTasks.length,
          tasks: tasks.map((t: any) => ({
            id: t.id,
            service: t.service_definition_id,
            status: t.status,
            scheduled_start: t.scheduled_start,
            scheduled_end: t.scheduled_end,
            actual_start: t.actual_start,
            actual_end: t.actual_end,
            stall_id: t.assigned_stall_id,
          })),
        },
        open_exceptions: openExceptions.map((e: any) => ({
          id: e.id,
          type: e.exception_type,
          severity: e.severity,
          title: e.title,
          created_at: e.created_at,
        })),
        recent_exceptions: recentExceptions.map((e: any) => ({
          id: e.id,
          type: e.exception_type,
          severity: e.severity,
          status: e.status,
          title: e.title,
          created_at: e.created_at,
          resolved_at: e.resolved_at,
        })),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/vehicles/:id/schedule  (P1: Vehicle Schedule)
    // Returns today's schedule + tasks for a specific vehicle
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/vehicles\/[^/]+\/schedule$/.test(path)) {
      const vehicleId = path.split("/")[4];
      const vehicle = await store.getVehicle(vehicleId);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${vehicleId} not found`, 404);

      const date = url.searchParams.get("date") || new Date().toISOString().split("T")[0];
      const schedule = await store.getScheduleForVehicle(vehicleId, date);
      const tasks = await store.getTasksByVehicle(vehicleId, date);

      return ok({
        vehicle_id: vehicleId,
        display_name: vehicle.display_name || vehicle.vin,
        date,
        schedule: schedule ? {
          id: schedule.id,
          status: schedule.status,
          wave_id: schedule.wave_id,
          priority_tier: schedule.priority_tier,
          estimated_arrival: schedule.estimated_arrival,
          estimated_departure: schedule.estimated_departure,
          services_requested: schedule.services_requested,
        } : null,
        tasks: tasks.map((t: any) => ({
          id: t.id,
          sequence_order: t.sequence_order,
          service_definition_id: t.service_definition_id,
          assigned_stall_id: t.assigned_stall_id,
          status: t.status,
          scheduled_start: t.scheduled_start,
          scheduled_end: t.scheduled_end,
          actual_start: t.actual_start,
          actual_end: t.actual_end,
          target_soc: t.target_soc,
          soc_at_start: t.soc_at_start,
          soc_at_end: t.soc_at_end,
          energy_delivered_kwh: t.energy_delivered_kwh,
          notes: t.notes,
          confirmed_by_role: t.confirmed_by_role,
          confirmation_timestamp: t.confirmation_timestamp,
        })),
        task_count: tasks.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // PATCH /api/v1/tasks/:id/progress  (P1: Task Confirmation Checkboxes)
    // Updates a task's status + confirmation + notes
    // -----------------------------------------------------------------------
    if (method === "PATCH" && /^\/api\/v1\/tasks\/[^/]+\/progress$/.test(path)) {
      const taskId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const task = await store.getTask(taskId);
      if (!task) return err("NOT_FOUND", `Task ${taskId} not found`, 404);

      const updates: any = {};
      if (body.status) updates.status = body.status;
      if (body.notes) updates.notes = body.notes;
      if (body.confirmed_by_user_id) {
        updates.confirmed_by_user_id = body.confirmed_by_user_id;
        updates.confirmed_by_role = body.confirmed_by_role || null;
        updates.confirmation_timestamp = new Date().toISOString();
      }
      if (body.status === "in_progress" && !task.actual_start) {
        updates.actual_start = new Date().toISOString();
      }
      if (body.status === "completed" && !task.actual_end) {
        updates.actual_end = new Date().toISOString();
      }
      updates.updated_at = new Date().toISOString();

      await store.updateTask(taskId, updates);

      return ok({
        task_id: taskId,
        previous_status: task.status,
        new_status: updates.status || task.status,
        updated_fields: Object.keys(updates),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/exceptions/:id/notes  (P1: Incident Add Note)
    // Appends a note to exception's resolution_notes via JSONB
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/exceptions\/[^/]+\/notes$/.test(path)) {
      const exceptionId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body?.note) return err("BAD_REQUEST", "note field required", 400);

      const { data: exception } = await supabase.from("exceptions").select("*")
        .eq("id", exceptionId).single();
      if (!exception) return err("NOT_FOUND", `Exception ${exceptionId} not found`, 404);

      // Store notes as JSONB array in metadata or append to resolution_notes
      const existingNotes = exception.metadata?.notes || [];
      const newNote = {
        id: crypto.randomUUID(),
        text: body.note,
        author_id: body.user_id || null,
        author_role: body.role || null,
        created_at: new Date().toISOString(),
      };
      existingNotes.push(newNote);

      await supabase.from("exceptions").update({
        metadata: { ...(exception.metadata || {}), notes: existingNotes },
        updated_at: new Date().toISOString(),
      }).eq("id", exceptionId);

      return ok({
        exception_id: exceptionId,
        note: newNote,
        total_notes: existingNotes.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/exceptions/:id/notes  (P1: Get Incident Notes)
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/exceptions\/[^/]+\/notes$/.test(path)) {
      const exceptionId = path.split("/")[4];

      const { data: exception } = await supabase.from("exceptions").select("id, metadata")
        .eq("id", exceptionId).single();
      if (!exception) return err("NOT_FOUND", `Exception ${exceptionId} not found`, 404);

      return ok({
        exception_id: exceptionId,
        notes: exception.metadata?.notes || [],
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // PATCH /api/v1/stalls/:id/action  (P1: Stall Action Buttons)
    // Handles Confirm Deployment, Queue for Service, Override to Park, etc.
    // -----------------------------------------------------------------------
    if (method === "PATCH" && /^\/api\/v1\/stalls\/[^/]+\/action$/.test(path)) {
      const stallId = path.split("/")[4];
      const body = await req.json().catch(() => null);
      if (!body?.action) return err("BAD_REQUEST", "action field required", 400);

      const stall = await store.getStall(stallId);
      if (!stall) return err("NOT_FOUND", `Stall ${stallId} not found`, 404);

      const result: any = { stall_id: stallId, action: body.action };

      switch (body.action) {
        case "confirm_deployment": {
          // Mark stall available, transition vehicle to next state
          if (stall.current_vehicle_id) {
            await store.updateVehicleState(
              stall.current_vehicle_id,
              "staged_for_departure",
              null,
              body.triggered_by || "charging_tech",
              body.user_id,
            );
            result.vehicle_id = stall.current_vehicle_id;
            result.vehicle_new_state = "staged_for_departure";
          }
          await store.updateStall(stallId, { status: "available", current_vehicle_id: null });
          result.stall_status = "available";
          break;
        }
        case "queue_for_service": {
          if (stall.current_vehicle_id) {
            await store.updateVehicleState(
              stall.current_vehicle_id,
              "staged_awaiting_service",
              null,
              body.triggered_by || "charging_tech",
              body.user_id,
            );
            result.vehicle_id = stall.current_vehicle_id;
            result.vehicle_new_state = "staged_awaiting_service";
          }
          await store.updateStall(stallId, { status: "available", current_vehicle_id: null });
          result.stall_status = "available";
          break;
        }
        case "override_to_park": {
          if (stall.current_vehicle_id) {
            await store.updateVehicleState(
              stall.current_vehicle_id,
              "staged_for_departure",
              null,
              body.triggered_by || "charging_tech",
              body.user_id,
            );
            result.vehicle_id = stall.current_vehicle_id;
            result.vehicle_new_state = "staged_for_departure";
          }
          await store.updateStall(stallId, { status: "available", current_vehicle_id: null });
          result.stall_status = "available";
          break;
        }
        case "take_offline": {
          await store.updateStall(stallId, { status: "out_of_service" });
          if (stall.current_vehicle_id) {
            await store.updateVehicleState(
              stall.current_vehicle_id,
              "staged_awaiting_service",
              null,
              body.triggered_by || "yard_supervisor",
              body.user_id,
            );
            result.vehicle_id = stall.current_vehicle_id;
          }
          result.stall_status = "out_of_service";
          break;
        }
        case "shut_down": {
          await store.updateStall(stallId, { status: "out_of_service" });
          result.stall_status = "out_of_service";
          break;
        }
        case "reopen": {
          await store.updateStall(stallId, { status: "available", current_vehicle_id: null });
          result.stall_status = "available";
          break;
        }
        case "dispatch": {
          if (stall.current_vehicle_id) {
            await store.updateVehicleState(
              stall.current_vehicle_id,
              "en_route_to_deployment",
              null,
              body.triggered_by || "charging_tech",
              body.user_id,
            );
            result.vehicle_id = stall.current_vehicle_id;
            result.vehicle_new_state = "en_route_to_deployment";
          }
          await store.updateStall(stallId, { status: "available", current_vehicle_id: null });
          result.stall_status = "available";
          break;
        }
        case "staging_move": {
          // Move vehicle from staging to a target stall type
          if (stall.current_vehicle_id && body.target_stall_id) {
            const targetStall = await store.getStall(body.target_stall_id);
            if (targetStall && targetStall.status === "available") {
              const stateMap: Record<string, string> = {
                dcfc: "charging_dcfc",
                l2: "charging_l2",
                wash_bay: "in_wash_bay",
                detail_bay: "in_detail_bay",
                service_bay: "in_service_bay",
                staging: "staged_awaiting_service",
              };
              const targetState = stateMap[targetStall.stall_type] || "staged_awaiting_service";
              await store.updateVehicleState(
                stall.current_vehicle_id,
                targetState,
                body.target_stall_id,
                body.triggered_by || "charging_tech",
                body.user_id,
              );
              await store.updateStall(body.target_stall_id, {
                status: "occupied",
                current_vehicle_id: stall.current_vehicle_id,
              });
              await store.updateStall(stallId, { status: "available", current_vehicle_id: null });
              result.vehicle_id = stall.current_vehicle_id;
              result.vehicle_new_state = targetState;
              result.target_stall_id = body.target_stall_id;
            } else {
              return err("CONFLICT", "Target stall not available", 409);
            }
          }
          result.stall_status = "available";
          break;
        }
        default:
          return err("BAD_REQUEST", `Unknown action: ${body.action}`, 400);
      }

      return ok(result, startTime);
    }

    // =====================================================================
    // P3a: ORCHESTRA STRATEGIC ENDPOINTS — Cross-depot aggregations
    // =====================================================================

    // -----------------------------------------------------------------------
    // GET /api/v1/fleet/summary  (P3a: Cross-Depot Fleet Summary)
    // Returns aggregated fleet metrics across all active depots.
    // Used by Orchestra Overview to show the fleet operator a unified view.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/fleet/summary") {
      // Fetch all active depots
      const { data: depots } = await supabase
        .from("depots")
        .select("id, name, city, state, status")
        .eq("status", "active");

      if (!depots || depots.length === 0) {
        return ok({
          depots: [],
          totals: { vehicles: 0, on_site: 0, charging: 0, in_service: 0, staged: 0, en_route: 0 },
          soc_distribution: { critical: 0, low: 0, medium: 0, high: 0, full: 0 },
          stall_utilization: { total: 0, occupied: 0, available: 0, maintenance: 0 },
          active_exceptions: 0,
          active_ottow_missions: 0,
        }, startTime);
      }

      const depotIds = depots.map((d: any) => d.id);

      // All vehicles across these depots
      const { data: vehicles } = await supabase
        .from("vehicles")
        .select("id, current_state, current_soc, home_depot_id");

      // All stalls across these depots
      const { data: stalls } = await supabase
        .from("stalls")
        .select("id, depot_id, stall_type, status")
        .in("depot_id", depotIds);

      // Active exceptions + ottow missions across these depots
      const { data: exceptions } = await supabase
        .from("exceptions")
        .select("id, depot_id, status")
        .in("depot_id", depotIds)
        .neq("status", "resolved");

      const OTTOW_ACTIVE_STATUSES = [
        "reported", "dispatched", "en_route", "on_site",
        "vehicle_secured", "returning", "arrived_depot",
        "stall_assigned",
      ];

      const { data: missions } = await supabase
        .from("ottow_missions")
        .select("id, depot_id, status")
        .in("depot_id", depotIds)
        .in("status", OTTOW_ACTIVE_STATUSES);

      // Aggregate totals
      const allVehicles = vehicles || [];
      const totals = {
        vehicles: allVehicles.length,
        on_site: allVehicles.filter((v: any) => !["en_route", "in_transit", "at_customer"].includes(v.current_state)).length,
        charging: allVehicles.filter((v: any) => ["charging_dcfc", "charging_l2", "charging"].includes(v.current_state)).length,
        in_service: allVehicles.filter((v: any) => ["in_wash_bay", "in_detail_bay", "in_maintenance_bay", "in_service"].includes(v.current_state)).length,
        staged: allVehicles.filter((v: any) => ["staged", "staging", "emergency_staged"].includes(v.current_state)).length,
        en_route: allVehicles.filter((v: any) => ["en_route", "in_transit"].includes(v.current_state)).length,
      };

      // SOC distribution buckets
      const socDist = { critical: 0, low: 0, medium: 0, high: 0, full: 0 };
      for (const v of allVehicles) {
        const soc = v.current_soc ?? 0;
        if (soc < 20) socDist.critical++;
        else if (soc < 40) socDist.low++;
        else if (soc < 70) socDist.medium++;
        else if (soc < 95) socDist.high++;
        else socDist.full++;
      }

      // Stall utilization aggregated
      const allStalls = stalls || [];
      const stallUtil = {
        total: allStalls.length,
        occupied: allStalls.filter((s: any) => s.status === "occupied").length,
        available: allStalls.filter((s: any) => s.status === "available").length,
        maintenance: allStalls.filter((s: any) => s.status === "maintenance" || s.status === "closed").length,
      };

      // Per-depot breakdown
      const perDepot = depots.map((d: any) => {
        const depotVehicles = allVehicles.filter((v: any) => v.home_depot_id === d.id);
        const depotStalls = allStalls.filter((s: any) => s.depot_id === d.id);
        const depotExceptions = (exceptions || []).filter((e: any) => e.depot_id === d.id);
        const depotMissions = (missions || []).filter((m: any) => m.depot_id === d.id);
        return {
          id: d.id,
          name: d.name,
          city: d.city,
          state: d.state,
          vehicles: depotVehicles.length,
          on_site: depotVehicles.filter((v: any) => !["en_route", "in_transit", "at_customer"].includes(v.current_state)).length,
          charging: depotVehicles.filter((v: any) => ["charging_dcfc", "charging_l2", "charging"].includes(v.current_state)).length,
          in_service: depotVehicles.filter((v: any) => ["in_wash_bay", "in_detail_bay", "in_maintenance_bay", "in_service"].includes(v.current_state)).length,
          stalls_total: depotStalls.length,
          stalls_occupied: depotStalls.filter((s: any) => s.status === "occupied").length,
          stalls_available: depotStalls.filter((s: any) => s.status === "available").length,
          active_exceptions: depotExceptions.length,
          active_ottow_missions: depotMissions.length,
          utilization_pct: depotStalls.length > 0
            ? Math.round((depotStalls.filter((s: any) => s.status === "occupied").length / depotStalls.length) * 100)
            : 0,
        };
      });

      return ok({
        depots: perDepot,
        totals,
        soc_distribution: socDist,
        stall_utilization: stallUtil,
        active_exceptions: (exceptions || []).length,
        active_ottow_missions: (missions || []).length,
        timestamp: new Date().toISOString(),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/fleet-summary  (P3a: AI Brain Across All Depots)
    // Aggregates AI Brain metrics across all depots for Orchestra Intelligence Card.
    // Returns: model accuracy, active risks, autonomous actions today, pending actions.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/fleet-summary") {
      const { data: depots } = await supabase
        .from("depots")
        .select("id, name")
        .eq("status", "active");

      if (!depots || depots.length === 0) {
        return ok({
          depots: [],
          model_accuracy: { overall: null, by_type: {} },
          active_risks: { total: 0, critical: 0, warning: 0 },
          autonomous_actions_today: { executed: 0, pending: 0, rejected: 0 },
          recent_actions: [],
        }, startTime);
      }

      const depotIds = depots.map((d: any) => d.id);
      const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

      // Daily accuracy across all depots (last 7 days)
      const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
      const { data: accuracyRows } = await supabase
        .from("prediction_accuracy_daily")
        .select("depot_id, prediction_type, mean_accuracy, scored_predictions, report_date")
        .in("depot_id", depotIds)
        .gte("report_date", sevenDaysAgo);

      const accuracyByType: Record<string, { total_score: number; total_samples: number }> = {};
      let overallTotal = 0;
      let overallSamples = 0;
      for (const row of accuracyRows || []) {
        const type = row.prediction_type;
        if (!accuracyByType[type]) accuracyByType[type] = { total_score: 0, total_samples: 0 };
        const weight = row.scored_predictions || 1;
        const score = Number(row.mean_accuracy || 0);
        accuracyByType[type].total_score += score * weight;
        accuracyByType[type].total_samples += weight;
        overallTotal += score * weight;
        overallSamples += weight;
      }
      const byType: Record<string, number | null> = {};
      for (const type of Object.keys(accuracyByType)) {
        const row = accuracyByType[type];
        byType[type] = row.total_samples > 0 ? Number((row.total_score / row.total_samples).toFixed(4)) : null;
      }
      const overall = overallSamples > 0 ? Number((overallTotal / overallSamples).toFixed(4)) : null;

      // Active risks — pending predictions across all depots.
      // Severity is derived from confidence (>=0.85 = critical, >=0.6 = warning, <0.6 = info).
      const { data: pendingPreds } = await supabase
        .from("ottoq_predictions")
        .select("id, depot_id, prediction_type, confidence, title, status")
        .in("depot_id", depotIds)
        .eq("status", "pending");

      const riskList = pendingPreds || [];
      const activeRisks = {
        total: riskList.length,
        critical: riskList.filter((p: any) => Number(p.confidence || 0) >= 0.85).length,
        warning: riskList.filter((p: any) => {
          const c = Number(p.confidence || 0);
          return c >= 0.6 && c < 0.85;
        }).length,
        info: riskList.filter((p: any) => Number(p.confidence || 0) < 0.6).length,
      };

      // Autonomous actions in last 24h across all depots
      const { data: actions } = await supabase
        .from("autonomous_action_log")
        .select("id, depot_id, action_type, status, created_at, execution_completed_at, action_summary")
        .in("depot_id", depotIds)
        .gte("created_at", since)
        .order("created_at", { ascending: false });

      const allActions = actions || [];
      const actionsToday = {
        executed: allActions.filter((a: any) => a.status === "completed").length,
        pending: allActions.filter((a: any) => a.status === "pending" || a.status === "executing").length,
        failed: allActions.filter((a: any) => a.status === "failed" || a.status === "skipped").length,
        rolled_back: allActions.filter((a: any) => a.status === "rolled_back").length,
      };

      // Per-depot summary
      const perDepot = depots.map((d: any) => {
        const depotAccuracy = (accuracyRows || []).filter((r: any) => r.depot_id === d.id);
        let depotScore = 0;
        let depotSamples = 0;
        for (const row of depotAccuracy) {
          const weight = row.scored_predictions || 1;
          depotScore += Number(row.mean_accuracy || 0) * weight;
          depotSamples += weight;
        }
        return {
          id: d.id,
          name: d.name,
          accuracy: depotSamples > 0 ? Number((depotScore / depotSamples).toFixed(4)) : null,
          active_risks: riskList.filter((p: any) => p.depot_id === d.id).length,
          actions_24h: allActions.filter((a: any) => a.depot_id === d.id).length,
        };
      });

      return ok({
        depots: perDepot,
        model_accuracy: { overall, by_type: byType },
        active_risks: activeRisks,
        autonomous_actions_today: actionsToday,
        recent_actions: allActions.slice(0, 10).map((a: any) => ({
          id: a.id,
          depot_id: a.depot_id,
          action_type: a.action_type,
          status: a.status,
          summary: a.action_summary,
          created_at: a.created_at,
          completed_at: a.execution_completed_at,
        })),
        timestamp: new Date().toISOString(),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/energy/history?depot_id=X&range=7d  (P3a: Historical Energy)
    // Returns energy snapshots for Orchestra Analytics charts.
    // range values: 24h, 7d, 30d, 90d. If no depot_id, aggregates across all active depots.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/energy/history") {
      const depotId = url.searchParams.get("depot_id");
      const range = url.searchParams.get("range") || "7d";

      const rangeHours: Record<string, number> = {
        "24h": 24,
        "7d": 24 * 7,
        "30d": 24 * 30,
        "90d": 24 * 90,
      };
      const hours = rangeHours[range] || 24 * 7;
      const since = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();

      let q = supabase
        .from("depot_state_snapshots")
        .select("depot_id, snapshot_at, current_demand_kw, peak_demand_kw_15min, solar_generation_kw, bess_output_kw, current_rate_per_kwh")
        .gte("snapshot_at", since)
        .order("snapshot_at", { ascending: true });

      if (depotId) q = q.eq("depot_id", depotId);

      const { data: snapshots } = await q;
      const rows = snapshots || [];

      // If no depot_id, aggregate across depots at each timestamp (sum demand, avg rate)
      let series = rows;
      if (!depotId && rows.length > 0) {
        const byTime: Record<string, any> = {};
        for (const r of rows) {
          // Bucket to nearest 15min for alignment
          const bucket = new Date(r.snapshot_at);
          bucket.setMinutes(Math.floor(bucket.getMinutes() / 15) * 15, 0, 0);
          const key = bucket.toISOString();
          if (!byTime[key]) {
            byTime[key] = {
              snapshot_at: key,
              current_demand_kw: 0,
              peak_demand_kw_15min: 0,
              solar_generation_kw: 0,
              bess_output_kw: 0,
              rate_samples: [] as number[],
            };
          }
          byTime[key].current_demand_kw += Number(r.current_demand_kw || 0);
          byTime[key].peak_demand_kw_15min = Math.max(byTime[key].peak_demand_kw_15min, Number(r.peak_demand_kw_15min || 0));
          byTime[key].solar_generation_kw += Number(r.solar_generation_kw || 0);
          byTime[key].bess_output_kw += Number(r.bess_output_kw || 0);
          if (r.current_rate_per_kwh) byTime[key].rate_samples.push(Number(r.current_rate_per_kwh));
        }
        series = Object.values(byTime)
          .map((b: any) => ({
            snapshot_at: b.snapshot_at,
            current_demand_kw: Number(b.current_demand_kw.toFixed(2)),
            peak_demand_kw_15min: Number(b.peak_demand_kw_15min.toFixed(2)),
            solar_generation_kw: Number(b.solar_generation_kw.toFixed(2)),
            bess_output_kw: Number(b.bess_output_kw.toFixed(2)),
            current_rate_per_kwh: b.rate_samples.length
              ? Number((b.rate_samples.reduce((a: number, c: number) => a + c, 0) / b.rate_samples.length).toFixed(4))
              : null,
          }))
          .sort((a: any, b: any) => a.snapshot_at.localeCompare(b.snapshot_at));
      }

      // Summary stats
      const demands = series.map((s: any) => Number(s.current_demand_kw || 0));
      const summary = {
        avg_demand_kw: demands.length ? Number((demands.reduce((a, c) => a + c, 0) / demands.length).toFixed(2)) : 0,
        peak_demand_kw: demands.length ? Number(Math.max(...demands).toFixed(2)) : 0,
        total_solar_kwh: Number((series.reduce((a: number, s: any) => a + (Number(s.solar_generation_kw) || 0) * 0.25, 0)).toFixed(2)),
        total_bess_kwh: Number((series.reduce((a: number, s: any) => a + (Number(s.bess_output_kw) || 0) * 0.25, 0)).toFixed(2)),
        sample_count: series.length,
      };

      return ok({
        depot_id: depotId || "all",
        range,
        series,
        summary,
        timestamp: new Date().toISOString(),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/fleet/schedule?horizon=24h  (P3a: Cross-Depot Fleet Schedule)
    // Returns waves + vehicle schedules across ALL active depots for a 24h window.
    // Used by Orchestra Fleet Scheduling Gantt view.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/fleet/schedule") {
      const horizon = url.searchParams.get("horizon") || "24h";
      const hours = horizon === "48h" ? 48 : horizon === "12h" ? 12 : 24;
      const now = new Date();
      const windowEnd = new Date(now.getTime() + hours * 60 * 60 * 1000);

      const { data: depots } = await supabase
        .from("depots")
        .select("id, name, city, state, timezone")
        .eq("status", "active");

      if (!depots || depots.length === 0) {
        return ok({ depots: [], waves: [], tasks: [], window: { start: now.toISOString(), end: windowEnd.toISOString(), hours } }, startTime);
      }

      const depotIds = depots.map((d: any) => d.id);
      const windowStartBuffer = new Date(now.getTime() - 2 * 60 * 60 * 1000).toISOString();

      // Active + upcoming waves in the window — waves overlap if
      // arrival_window_start <= windowEnd AND arrival_window_end >= windowStartBuffer
      const { data: waves } = await supabase
        .from("waves")
        .select("id, depot_id, wave_code, scheduled_date, arrival_window_start, arrival_window_end, departure_window_start, departure_window_end, vehicle_count, status")
        .in("depot_id", depotIds)
        .gte("arrival_window_end", windowStartBuffer)
        .lte("arrival_window_start", windowEnd.toISOString())
        .order("arrival_window_start", { ascending: true });

      // Tasks within the window (ongoing + upcoming)
      // schedule_tasks doesn't have task_type — derive via service_definitions
      const { data: tasks } = await supabase
        .from("schedule_tasks")
        .select("id, vehicle_id, assigned_stall_id, actual_stall_id, service_definition_id, status, scheduled_start, scheduled_end, actual_start, actual_end, depot_id, target_soc, soc_at_start, soc_at_end")
        .in("depot_id", depotIds)
        .gte("scheduled_end", windowStartBuffer)
        .lte("scheduled_start", windowEnd.toISOString())
        .order("scheduled_start", { ascending: true });

      // Enrich tasks with service type
      const serviceDefIds = [...new Set((tasks || []).map((t: any) => t.service_definition_id).filter(Boolean))];
      let serviceDefMap: Record<string, any> = {};
      if (serviceDefIds.length > 0) {
        const { data: serviceDefs } = await supabase
          .from("service_definitions")
          .select("id, service_type, display_name")
          .in("id", serviceDefIds);
        serviceDefMap = (serviceDefs || []).reduce((acc: any, s: any) => { acc[s.id] = s; return acc; }, {});
      }

      // Enrich tasks with vehicle display info + fleet operator
      const vehicleIds = [...new Set((tasks || []).map((t: any) => t.vehicle_id).filter(Boolean))];
      let vehicleMap: Record<string, any> = {};
      if (vehicleIds.length > 0) {
        const { data: vehs } = await supabase
          .from("vehicles")
          .select("id, display_name, fleet_operator_id, platform, current_soc")
          .in("id", vehicleIds);
        vehicleMap = (vehs || []).reduce((acc: any, v: any) => { acc[v.id] = v; return acc; }, {});
      }

      // Fleet operator names from vehicles
      const fleetOpIds = [...new Set(Object.values(vehicleMap).map((v: any) => v.fleet_operator_id).filter(Boolean))];
      let fleetOpMap: Record<string, string> = {};
      if (fleetOpIds.length > 0) {
        const { data: fleetOps } = await supabase
          .from("fleet_operators")
          .select("id, name")
          .in("id", fleetOpIds);
        fleetOpMap = (fleetOps || []).reduce((acc: any, f: any) => { acc[f.id] = f.name; return acc; }, {});
      }

      const enrichedTasks = (tasks || []).map((t: any) => {
        const svc = serviceDefMap[t.service_definition_id];
        const veh = vehicleMap[t.vehicle_id];
        return {
          ...t,
          service_type: svc?.service_type || null,
          service_display_name: svc?.display_name || null,
          vehicle_display_name: veh?.display_name || null,
          vehicle_platform: veh?.platform || null,
          fleet_operator_name: veh?.fleet_operator_id ? fleetOpMap[veh.fleet_operator_id] || null : null,
        };
      });

      return ok({
        window: { start: now.toISOString(), end: windowEnd.toISOString(), hours },
        depots: depots.map((d: any) => ({ id: d.id, name: d.name, city: d.city, state: d.state, timezone: d.timezone })),
        waves: waves || [],
        tasks: enrichedTasks,
        counts: {
          waves: (waves || []).length,
          tasks: enrichedTasks.length,
          depots: depots.length,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/fleet/schedule-intelligence?horizon=24h
    // (P3c: Fleet Scheduling Intelligence — AI-enriched scheduling view)
    //
    // Joins waves + AI predictions + autonomous action log + demand forecast
    // into a single Orchestra-ready payload. Shows the fleet operator WHY the
    // AI is recommending scheduling changes and what actions have been taken.
    //
    // Closed-loop architecture:
    //   predictions -> risk scores per wave
    //   predictions (pending) -> recommendations queue (ranked by impact)
    //   predictions (accepted/auto_applied) + action log -> outcomes history
    //   historical snapshots (same time-of-day) -> demand forecast overlay
    //
    // External factor hooks (consumed when present, graceful when absent):
    //   - weather_data in depot_state_snapshots
    //   - tariff/rate in current_rate_per_kwh
    //   - ottow mission load (proxy for incident density)
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/fleet/schedule-intelligence") {
      const horizon = url.searchParams.get("horizon") || "24h";
      const hours = horizon === "48h" ? 48 : horizon === "12h" ? 12 : 24;
      const now = new Date();
      const windowStart = new Date(now.getTime() - 2 * 60 * 60 * 1000);
      const windowEnd = new Date(now.getTime() + hours * 60 * 60 * 1000);

      // All scheduling-relevant prediction types
      const SCHEDULING_PREDICTION_TYPES = [
        "arrival_time_adjustment",
        "soc_target_optimization",
        "wave_rebalancing",
        "demand_forecast",
        "stall_utilization",
        "service_duration_update",
      ];

      // Scheduling-relevant action types (from autonomous_action_log)
      const SCHEDULING_ACTION_TYPES = [
        "resequence_queue",
        "pre_position_stall",
        "throttle_charger",
        "trigger_early_recall",
        "adjust_wave",
        "defer_charge",
        "expedite_service",
      ];

      // Fetch active depots first
      const { data: depots } = await supabase
        .from("depots")
        .select("id, name, city, state, timezone")
        .eq("status", "active");

      if (!depots || depots.length === 0) {
        return ok({
          window: { start: now.toISOString(), end: windowEnd.toISOString(), hours },
          waves: [],
          pending_optimizations: [],
          applied_optimizations_24h: [],
          demand_forecast: [],
          summary: {
            waves_count: 0,
            pending_count: 0,
            applied_count_24h: 0,
            avg_risk_score: 0,
            estimated_savings_kwh_24h: 0,
          },
          engine_status: {
            last_snapshot_at: null,
            last_prediction_at: null,
            last_action_at: null,
            healthy: false,
            note: "No active depots — engine idle",
          },
        }, startTime);
      }

      const depotIds = depots.map((d: any) => d.id);
      const last24h = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

      // Parallel fetches for speed
      const [
        wavesRes,
        pendingPredsRes,
        appliedActionsRes,
        demandForecastPredsRes,
        recentSnapshotsRes,
        engineHealthRes,
      ] = await Promise.all([
        supabase
          .from("waves")
          .select("id, depot_id, wave_code, scheduled_date, arrival_window_start, arrival_window_end, departure_window_start, departure_window_end, vehicle_count, status")
          .in("depot_id", depotIds)
          .gte("arrival_window_end", windowStart.toISOString())
          .lte("arrival_window_start", windowEnd.toISOString())
          .order("arrival_window_start", { ascending: true }),

        supabase
          .from("ottoq_predictions")
          .select("id, depot_id, vehicle_id, prediction_type, title, description, recommendation, confidence, supporting_data, status, created_at, expires_at, analysis_window_start, analysis_window_end")
          .in("depot_id", depotIds)
          .in("prediction_type", SCHEDULING_PREDICTION_TYPES)
          .eq("status", "pending")
          .order("confidence", { ascending: false })
          .limit(50),

        supabase
          .from("autonomous_action_log")
          .select("id, depot_id, prediction_id, action_type, action_summary, action_parameters, pre_state, post_state, confidence, approval_method, risk_factors, estimated_impact, status, execution_started_at, execution_completed_at, created_at")
          .in("depot_id", depotIds)
          .in("action_type", SCHEDULING_ACTION_TYPES)
          .gte("created_at", last24h)
          .order("created_at", { ascending: false })
          .limit(50),

        supabase
          .from("ottoq_predictions")
          .select("id, depot_id, recommendation, supporting_data, confidence, analysis_window_start, analysis_window_end, created_at")
          .in("depot_id", depotIds)
          .eq("prediction_type", "demand_forecast")
          .in("status", ["pending", "accepted", "auto_applied"])
          .gte("analysis_window_end", now.toISOString())
          .order("confidence", { ascending: false })
          .limit(20),

        supabase
          .from("depot_state_snapshots")
          .select("depot_id, snapshot_at, current_demand_kw, peak_demand_kw_15min, solar_generation_kw, bess_output_kw, current_rate_per_kwh, weather_data, active_ottow_missions")
          .in("depot_id", depotIds)
          .gte("snapshot_at", last24h)
          .order("snapshot_at", { ascending: true }),

        // Engine health: most recent snapshot, prediction, and action timestamps
        supabase
          .from("depot_state_snapshots")
          .select("snapshot_at")
          .in("depot_id", depotIds)
          .order("snapshot_at", { ascending: false })
          .limit(1)
          .maybeSingle(),
      ]);

      const waves = wavesRes.data || [];
      const pendingPreds = pendingPredsRes.data || [];
      const appliedActions = appliedActionsRes.data || [];
      const forecastPreds = demandForecastPredsRes.data || [];
      const recentSnapshots = recentSnapshotsRes.data || [];

      // Fetch vehicle + fleet operator enrichment for predictions + actions
      const predVehicleIds = [...new Set(pendingPreds.map((p: any) => p.vehicle_id).filter(Boolean))];
      let vehicleMap: Record<string, any> = {};
      if (predVehicleIds.length > 0) {
        const { data: vs } = await supabase
          .from("vehicles")
          .select("id, display_name, platform, fleet_operator_id, current_soc")
          .in("id", predVehicleIds);
        vehicleMap = (vs || []).reduce((acc: any, v: any) => { acc[v.id] = v; return acc; }, {});
      }

      const fleetOpIds = [...new Set(Object.values(vehicleMap).map((v: any) => v.fleet_operator_id).filter(Boolean))];
      let fleetOpMap: Record<string, string> = {};
      if (fleetOpIds.length > 0) {
        const { data: fos } = await supabase
          .from("fleet_operators")
          .select("id, name")
          .in("id", fleetOpIds);
        fleetOpMap = (fos || []).reduce((acc: any, f: any) => { acc[f.id] = f.name; return acc; }, {});
      }

      const depotNameMap: Record<string, string> = (depots || []).reduce((acc: any, d: any) => {
        acc[d.id] = d.name;
        return acc;
      }, {});

      // ---------------------------------------------------------------
      // Per-wave risk scoring
      // Multi-factor: count predictions affecting this wave's time window,
      // weight by confidence, weight again by category severity.
      // ---------------------------------------------------------------
      const PREDICTION_SEVERITY: Record<string, number> = {
        demand_forecast: 1.0,
        wave_rebalancing: 0.9,
        arrival_time_adjustment: 0.7,
        stall_utilization: 0.6,
        soc_target_optimization: 0.5,
        service_duration_update: 0.4,
        maintenance_prediction: 0.4,
      };

      const enrichedWaves = waves.map((w: any) => {
        const waveStart = new Date(w.arrival_window_start).getTime();
        const waveEnd = new Date(w.arrival_window_end).getTime();
        const bufferMs = 2 * 60 * 60 * 1000; // 2h buffer on each side

        // Predictions that affect this wave: same depot + time overlap
        const affecting = pendingPreds.filter((p: any) => {
          if (p.depot_id !== w.depot_id) return false;
          const analyzeStart = p.analysis_window_start ? new Date(p.analysis_window_start).getTime() : null;
          const analyzeEnd = p.analysis_window_end ? new Date(p.analysis_window_end).getTime() : null;
          if (!analyzeStart || !analyzeEnd) return true; // be inclusive if window not set
          return analyzeEnd >= (waveStart - bufferMs) && analyzeStart <= (waveEnd + bufferMs);
        });

        // Risk score: weighted sum normalized to 0-1
        let weightedRisk = 0;
        let weightDenominator = 0;
        const riskFactors: Set<string> = new Set();
        for (const p of affecting) {
          const sev = PREDICTION_SEVERITY[p.prediction_type] ?? 0.5;
          const conf = Number(p.confidence || 0.5);
          weightedRisk += sev * conf;
          weightDenominator += 1;
          riskFactors.add(p.prediction_type);
        }
        const risk_score = weightDenominator > 0
          ? Math.min(1, Number((weightedRisk / Math.max(1, weightDenominator)).toFixed(3)))
          : 0;

        return {
          id: w.id,
          depot_id: w.depot_id,
          depot_name: depotNameMap[w.depot_id] || null,
          wave_code: w.wave_code,
          scheduled_date: w.scheduled_date,
          arrival_window_start: w.arrival_window_start,
          arrival_window_end: w.arrival_window_end,
          departure_window_start: w.departure_window_start,
          departure_window_end: w.departure_window_end,
          vehicle_count: w.vehicle_count,
          status: w.status,
          risk_score,
          risk_level: risk_score >= 0.7 ? "high" : risk_score >= 0.4 ? "medium" : risk_score > 0 ? "low" : "none",
          risk_factors: [...riskFactors],
          ai_recommendation_count: affecting.length,
          ai_recommendations: affecting.slice(0, 3).map((p: any) => ({
            id: p.id,
            prediction_type: p.prediction_type,
            title: p.title,
            confidence: Number(p.confidence || 0),
          })),
        };
      });

      // ---------------------------------------------------------------
      // Pending optimizations queue
      // Ranked by priority score: confidence * category severity * recency
      // Grouped by category for UI.
      // ---------------------------------------------------------------
      const pendingWithPriority = pendingPreds.map((p: any) => {
        const sev = PREDICTION_SEVERITY[p.prediction_type] ?? 0.5;
        const conf = Number(p.confidence || 0);
        const ageHours = (now.getTime() - new Date(p.created_at).getTime()) / (1000 * 60 * 60);
        const recencyBoost = Math.max(0, 1 - (ageHours / 48)); // decays over 48h
        const priority = Number((sev * conf * (0.7 + 0.3 * recencyBoost)).toFixed(4));
        const veh = p.vehicle_id ? vehicleMap[p.vehicle_id] : null;
        return {
          id: p.id,
          depot_id: p.depot_id,
          depot_name: depotNameMap[p.depot_id] || null,
          vehicle_id: p.vehicle_id,
          vehicle_display_name: veh?.display_name || null,
          fleet_operator_name: veh?.fleet_operator_id ? fleetOpMap[veh.fleet_operator_id] || null : null,
          prediction_type: p.prediction_type,
          category: categorizeScheduling(p.prediction_type),
          title: p.title,
          description: p.description,
          recommendation: p.recommendation,
          confidence: conf,
          priority_score: priority,
          risk_factors: extractRiskFactors(p.supporting_data),
          created_at: p.created_at,
          expires_at: p.expires_at,
        };
      }).sort((a: any, b: any) => b.priority_score - a.priority_score);

      // ---------------------------------------------------------------
      // Applied actions in last 24h with outcomes
      // ---------------------------------------------------------------
      const appliedWithOutcome = appliedActions.map((a: any) => {
        const estImpact = a.estimated_impact || "";
        // Try to parse saved kWh/cost from estimated_impact if present
        const kwhMatch = String(estImpact).match(/(\d+(?:\.\d+)?)\s*kWh/i);
        const usdMatch = String(estImpact).match(/\$(\d+(?:\.\d+)?)/);
        return {
          id: a.id,
          depot_id: a.depot_id,
          depot_name: depotNameMap[a.depot_id] || null,
          prediction_id: a.prediction_id,
          action_type: a.action_type,
          category: categorizeAction(a.action_type),
          summary: a.action_summary,
          confidence: Number(a.confidence || 0),
          approval_method: a.approval_method,
          risk_factors: a.risk_factors || [],
          estimated_impact: a.estimated_impact,
          estimated_savings_kwh: kwhMatch ? Number(kwhMatch[1]) : null,
          estimated_savings_usd: usdMatch ? Number(usdMatch[1]) : null,
          status: a.status,
          duration_ms: a.execution_started_at && a.execution_completed_at
            ? new Date(a.execution_completed_at).getTime() - new Date(a.execution_started_at).getTime()
            : null,
          created_at: a.created_at,
          completed_at: a.execution_completed_at,
        };
      });

      // ---------------------------------------------------------------
      // Demand forecast overlay
      // Primary source: demand_forecast predictions (if present).
      // Fallback: same-time-of-day historical snapshots (pattern match).
      // ---------------------------------------------------------------
      const forecastPoints: Array<{
        time: string;
        predicted_demand_kw: number;
        predicted_solar_kw: number;
        predicted_rate_per_kwh: number | null;
        source: "prediction" | "historical_pattern";
        confidence: number;
      }> = [];

      // From predictions
      for (const fp of forecastPreds) {
        const rec = fp.recommendation || {};
        const points = Array.isArray(rec.forecast_points) ? rec.forecast_points : [];
        for (const pt of points) {
          if (pt.time && typeof pt.predicted_demand_kw !== "undefined") {
            forecastPoints.push({
              time: pt.time,
              predicted_demand_kw: Number(pt.predicted_demand_kw || 0),
              predicted_solar_kw: Number(pt.predicted_solar_kw || 0),
              predicted_rate_per_kwh: pt.predicted_rate_per_kwh !== undefined ? Number(pt.predicted_rate_per_kwh) : null,
              source: "prediction",
              confidence: Number(fp.confidence || 0),
            });
          }
        }
      }

      // If we have no prediction-based forecast, synthesize from historical pattern
      // using same hour-of-day from the last 14 days of snapshots (if we had them).
      // For now, project the last 24h forward as a naive pattern.
      if (forecastPoints.length === 0 && recentSnapshots.length >= 4) {
        // Aggregate last 24h snapshots by hour-of-day across depots
        const byHour: Record<number, { demand: number[]; solar: number[]; rate: number[] }> = {};
        for (const s of recentSnapshots) {
          const hour = new Date(s.snapshot_at).getUTCHours();
          if (!byHour[hour]) byHour[hour] = { demand: [], solar: [], rate: [] };
          byHour[hour].demand.push(Number(s.current_demand_kw || 0));
          byHour[hour].solar.push(Number(s.solar_generation_kw || 0));
          if (s.current_rate_per_kwh) byHour[hour].rate.push(Number(s.current_rate_per_kwh));
        }
        const avg = (arr: number[]) => arr.length ? arr.reduce((a, c) => a + c, 0) / arr.length : 0;

        // Project forward in 1h increments
        for (let h = 0; h < hours; h++) {
          const t = new Date(now.getTime() + h * 60 * 60 * 1000);
          const hour = t.getUTCHours();
          const bucket = byHour[hour];
          if (bucket) {
            forecastPoints.push({
              time: t.toISOString(),
              predicted_demand_kw: Number(avg(bucket.demand).toFixed(2)),
              predicted_solar_kw: Number(avg(bucket.solar).toFixed(2)),
              predicted_rate_per_kwh: bucket.rate.length ? Number(avg(bucket.rate).toFixed(4)) : null,
              source: "historical_pattern",
              confidence: 0.4, // low confidence — naive pattern
            });
          }
        }
      }

      // ---------------------------------------------------------------
      // Engine health signal (for the UI to show "live vs stale")
      // ---------------------------------------------------------------
      const lastSnapshot = (engineHealthRes.data as any)?.snapshot_at || null;
      const latestPrediction = pendingPreds.length > 0
        ? pendingPreds.reduce((latest: string, p: any) => p.created_at > latest ? p.created_at : latest, pendingPreds[0].created_at)
        : null;
      const latestAction = appliedActions.length > 0 ? appliedActions[0].created_at : null;
      const snapshotAgeMin = lastSnapshot
        ? (now.getTime() - new Date(lastSnapshot).getTime()) / (1000 * 60)
        : null;
      const engineHealthy = snapshotAgeMin !== null && snapshotAgeMin < 60;

      // ---------------------------------------------------------------
      // Summary rollups
      // ---------------------------------------------------------------
      const avgRisk = enrichedWaves.length
        ? enrichedWaves.reduce((a, w) => a + w.risk_score, 0) / enrichedWaves.length
        : 0;

      const savingsKwh = appliedWithOutcome.reduce((a: number, x: any) => a + (x.estimated_savings_kwh || 0), 0);
      const savingsUsd = appliedWithOutcome.reduce((a: number, x: any) => a + (x.estimated_savings_usd || 0), 0);

      return ok({
        window: { start: now.toISOString(), end: windowEnd.toISOString(), hours },
        waves: enrichedWaves,
        pending_optimizations: pendingWithPriority,
        applied_optimizations_24h: appliedWithOutcome,
        demand_forecast: forecastPoints,
        summary: {
          waves_count: enrichedWaves.length,
          pending_count: pendingWithPriority.length,
          applied_count_24h: appliedWithOutcome.length,
          avg_risk_score: Number(avgRisk.toFixed(3)),
          estimated_savings_kwh_24h: Number(savingsKwh.toFixed(2)),
          estimated_savings_usd_24h: Number(savingsUsd.toFixed(2)),
          high_risk_waves: enrichedWaves.filter(w => w.risk_level === "high").length,
          medium_risk_waves: enrichedWaves.filter(w => w.risk_level === "medium").length,
        },
        engine_status: {
          last_snapshot_at: lastSnapshot,
          last_prediction_at: latestPrediction,
          last_action_at: latestAction,
          snapshot_age_min: snapshotAgeMin !== null ? Number(snapshotAgeMin.toFixed(1)) : null,
          healthy: engineHealthy,
          depots_tracked: depots.length,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/depots/compare  (P3a: Depot Comparison View)
    // Side-by-side depot performance metrics for Orchestra Analytics.
    // Returns current state + last-24h performance deltas for each active depot.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/depots/compare") {
      const { data: depots } = await supabase
        .from("depots")
        .select("id, name, city, state, timezone, config")
        .eq("status", "active");

      if (!depots || depots.length === 0) {
        return ok({ depots: [] }, startTime);
      }

      const depotIds = depots.map((d: any) => d.id);
      const since24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

      // Current stalls
      const { data: stalls } = await supabase
        .from("stalls")
        .select("id, depot_id, status, stall_type")
        .in("depot_id", depotIds);

      // Current vehicles (by home_depot_id)
      const { data: vehicles } = await supabase
        .from("vehicles")
        .select("id, home_depot_id, current_state, current_soc");

      // Last 24h snapshots (for avg demand, peak, solar, bess, health)
      const { data: snapshots } = await supabase
        .from("depot_state_snapshots")
        .select("depot_id, current_demand_kw, peak_demand_kw_15min, solar_generation_kw, bess_output_kw, depot_health_score, active_exceptions, tasks_completed_today")
        .in("depot_id", depotIds)
        .gte("snapshot_at", since24h);

      // Active exceptions + missions
      const { data: exceptions } = await supabase
        .from("exceptions")
        .select("depot_id, severity, status")
        .in("depot_id", depotIds)
        .neq("status", "resolved");

      const { data: missions } = await supabase
        .from("ottow_missions")
        .select("depot_id, status")
        .in("depot_id", depotIds)
        .in("status", [
          "reported", "dispatched", "en_route", "on_site",
          "vehicle_secured", "returning", "arrived_depot", "stall_assigned",
        ]);

      // Completed tasks in last 24h
      const { data: completedTasks } = await supabase
        .from("schedule_tasks")
        .select("depot_id, task_type, actual_start, actual_end")
        .in("depot_id", depotIds)
        .eq("status", "completed")
        .gte("actual_end", since24h);

      const comparison = depots.map((d: any) => {
        const depotStalls = (stalls || []).filter((s: any) => s.depot_id === d.id);
        const depotVehicles = (vehicles || []).filter((v: any) => v.home_depot_id === d.id);
        const depotSnapshots = (snapshots || []).filter((s: any) => s.depot_id === d.id);
        const depotExceptions = (exceptions || []).filter((e: any) => e.depot_id === d.id);
        const depotMissions = (missions || []).filter((m: any) => m.depot_id === d.id);
        const depotCompleted = (completedTasks || []).filter((t: any) => t.depot_id === d.id);

        // Average snapshot metrics
        const avg = (arr: any[], field: string) => {
          const nums = arr.map(a => Number(a[field] || 0)).filter(n => !isNaN(n));
          return nums.length ? nums.reduce((a, c) => a + c, 0) / nums.length : 0;
        };
        const max = (arr: any[], field: string) => {
          const nums = arr.map(a => Number(a[field] || 0)).filter(n => !isNaN(n));
          return nums.length ? Math.max(...nums) : 0;
        };

        // Avg turnaround from completed tasks (minutes)
        const turnarounds = depotCompleted
          .filter((t: any) => t.actual_start && t.actual_end)
          .map((t: any) => (new Date(t.actual_end).getTime() - new Date(t.actual_start).getTime()) / 60000);
        const avgTurnaround = turnarounds.length ? turnarounds.reduce((a, c) => a + c, 0) / turnarounds.length : null;

        // SOC avg
        const socs = depotVehicles.map((v: any) => Number(v.current_soc || 0));
        const avgSoc = socs.length ? socs.reduce((a, c) => a + c, 0) / socs.length : 0;

        return {
          id: d.id,
          name: d.name,
          city: d.city,
          state: d.state,
          timezone: d.timezone,
          stalls: {
            total: depotStalls.length,
            occupied: depotStalls.filter((s: any) => s.status === "occupied").length,
            available: depotStalls.filter((s: any) => s.status === "available").length,
            maintenance: depotStalls.filter((s: any) => ["maintenance", "closed"].includes(s.status)).length,
            utilization_pct: depotStalls.length > 0
              ? Math.round((depotStalls.filter((s: any) => s.status === "occupied").length / depotStalls.length) * 100)
              : 0,
          },
          vehicles: {
            total: depotVehicles.length,
            charging: depotVehicles.filter((v: any) => ["charging_dcfc", "charging_l2", "charging"].includes(v.current_state)).length,
            in_service: depotVehicles.filter((v: any) => ["in_wash_bay", "in_detail_bay", "in_maintenance_bay", "in_service"].includes(v.current_state)).length,
            avg_soc: Number(avgSoc.toFixed(1)),
          },
          energy_24h: {
            avg_demand_kw: Number(avg(depotSnapshots, "current_demand_kw").toFixed(2)),
            peak_demand_kw: Number(max(depotSnapshots, "peak_demand_kw_15min").toFixed(2)),
            avg_solar_kw: Number(avg(depotSnapshots, "solar_generation_kw").toFixed(2)),
            avg_bess_kw: Number(avg(depotSnapshots, "bess_output_kw").toFixed(2)),
            health_score: Number(avg(depotSnapshots, "depot_health_score").toFixed(3)),
          },
          operations_24h: {
            tasks_completed: depotCompleted.length,
            avg_turnaround_min: avgTurnaround !== null ? Number(avgTurnaround.toFixed(1)) : null,
            active_exceptions: depotExceptions.length,
            critical_exceptions: depotExceptions.filter((e: any) => e.severity === "critical").length,
            active_ottow_missions: depotMissions.length,
          },
        };
      });

      return ok({
        depots: comparison,
        timestamp: new Date().toISOString(),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/demand/current
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/demand/current") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const stalls = await store.getStallsByDepot(depotId);
      const dcfcStalls = stalls.filter((s: any) => s.stall_type === "dcfc");
      const activeSessions = await store.getActiveOCPPSessions(depotId);

      return ok({
        depot_id: depotId,
        dcfc: {
          total: dcfcStalls.length,
          occupied: dcfcStalls.filter((s: any) => s.status === "occupied").length,
          available: dcfcStalls.filter((s: any) => s.status === "available").length,
        },
        active_charge_sessions: activeSessions.length,
        timestamp: new Date().toISOString(),
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/predictions/pending
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/predictions/pending") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const predictions = await store.getPredictions(depotId, { status: "pending" });
      return ok({ depot_id: depotId, predictions, count: predictions.length }, startTime);
    }

    // =====================================================================
    // AI BRAIN — Predictive State Engine Endpoints
    // =====================================================================

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/snapshot — Capture depot state snapshot (cron-callable)
    // Called every 15 minutes to build the historical pattern database.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/snapshot") {
      const body = await req.json().catch(() => ({}));
      const depotId = body.depot_id || url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const snapshot = await captureDepotSnapshot(depotId);
      return json({
        data: { snapshot },
        meta: { request_id: correlationId(), timestamp: new Date().toISOString(), processing_ms: Date.now() - startTime },
      }, 201);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/depot-projection — Full depot projection with risks
    // The core prediction endpoint. Projects depot state for 2h, 4h, 8h
    // and returns risk factors and recommended actions.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/depot-projection") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);
      const horizonParam = url.searchParams.get("horizon");  // Optional: "2", "4", "8", or null for all

      const result = await runPredictionCycle(depotId);

      // Filter to requested horizon if specified
      if (horizonParam) {
        const h = parseInt(horizonParam);
        result.projections = result.projections.filter((p: any) => p.horizon_hours === h);
      }

      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/predictions/history — Historical AI predictions
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/predictions/history") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const predictions = await store.getAIPredictions(depotId, {
        action_type: url.searchParams.get("action_type") || undefined,
        execution_status: url.searchParams.get("execution_status") || undefined,
        limit: parseInt(url.searchParams.get("limit") || "50"),
      });

      return ok({ depot_id: depotId, predictions, count: predictions.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/predictions/:id/accept — Human approves a prediction
    // -----------------------------------------------------------------------
    const aiAcceptMatch = path.match(/^\/api\/v1\/ai\/predictions\/([^/]+)\/accept$/);
    if (method === "POST" && aiAcceptMatch) {
      const predictionId = aiAcceptMatch[1];
      const body = await req.json().catch(() => ({}));

      const updated = await store.updatePredictionExecution(predictionId, {
        execution_status: "approved",
        status: "accepted",
        reviewed_by: body.reviewed_by || "human",
        reviewed_at: new Date().toISOString(),
      });

      return ok({ prediction: updated, message: "Prediction approved for execution" }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/predictions/:id/reject — Human rejects a prediction
    // -----------------------------------------------------------------------
    const aiRejectMatch = path.match(/^\/api\/v1\/ai\/predictions\/([^/]+)\/reject$/);
    if (method === "POST" && aiRejectMatch) {
      const predictionId = aiRejectMatch[1];
      const body = await req.json().catch(() => ({}));

      const updated = await store.updatePredictionExecution(predictionId, {
        execution_status: "expired",
        status: "rejected",
        reviewed_by: body.reviewed_by || "human",
        reviewed_at: new Date().toISOString(),
      });

      return ok({ prediction: updated, message: "Prediction rejected" }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/model-performance — Model accuracy metrics
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/model-performance") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const [allParams, recentOutcomes, recentPredictions] = await Promise.all([
        store.getAllModelParameters(depotId),
        store.getPredictionOutcomes(depotId, { limit: 100 }),
        store.getAIPredictions(depotId, { limit: 50 }),
      ]);

      // Calculate accuracy stats
      const outcomesByType: Record<string, any[]> = {};
      for (const o of recentOutcomes) {
        const t = o.prediction_type || "unknown";
        if (!outcomesByType[t]) outcomesByType[t] = [];
        outcomesByType[t].push(o);
      }

      const accuracyByType: Record<string, any> = {};
      for (const [type, outcomes] of Object.entries(outcomesByType)) {
        const scores = outcomes.map((o: any) => o.accuracy_score);
        const avg = scores.reduce((a: number, b: number) => a + b, 0) / scores.length;
        accuracyByType[type] = {
          count: scores.length,
          mean_accuracy: parseFloat(avg.toFixed(4)),
          min_accuracy: parseFloat(Math.min(...scores).toFixed(4)),
          max_accuracy: parseFloat(Math.max(...scores).toFixed(4)),
        };
      }

      // Prediction execution stats
      const execStats = {
        total_predictions: recentPredictions.length,
        pending: recentPredictions.filter((p: any) => p.execution_status === "pending").length,
        approved: recentPredictions.filter((p: any) => p.execution_status === "approved").length,
        executed: recentPredictions.filter((p: any) => p.execution_status === "executed").length,
        expired: recentPredictions.filter((p: any) => p.execution_status === "expired").length,
      };

      return ok({
        depot_id: depotId,
        model_parameters: allParams.map((p: any) => ({
          group: p.parameter_group,
          version: p.version,
          is_active: p.is_active,
          last_tuned_at: p.last_tuned_at,
          tuned_by: p.tuned_by,
          performance_metrics: p.performance_metrics,
        })),
        accuracy_by_prediction_type: accuracyByType,
        execution_stats: execStats,
        outcomes_evaluated: recentOutcomes.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/charge-prediction — Predict charge duration for a vehicle
    // Standalone endpoint for charge time prediction (used by scheduler)
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/charge-prediction") {
      const depotId = url.searchParams.get("depot_id");
      const vehicleId = url.searchParams.get("vehicle_id");
      const currentSoc = parseInt(url.searchParams.get("current_soc") || "0");
      const targetSoc = parseInt(url.searchParams.get("target_soc") || "95");
      if (!depotId || !vehicleId) return err("BAD_REQUEST", "depot_id and vehicle_id required", 400);

      const [vehicle, sessions, modelParams] = await Promise.all([
        store.getVehicle(vehicleId),
        store.getCompletedChargeSessions(depotId, 30),
        store.getModelParameters(depotId, "charge_duration"),
      ]);

      if (!vehicle) return err("NOT_FOUND", "Vehicle not found", 404);

      const prediction = predictChargeDuration(
        vehicleId,
        currentSoc || vehicle.current_soc || 0,
        targetSoc,
        vehicle.battery_capacity_kwh || 100,
        150, // Default DCFC max kW
        sessions,
        modelParams,
      );

      return ok({
        vehicle_id: vehicleId,
        vehicle_name: vehicle.display_name,
        current_soc: currentSoc || vehicle.current_soc,
        target_soc: targetSoc,
        prediction,
      }, startTime);
    }

    // =====================================================================
    // AI BRAIN — Phase 2: Autonomous Action Engine Endpoints
    // =====================================================================

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/run-cycle — Full autonomous prediction + action cycle
    // The main cron entry point. Runs predictions, evaluates guardrails,
    // auto-executes eligible actions, queues others for human approval.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/run-cycle") {
      const body = await req.json().catch(() => ({}));
      const depotId = body.depot_id || url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const result = await runAutonomousCycle(depotId);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/actions/execute — Execute a specific action
    // Can be triggered from a prediction or directly with parameters.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/actions/execute") {
      const body = await req.json();
      if (!body.depot_id || !body.action_type) return err("BAD_REQUEST", "depot_id and action_type required", 400);

      const result = await executeAutonomousAction(
        body.depot_id,
        body.prediction_id || null,
        body.action_type,
        body.action_parameters || {},
        body.confidence || 0.90,
        body.risk_factors || [],
        body.approval_override || undefined,
      );
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/actions/:id/approve — Human approves a pending action
    // -----------------------------------------------------------------------
    const actionApproveMatch = path.match(/^\/api\/v1\/ai\/actions\/([^/]+)\/approve$/);
    if (method === "POST" && actionApproveMatch) {
      const actionId = actionApproveMatch[1];
      const body = await req.json().catch(() => ({}));

      // Get the pending action by ID directly
      const action = await store.getActionById(actionId);
      if (!action) return err("NOT_FOUND", "Action not found", 404);
      if (action.status !== "pending") return err("INVALID_STATE", `Action is '${action.status}', not pending`, 409);

      // Execute with human approval override
      const result = await executeAutonomousAction(
        action.depot_id,
        action.prediction_id,
        action.action_type,
        action.action_parameters,
        action.confidence,
        action.risk_factors || [],
        "human_approved",
      );

      // Mark the original pending entry as superseded
      await store.updateActionLog(actionId, { status: "skipped", action_summary: "Superseded by approved execution" });

      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/actions/:id/rollback — Reverse an executed action
    // -----------------------------------------------------------------------
    const actionRollbackMatch = path.match(/^\/api\/v1\/ai\/actions\/([^/]+)\/rollback$/);
    if (method === "POST" && actionRollbackMatch) {
      const actionId = actionRollbackMatch[1];
      const body = await req.json().catch(() => ({}));

      const action = await store.getActionById(actionId);
      if (!action) return err("NOT_FOUND", "Action not found", 404);
      if (action.status !== "completed") return err("INVALID_STATE", `Cannot rollback action in '${action.status}' state`, 409);

      const result = await rollbackAutonomousAction(action);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/actions/log — Autonomous action audit log
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/actions/log") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const log = await store.getActionLog(depotId, {
        status: url.searchParams.get("status") || undefined,
        action_type: url.searchParams.get("action_type") || undefined,
        limit: parseInt(url.searchParams.get("limit") || "50"),
        since: url.searchParams.get("since") || undefined,
      });

      const summary = {
        total: log.length,
        by_status: {
          completed: log.filter((a: any) => a.status === "completed").length,
          pending: log.filter((a: any) => a.status === "pending").length,
          failed: log.filter((a: any) => a.status === "failed").length,
          skipped: log.filter((a: any) => a.status === "skipped").length,
          rolled_back: log.filter((a: any) => a.status === "rolled_back").length,
        },
        by_type: log.reduce((acc: any, a: any) => { acc[a.action_type] = (acc[a.action_type] || 0) + 1; return acc; }, {}),
      };

      return ok({ depot_id: depotId, actions: log, summary }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/guardrails — View current action guardrails
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/guardrails") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const guardrails = await store.getGuardrails(depotId);
      return ok({ depot_id: depotId, guardrails, count: guardrails.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // PUT /api/v1/ai/guardrails — Update a guardrail configuration
    // -----------------------------------------------------------------------
    if (method === "PUT" && path === "/api/v1/ai/guardrails") {
      const body = await req.json();
      if (!body.depot_id || !body.action_type) return err("BAD_REQUEST", "depot_id and action_type required", 400);

      const updated = await store.upsertGuardrail({
        depot_id: body.depot_id,
        action_type: body.action_type,
        max_per_hour: body.max_per_hour,
        max_per_shift: body.max_per_shift,
        max_per_day: body.max_per_day,
        min_confidence: body.min_confidence,
        auto_execute_confidence: body.auto_execute_confidence,
        cooldown_minutes: body.cooldown_minutes,
        requires_human_approval: body.requires_human_approval,
        enabled: body.enabled,
        max_vehicles_affected: body.max_vehicles_affected,
        max_demand_impact_kw: body.max_demand_impact_kw,
        blackout_start: body.blackout_start || null,
        blackout_end: body.blackout_end || null,
        allow_rollback: body.allow_rollback,
      });

      return ok({ guardrail: updated, message: "Guardrail updated" }, startTime);
    }


    // =====================================================================
    // PHASE 3: LEARNING FEEDBACK LOOP — API Endpoints
    // =====================================================================

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/score-prediction — Score a prediction against reality
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/score-prediction") {
      const body = await req.json();
      if (!body.depot_id || !body.actual_value) {
        return err("BAD_REQUEST", "depot_id and actual_value required", 400);
      }

      const result = await scorePrediction(
        body.prediction_id,
        body.depot_id,
        body.predicted_value || {},
        body.actual_value,
        body.prediction_type || "unknown",
        body.time_horizon_hours || 2,
      );
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/model-performance/detailed — Detailed accuracy analysis
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/model-performance/detailed") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const parameterGroup = url.searchParams.get("parameter_group") || undefined;
      const windowDays = parseInt(url.searchParams.get("window_days") || "7");

      const result = await evaluateModelPerformance(depotId, parameterGroup, windowDays);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/tune — Trigger model parameter tuning
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/tune") {
      const body = await req.json();
      if (!body.depot_id || !body.parameter_group) {
        return err("BAD_REQUEST", "depot_id and parameter_group required", 400);
      }

      const result = await tuneModelParameters(
        body.depot_id,
        body.parameter_group,
        body.trigger_type || "manual",
      );
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/drift-check — Check for accuracy drift across all models
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/drift-check") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const result = await detectAccuracyDrift(depotId);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/daily-report — Generate daily accuracy report
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/daily-report") {
      const body = await req.json().catch(() => ({}));
      const depotId = body.depot_id;
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const result = await generateDailyAccuracyReport(depotId, body.report_date);
      return ok(result, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/accuracy/daily — Get daily accuracy records for dashboard
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/accuracy/daily") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const records = await store.getDailyAccuracy(depotId, {
        prediction_type: url.searchParams.get("prediction_type") || undefined,
        days: parseInt(url.searchParams.get("days") || "30"),
        time_horizon: url.searchParams.get("time_horizon")
          ? parseInt(url.searchParams.get("time_horizon")!) : undefined,
      });

      return ok({
        depot_id: depotId,
        records,
        count: records.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/tuning-history — View model tuning run history
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/tuning-history") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const runs = await store.getTuningRuns(depotId, {
        parameter_group: url.searchParams.get("parameter_group") || undefined,
        status: url.searchParams.get("status") || undefined,
        limit: parseInt(url.searchParams.get("limit") || "20"),
      });

      return ok({
        depot_id: depotId,
        tuning_runs: runs,
        count: runs.length,
      }, startTime);
    }


    // =======================================================================
    // P4 STRENGTHENING ENDPOINTS
    // External factor ingestion, data contracts, model versioning, A/B tests,
    // SLOs, explainability, feature store, downstream contracts, decision
    // fusion audit, engine health — the production-readiness surface.
    // =======================================================================

    // -----------------------------------------------------------------------
    // GET /api/v1/external-factors/sources
    // List all registered adapter sources (weather, grid, traffic, etc.)
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/external-factors/sources") {
      const depotId = url.searchParams.get("depot_id");
      const factorType = url.searchParams.get("factor_type");

      let q = supabase
        .from("external_factor_sources")
        .select("*")
        .order("factor_type", { ascending: true })
        .order("source_name", { ascending: true });

      if (depotId) q = q.or(`depot_id.eq.${depotId},depot_id.is.null`);
      if (factorType) q = q.eq("factor_type", factorType);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      const byType: Record<string, number> = {};
      const byHealth: Record<string, number> = {};
      for (const s of data || []) {
        byType[s.factor_type] = (byType[s.factor_type] || 0) + 1;
        byHealth[s.health_status] = (byHealth[s.health_status] || 0) + 1;
      }

      return ok({
        sources: data || [],
        count: (data || []).length,
        summary: {
          by_factor_type: byType,
          by_health_status: byHealth,
          active: (data || []).filter((s: any) => s.is_active).length,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/external-factors/sources
    // Register a new adapter source (partner can add custom OEM feeds here)
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/external-factors/sources") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const required = ["factor_type", "source_name"];
      for (const f of required) {
        if (!body[f]) return err("BAD_REQUEST", `${f} required`, 400);
      }

      const { data, error } = await supabase
        .from("external_factor_sources")
        .insert({
          depot_id: body.depot_id || null,
          factor_type: body.factor_type,
          source_name: body.source_name,
          provider: body.provider || null,
          source_url: body.source_url || null,
          config: body.config || {},
          poll_interval_sec: body.poll_interval_sec || 900,
          poll_mode: body.poll_mode || "pull",
          required_fields: body.required_fields || [],
          staleness_tolerance_sec: body.staleness_tolerance_sec || 1800,
          fallback_strategy: body.fallback_strategy || "last_known",
          is_active: body.is_active !== false,
          notes: body.notes || null,
        })
        .select()
        .single();

      if (error) return err("INTERNAL", error.message, 500);
      return ok({ source: data, registered_at: new Date().toISOString() }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/external-factors/ingest
    // Accept an observation from a registered adapter. Validates against the
    // source's required_fields contract, computes data_hash, and appends to
    // external_factors_log.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/external-factors/ingest") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const required = ["source_name", "observed_at", "payload"];
      for (const f of required) {
        if (body[f] === undefined) return err("BAD_REQUEST", `${f} required`, 400);
      }

      // Look up source
      const { data: source, error: sourceErr } = await supabase
        .from("external_factor_sources")
        .select("*")
        .eq("source_name", body.source_name)
        .single();

      if (sourceErr || !source) {
        return err("NOT_FOUND", `source '${body.source_name}' not registered`, 404);
      }

      // Validate payload against source.required_fields
      const missing: string[] = [];
      for (const f of source.required_fields || []) {
        if (body.payload[f] === undefined || body.payload[f] === null) missing.push(f);
      }

      if (missing.length > 0) {
        // Log data quality error instead of inserting bad observation
        await supabase.from("data_quality_errors").insert({
          depot_id: source.depot_id,
          source_table: "external_factors_log",
          source_name: source.source_name,
          error_type: "null_required_field",
          severity: "warning",
          field_name: missing.join(","),
          expected: source.required_fields.join(","),
          actual: Object.keys(body.payload).join(","),
          message: `Adapter ${source.source_name} omitted required fields: ${missing.join(", ")}`,
          payload_sample: body.payload,
        });

        // Update source health
        await supabase.from("external_factor_sources")
          .update({
            last_polled_at: new Date().toISOString(),
            last_error_at: new Date().toISOString(),
            last_error: `missing required fields: ${missing.join(", ")}`,
            consecutive_failures: (source.consecutive_failures || 0) + 1,
            health_status: "degraded",
          })
          .eq("id", source.id);

        return err("DATA_CONTRACT_VIOLATION", `Missing required fields: ${missing.join(", ")}`, 422, {
          required: source.required_fields,
          received: Object.keys(body.payload),
          missing,
        });
      }

      // Compute deterministic hash for dedup
      const hashInput = source.id + "|" + body.observed_at + "|" + JSON.stringify(body.payload);
      const encoder = new TextEncoder();
      const data = encoder.encode(hashInput);
      const hashBuffer = await crypto.subtle.digest("SHA-256", data);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const dataHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

      // Dedup check
      const { data: existing } = await supabase
        .from("external_factors_log")
        .select("id")
        .eq("source_id", source.id)
        .eq("data_hash", dataHash)
        .limit(1)
        .maybeSingle();

      if (existing) {
        return ok({
          status: "duplicate",
          existing_id: existing.id,
          data_hash: dataHash,
        }, startTime);
      }

      // Insert observation
      const validFrom = body.valid_from || body.observed_at;
      const { data: inserted, error: insertErr } = await supabase
        .from("external_factors_log")
        .insert({
          source_id: source.id,
          depot_id: source.depot_id,
          factor_type: source.factor_type,
          observed_at: body.observed_at,
          valid_from: validFrom,
          valid_to: body.valid_to || null,
          payload: body.payload,
          data_hash: dataHash,
          quality_score: body.quality_score ?? 1.0,
          is_interpolated: body.is_interpolated || false,
          supersedes_id: body.supersedes_id || null,
        })
        .select()
        .single();

      if (insertErr) return err("INTERNAL", insertErr.message, 500);

      // Update source health telemetry
      await supabase.from("external_factor_sources")
        .update({
          last_polled_at: new Date().toISOString(),
          last_success_at: new Date().toISOString(),
          consecutive_failures: 0,
          health_status: "healthy",
        })
        .eq("id", source.id);

      return ok({
        status: "ingested",
        observation_id: inserted.id,
        data_hash: dataHash,
        source_id: source.id,
        factor_type: source.factor_type,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/external-factors/current
    // Most recent valid observation per factor_type for a depot.
    // This is what the prediction engine calls to enrich its inputs.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/external-factors/current") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const factorTypes = url.searchParams.get("factor_types")?.split(",");

      // Pull recent observations for this depot + global
      let q = supabase
        .from("external_factors_log")
        .select("id, source_id, factor_type, observed_at, ingested_at, valid_from, valid_to, payload, quality_score, is_interpolated")
        .or(`depot_id.eq.${depotId},depot_id.is.null`)
        .order("observed_at", { ascending: false })
        .limit(200);

      if (factorTypes) q = q.in("factor_type", factorTypes);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      // Reduce to most-recent-per-factor_type, filtering out expired
      const now = new Date();
      const byType: Record<string, any> = {};
      for (const row of data || []) {
        if (byType[row.factor_type]) continue;
        if (row.valid_to && new Date(row.valid_to) < now) continue;
        byType[row.factor_type] = row;
      }

      // Compute staleness
      const factors: any[] = Object.values(byType).map((obs: any) => {
        const ageSec = (now.getTime() - new Date(obs.observed_at).getTime()) / 1000;
        return {
          ...obs,
          age_seconds: Math.round(ageSec),
          is_stale: ageSec > 1800,
        };
      });

      return ok({
        depot_id: depotId,
        as_of: now.toISOString(),
        factors,
        count: factors.length,
        factor_types_available: factors.map(f => f.factor_type),
        factor_types_requested: factorTypes || "all",
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/external-factors/history
    // Time-series of observations for a factor_type over a range
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/external-factors/history") {
      const depotId = url.searchParams.get("depot_id");
      const factorType = url.searchParams.get("factor_type");
      const range = url.searchParams.get("range") || "24h";
      if (!factorType) return err("BAD_REQUEST", "factor_type required", 400);

      const hours = range === "7d" ? 168 : range === "30d" ? 720 : 24;
      const since = new Date(Date.now() - hours * 3600 * 1000).toISOString();

      let q = supabase
        .from("external_factors_log")
        .select("id, observed_at, payload, quality_score, is_interpolated")
        .eq("factor_type", factorType)
        .gte("observed_at", since)
        .order("observed_at", { ascending: true });

      if (depotId) q = q.or(`depot_id.eq.${depotId},depot_id.is.null`);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      return ok({
        depot_id: depotId,
        factor_type: factorType,
        range,
        since,
        observations: data || [],
        count: (data || []).length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/snapshots/validate
    // Dry-run data contract validation for a snapshot payload
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/snapshots/validate") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const { data, error } = await supabase.rpc("validate_depot_snapshot", { snapshot: body });
      if (error) return err("INTERNAL", error.message, 500);

      return ok(data, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/data-quality/errors
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/data-quality/errors") {
      const depotId = url.searchParams.get("depot_id");
      const severity = url.searchParams.get("severity");
      const unresolvedOnly = url.searchParams.get("unresolved_only") === "true";
      const limit = parseInt(url.searchParams.get("limit") || "100");

      let q = supabase
        .from("data_quality_errors")
        .select("*")
        .order("detected_at", { ascending: false })
        .limit(limit);

      if (depotId) q = q.eq("depot_id", depotId);
      if (severity) q = q.eq("severity", severity);
      if (unresolvedOnly) q = q.is("resolved_at", null);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      // Summary
      const bySeverity: Record<string, number> = {};
      const byErrorType: Record<string, number> = {};
      const bySource: Record<string, number> = {};
      for (const e of data || []) {
        bySeverity[e.severity] = (bySeverity[e.severity] || 0) + 1;
        byErrorType[e.error_type] = (byErrorType[e.error_type] || 0) + 1;
        bySource[e.source_table] = (bySource[e.source_table] || 0) + 1;
      }

      return ok({
        errors: data || [],
        count: (data || []).length,
        summary: {
          by_severity: bySeverity,
          by_error_type: byErrorType,
          by_source: bySource,
          unresolved: (data || []).filter((e: any) => !e.resolved_at).length,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/model-versions
    // List parameter versions with lineage
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/model-versions") {
      const depotId = url.searchParams.get("depot_id");
      const parameterGroup = url.searchParams.get("parameter_group");
      const status = url.searchParams.get("status");

      let q = supabase
        .from("model_versions")
        .select("*")
        .order("depot_id")
        .order("parameter_group")
        .order("version_number", { ascending: false });

      if (depotId) q = q.eq("depot_id", depotId);
      if (parameterGroup) q = q.eq("parameter_group", parameterGroup);
      if (status) q = q.eq("status", status);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      return ok({
        versions: data || [],
        count: (data || []).length,
        active: (data || []).filter((v: any) => v.status === "active").length,
        candidate: (data || []).filter((v: any) => v.status === "candidate").length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/model-versions
    // Create an immutable snapshot from current model_parameters
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/model-versions") {
      const body = await req.json().catch(() => null);
      if (!body?.depot_id || !body?.parameter_group || !body?.version_tag) {
        return err("BAD_REQUEST", "depot_id, parameter_group, version_tag required", 400);
      }

      // Pull current parameters
      const { data: current } = await supabase
        .from("model_parameters")
        .select("parameters, version")
        .eq("depot_id", body.depot_id)
        .eq("parameter_group", body.parameter_group)
        .single();

      if (!current) return err("NOT_FOUND", "model_parameters row not found", 404);

      // Find next version number
      const { data: latest } = await supabase
        .from("model_versions")
        .select("version_number")
        .eq("depot_id", body.depot_id)
        .eq("parameter_group", body.parameter_group)
        .order("version_number", { ascending: false })
        .limit(1)
        .maybeSingle();

      const nextVersion = (latest?.version_number || 0) + 1;

      // Simple hash
      const encoder = new TextEncoder();
      const hashBuffer = await crypto.subtle.digest(
        "SHA-256",
        encoder.encode(JSON.stringify(current.parameters)),
      );
      const paramHash = Array.from(new Uint8Array(hashBuffer))
        .map(b => b.toString(16).padStart(2, "0")).join("");

      const { data, error } = await supabase
        .from("model_versions")
        .insert({
          depot_id: body.depot_id,
          parameter_group: body.parameter_group,
          version_tag: body.version_tag,
          version_number: nextVersion,
          parameters: body.parameters || current.parameters,
          parameters_hash: paramHash,
          parent_version_id: body.parent_version_id || null,
          source: body.source || "manual",
          status: body.status || "draft",
          promotion_notes: body.promotion_notes || null,
          created_by: body.created_by || "api",
        })
        .select()
        .single();

      if (error) return err("INTERNAL", error.message, 500);
      return ok({ version: data }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/model-versions/:id/promote
    // Transition a version to active; demote prior active to archived
    // -----------------------------------------------------------------------
    if (method === "POST" && path.startsWith("/api/v1/ai/model-versions/") && path.endsWith("/promote")) {
      const id = path.split("/")[5];
      const { data: version, error: fetchErr } = await supabase
        .from("model_versions")
        .select("*")
        .eq("id", id)
        .single();

      if (fetchErr || !version) return err("NOT_FOUND", "model version not found", 404);

      // Demote current active
      await supabase
        .from("model_versions")
        .update({ status: "archived", archived_at: new Date().toISOString() })
        .eq("depot_id", version.depot_id)
        .eq("parameter_group", version.parameter_group)
        .eq("status", "active");

      // Promote target
      const { data: promoted, error: promoteErr } = await supabase
        .from("model_versions")
        .update({
          status: "active",
          promoted_to_active_at: new Date().toISOString(),
        })
        .eq("id", id)
        .select()
        .single();

      if (promoteErr) return err("INTERNAL", promoteErr.message, 500);

      // Mirror parameters back into model_parameters (the live table the engine reads)
      await supabase
        .from("model_parameters")
        .update({
          parameters: version.parameters,
          version: version.version_number,
          last_tuned_at: new Date().toISOString(),
          tuned_by: "promote:" + (version.version_tag || "unknown"),
          updated_at: new Date().toISOString(),
        })
        .eq("depot_id", version.depot_id)
        .eq("parameter_group", version.parameter_group);

      return ok({
        promoted_version: promoted,
        previous_active_archived: true,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/ab-tests
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/ab-tests") {
      const depotId = url.searchParams.get("depot_id");
      const status = url.searchParams.get("status");

      let q = supabase
        .from("ab_tests")
        .select("*, variant_a:model_versions!variant_a_version_id(version_tag,status), variant_b:model_versions!variant_b_version_id(version_tag,status)")
        .order("started_at", { ascending: false, nullsFirst: false })
        .order("created_at", { ascending: false });

      if (depotId) q = q.eq("depot_id", depotId);
      if (status) q = q.eq("status", status);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      return ok({
        tests: data || [],
        count: (data || []).length,
        running: (data || []).filter((t: any) => t.status === "running").length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/ab-tests
    // Create an A/B test (starts in draft; call /start to go live)
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/ab-tests") {
      const body = await req.json().catch(() => null);
      const req_fields = ["depot_id", "parameter_group", "test_name",
                          "variant_a_version_id", "variant_b_version_id"];
      for (const f of req_fields) {
        if (!body?.[f]) return err("BAD_REQUEST", `${f} required`, 400);
      }

      const { data, error } = await supabase
        .from("ab_tests")
        .insert({
          depot_id: body.depot_id,
          parameter_group: body.parameter_group,
          test_name: body.test_name,
          variant_a_version_id: body.variant_a_version_id,
          variant_b_version_id: body.variant_b_version_id,
          traffic_split_pct: body.traffic_split_pct ?? 50,
          hypothesis: body.hypothesis,
          primary_metric: body.primary_metric || "mean_accuracy",
          minimum_sample_size: body.minimum_sample_size || 100,
          minimum_detectable_effect: body.minimum_detectable_effect || 0.02,
          status: "draft",
          planned_end_at: body.planned_end_at || null,
          safety_stop_conditions: body.safety_stop_conditions || {},
          created_by: body.created_by || "api",
        })
        .select()
        .single();

      if (error) return err("INTERNAL", error.message, 500);
      return ok({ test: data }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/ab-tests/:id/start
    // -----------------------------------------------------------------------
    if (method === "POST" && path.startsWith("/api/v1/ai/ab-tests/") && path.endsWith("/start")) {
      const id = path.split("/")[5];
      const { data, error } = await supabase
        .from("ab_tests")
        .update({
          status: "running",
          started_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("status", "draft")
        .select()
        .single();

      if (error || !data) return err("CONFLICT", "test not in draft state or not found", 409);

      // Mark both variants as 'candidate'
      await supabase
        .from("model_versions")
        .update({ status: "candidate" })
        .in("id", [data.variant_a_version_id, data.variant_b_version_id]);

      return ok({ test: data, status: "running" }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/slos
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/slos") {
      const depotId = url.searchParams.get("depot_id");

      let q = supabase
        .from("accuracy_slos")
        .select("*")
        .order("prediction_type")
        .order("time_horizon_hours");

      if (depotId) q = q.or(`depot_id.eq.${depotId},depot_id.is.null`);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      return ok({
        slos: data || [],
        count: (data || []).length,
        active: (data || []).filter((s: any) => s.is_active).length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/slos/evaluate
    // Evaluate all active SLOs (optionally scoped to a depot); write alerts
    // for any breaches. Callable by hourly cron.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/slos/evaluate") {
      const body = await req.json().catch(() => ({} as any));
      const depotId = body?.depot_id;

      let q = supabase
        .from("accuracy_slos")
        .select("*")
        .eq("is_active", true);

      if (depotId) q = q.or(`depot_id.eq.${depotId},depot_id.is.null`);

      const { data: slos, error: slosErr } = await q;
      if (slosErr) return err("INTERNAL", slosErr.message, 500);

      const results: any[] = [];
      const alertsCreated: any[] = [];

      for (const slo of slos || []) {
        const { data: evalResult, error: evalErr } = await supabase.rpc(
          "evaluate_slo_breach",
          { p_slo_id: slo.id },
        );

        if (evalErr) {
          results.push({ slo_id: slo.id, error: evalErr.message });
          continue;
        }

        results.push(evalResult);

        if (evalResult?.status === "breached") {
          // Check cooldown — is there an unresolved alert for this SLO within cooldown?
          const cooldownStart = new Date(
            Date.now() - (slo.alert_cooldown_min || 60) * 60 * 1000,
          ).toISOString();

          const { data: recent } = await supabase
            .from("accuracy_alerts")
            .select("id")
            .eq("slo_id", slo.id)
            .gte("observed_at", cooldownStart)
            .is("resolved_at", null)
            .limit(1)
            .maybeSingle();

          if (!recent) {
            const { data: alert } = await supabase
              .from("accuracy_alerts")
              .insert({
                slo_id: slo.id,
                depot_id: slo.depot_id,
                prediction_type: slo.prediction_type,
                time_horizon_hours: slo.time_horizon_hours,
                severity: evalResult.severity,
                observed_accuracy: evalResult.observed_accuracy || evalResult.passing_pct,
                threshold_breached: evalResult.threshold_breached,
                samples_in_window: evalResult.sample_count,
                window_start: evalResult.window_start,
                window_end: evalResult.window_end,
              })
              .select()
              .single();
            if (alert) alertsCreated.push(alert);
          }
        }
      }

      return ok({
        slos_evaluated: results.length,
        breached: results.filter(r => r?.status === "breached").length,
        healthy: results.filter(r => r?.status === "healthy").length,
        insufficient_samples: results.filter(r => r?.status === "insufficient_samples").length,
        alerts_created: alertsCreated.length,
        results,
        alerts: alertsCreated,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/alerts
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/alerts") {
      const depotId = url.searchParams.get("depot_id");
      const unresolvedOnly = url.searchParams.get("unresolved_only") === "true";
      const limit = parseInt(url.searchParams.get("limit") || "50");

      let q = supabase
        .from("accuracy_alerts")
        .select("*, slo:accuracy_slos(slo_target, accuracy_threshold, auto_rollback_on_breach)")
        .order("observed_at", { ascending: false })
        .limit(limit);

      if (depotId) q = q.eq("depot_id", depotId);
      if (unresolvedOnly) q = q.is("resolved_at", null);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      const bySeverity: Record<string, number> = {};
      for (const a of data || []) {
        bySeverity[a.severity] = (bySeverity[a.severity] || 0) + 1;
      }

      return ok({
        alerts: data || [],
        count: (data || []).length,
        unresolved: (data || []).filter((a: any) => !a.resolved_at).length,
        by_severity: bySeverity,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/alerts/:id/acknowledge
    // -----------------------------------------------------------------------
    if (method === "POST" && path.startsWith("/api/v1/ai/alerts/") && path.endsWith("/acknowledge")) {
      const id = path.split("/")[5];
      const body = await req.json().catch(() => ({} as any));

      const { data, error } = await supabase
        .from("accuracy_alerts")
        .update({
          acknowledged_at: new Date().toISOString(),
          acknowledged_by: body?.acknowledged_by || "api",
        })
        .eq("id", id)
        .is("acknowledged_at", null)
        .select()
        .single();

      if (error || !data) return err("CONFLICT", "alert already acknowledged or not found", 409);
      return ok({ alert: data }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/predictions/:id/explain
    // Return cached explanation OR compute on-demand (sensitivity +
    // feature importance + top-similar-snapshot audit)
    // -----------------------------------------------------------------------
    if (method === "GET" && path.startsWith("/api/v1/ai/predictions/") && path.endsWith("/explain")) {
      const predictionId = path.split("/")[5];

      // Try cached first
      const { data: cached } = await supabase
        .from("prediction_explanations")
        .select("*")
        .eq("prediction_id", predictionId)
        .maybeSingle();

      if (cached) {
        return ok({
          explanation: cached,
          source: "cache",
        }, startTime);
      }

      // Compute on-demand
      const { data: prediction, error: predErr } = await supabase
        .from("ottoq_predictions")
        .select("*")
        .eq("id", predictionId)
        .single();

      if (predErr || !prediction) return err("NOT_FOUND", "prediction not found", 404);

      // Pull a few "similar" snapshots for audit (same hour-of-day, depot)
      const predHour = new Date(prediction.created_at).getUTCHours();
      const { data: snapshots } = await supabase
        .from("depot_state_snapshots")
        .select("id, snapshot_at, vehicles_on_site, current_demand_kw, active_exceptions")
        .eq("depot_id", prediction.depot_id)
        .order("snapshot_at", { ascending: false })
        .limit(50);

      const similar = (snapshots || [])
        .filter((s: any) => new Date(s.snapshot_at).getUTCHours() === predHour)
        .slice(0, 5)
        .map((s: any, idx: number) => ({
          snapshot_id: s.id,
          snapshot_at: s.snapshot_at,
          relevance: Math.max(0.5, 1 - idx * 0.08),
          reason: `same hour-of-day (H${predHour}) + same depot`,
        }));

      const supporting = prediction.supporting_data || {};
      const featureImportance: Record<string, number> = {};
      if (typeof supporting === "object" && supporting !== null) {
        const keys = Object.keys(supporting).slice(0, 6);
        const weights = keys.map((_, i) => 1 / (i + 1));
        const weightSum = weights.reduce((a, b) => a + b, 0);
        keys.forEach((k, i) => { featureImportance[k] = +(weights[i] / weightSum).toFixed(3); });
      }

      // Pull external factors consumed
      const factorIds = prediction.feature_snapshot_ids || [];
      let factorsUsed: any[] = [];
      if (factorIds.length) {
        const { data: factors } = await supabase
          .from("external_factors_log")
          .select("id, factor_type, observed_at, payload")
          .in("id", factorIds);
        factorsUsed = (factors || []).map((f: any) => ({
          factor_log_id: f.id,
          factor_type: f.factor_type,
          observed_at: f.observed_at,
          impact_weight: 1 / factorIds.length,
        }));
      }

      const confidence = prediction.confidence || 0.5;
      const confidenceDecomposition = {
        density_score: +(confidence * 0.95).toFixed(3),
        relevance_score: +(Math.min(1, similar.length / 5)).toFixed(3),
        horizon_decay: prediction.time_horizon_hours
          ? +Math.pow(0.85, Math.max(0, prediction.time_horizon_hours / 4 - 1)).toFixed(3)
          : 1.0,
        variance_penalty: +((confidence ** 0.5)).toFixed(3),
        final: +confidence.toFixed(3),
      };

      // Sensitivity (synthetic but correctly shaped)
      const sensitivity: Record<string, string> = {};
      if (prediction.action_type === "throttle_charger") {
        sensitivity["if_demand_up_10pct"] = "recommend lower kW cap";
        sensitivity["if_tariff_peak_shift"] = "defer 30 min";
      } else if (prediction.action_type === "resequence_queue") {
        sensitivity["if_late_arrival_added"] = "swap next 2 vehicles";
      }

      const genStart = Date.now();
      const { data: cached2, error: cacheErr } = await supabase
        .from("prediction_explanations")
        .insert({
          prediction_id: predictionId,
          top_similar_snapshots: similar,
          external_factors_used: factorsUsed,
          feature_importance: featureImportance,
          sensitivity_analysis: sensitivity,
          confidence_decomposition: confidenceDecomposition,
          risk_factor_weights: supporting.risk_factor_weights || {},
          model_version_id: prediction.model_version_id,
          ab_test_id: prediction.ab_test_id,
          ab_test_variant: prediction.ab_test_variant,
          generation_method: "on_demand",
          generation_ms: Date.now() - genStart,
        })
        .select()
        .single();

      if (cacheErr) return err("INTERNAL", cacheErr.message, 500);

      return ok({
        explanation: cached2,
        source: "computed",
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/action-contracts
    // Return the list of downstream action contracts. This is what a partner
    // engineer queries to learn: "what does OTTO-Q send to my system?"
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/action-contracts") {
      const actionType = url.searchParams.get("action_type");
      const downstreamSystem = url.searchParams.get("downstream_system");
      const implementedOnly = url.searchParams.get("implemented_only") === "true";

      let q = supabase
        .from("downstream_action_contracts")
        .select("*")
        .order("action_type")
        .order("downstream_system");

      if (actionType) q = q.eq("action_type", actionType);
      if (downstreamSystem) q = q.eq("downstream_system", downstreamSystem);
      if (implementedOnly) q = q.eq("is_implemented", true);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      const byActionType: Record<string, number> = {};
      let implemented = 0;
      for (const c of data || []) {
        byActionType[c.action_type] = (byActionType[c.action_type] || 0) + 1;
        if (c.is_implemented) implemented++;
      }

      return ok({
        contracts: data || [],
        count: (data || []).length,
        implemented,
        pending: (data || []).length - implemented,
        by_action_type: byActionType,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/decision-fusion/simulate
    // Dry-run the decision fusion algorithm. Given signals + weights + fusion
    // method, returns what the brain would decide WITHOUT persisting or
    // executing anything. Useful for partner engineers to verify the math.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/decision-fusion/simulate") {
      const body = await req.json().catch(() => null);
      if (!body?.signals || !Array.isArray(body.signals)) {
        return err("BAD_REQUEST", "signals (array) required", 400);
      }

      const method = body.fusion_method || "weighted_sum";
      const signals = body.signals as Array<{
        source: string; weight: number; observation: any; reliability?: number;
      }>;

      // Normalize weights × reliability
      let totalEffective = 0;
      const effectiveWeights = signals.map(s => {
        const eff = (s.weight || 0) * (s.reliability ?? 1.0);
        totalEffective += eff;
        return eff;
      });

      const normalized = effectiveWeights.map(w => totalEffective > 0 ? w / totalEffective : 0);

      // Build confidence from signal reliabilities (geometric mean, fallback 0.5)
      const reliabilities = signals.map(s => s.reliability ?? 1.0).filter(r => r > 0);
      const geomMean = reliabilities.length
        ? Math.pow(reliabilities.reduce((a, b) => a * b, 1), 1 / reliabilities.length)
        : 0.5;

      // Synthesize a weighted output. For each key, re-normalize weights over
      // only the signals that actually report that key — otherwise a key that
      // appears in 1 out of 4 signals gets averaged with 3 implicit zeros,
      // which is mathematically wrong for partner-engineer review.
      const synthesized: Record<string, number> = {};
      const contributorsByKey: Record<string, Array<{ value: number; weight: number }>> = {};

      for (let i = 0; i < signals.length; i++) {
        const obs = signals[i].observation || {};
        for (const [k, v] of Object.entries(obs)) {
          let numeric: number | null = null;
          if (typeof v === "number") numeric = v;
          else if (typeof v === "boolean") numeric = v ? 1 : 0;
          if (numeric === null) continue;

          contributorsByKey[k] = contributorsByKey[k] || [];
          contributorsByKey[k].push({ value: numeric, weight: effectiveWeights[i] });
        }
      }

      for (const [k, contribs] of Object.entries(contributorsByKey)) {
        const wSum = contribs.reduce((a, b) => a + b.weight, 0);
        if (wSum <= 0) continue;
        synthesized[k] = contribs.reduce((acc, c) => acc + c.value * (c.weight / wSum), 0);
      }

      // Recommend an action based on synthesized signals (simple rules)
      let recommendedAction = "no_action";
      let rationale = "no triggering thresholds crossed";
      if ((synthesized.demand_kw || 0) > 900 && (synthesized.rate_per_kwh || 0) > 0.15) {
        recommendedAction = "throttle_charger";
        rationale = "high demand + peak tariff";
      } else if ((synthesized.demand_kw || 0) > 1000) {
        recommendedAction = "defer_charge";
        rationale = "demand approaching cap";
      } else if ((synthesized.event_present || 0) > 0.5) {
        recommendedAction = "alert_ops";
        rationale = "external event signal";
      }

      return ok({
        simulated: true,
        fusion_method: method,
        input_signal_count: signals.length,
        effective_weights: normalized,
        synthesized_observation: synthesized,
        recommended_action: recommendedAction,
        rationale,
        confidence: +geomMean.toFixed(3),
        note: "This is a simulation — nothing was persisted or executed.",
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/decision-fusion/log
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/decision-fusion/log") {
      const depotId = url.searchParams.get("depot_id");
      const limit = parseInt(url.searchParams.get("limit") || "20");

      let q = supabase
        .from("decision_fusion_log")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(limit);

      if (depotId) q = q.eq("depot_id", depotId);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      return ok({
        decisions: data || [],
        count: (data || []).length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/features/fleet-aggregates
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/features/fleet-aggregates") {
      const group = url.searchParams.get("feature_group");
      const scope = url.searchParams.get("scope");
      const scopeId = url.searchParams.get("scope_id");
      const featureDate = url.searchParams.get("date");
      const limit = parseInt(url.searchParams.get("limit") || "50");

      let q = supabase
        .from("fleet_features_daily")
        .select("*")
        .order("feature_date", { ascending: false })
        .limit(limit);

      if (group) q = q.eq("feature_group", group);
      if (scope) q = q.eq("scope", scope);
      if (scopeId) q = q.eq("scope_id", scopeId);
      if (featureDate) q = q.eq("feature_date", featureDate);

      const { data, error } = await q;
      if (error) return err("INTERNAL", error.message, 500);

      return ok({
        features: data || [],
        count: (data || []).length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ai/engine-health
    // One-stop diagnostic: are external sources healthy? how fresh is the
    // most recent snapshot? how many data-quality errors? how many SLOs are
    // breached? which model versions are active? This is the surface a
    // partner engineer reads first.
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ai/engine-health") {
      const depotId = url.searchParams.get("depot_id");

      // Snapshot freshness
      let snapQ = supabase
        .from("depot_state_snapshots")
        .select("snapshot_at, depot_id")
        .order("snapshot_at", { ascending: false })
        .limit(1);
      if (depotId) snapQ = snapQ.eq("depot_id", depotId);
      const { data: latestSnap } = await snapQ.maybeSingle();

      const snapAgeMin = latestSnap?.snapshot_at
        ? Math.round((Date.now() - new Date(latestSnap.snapshot_at).getTime()) / 60000)
        : null;

      // External source health
      let srcQ = supabase
        .from("external_factor_sources")
        .select("factor_type, health_status, is_active, last_success_at, consecutive_failures");
      if (depotId) srcQ = srcQ.or(`depot_id.eq.${depotId},depot_id.is.null`);
      const { data: sources } = await srcQ;

      const sourceHealth: Record<string, any> = {};
      for (const s of sources || []) {
        sourceHealth[s.factor_type] = sourceHealth[s.factor_type] || {
          healthy: 0, degraded: 0, stale: 0, down: 0, unknown: 0, total: 0,
        };
        sourceHealth[s.factor_type].total++;
        sourceHealth[s.factor_type][s.health_status] =
          (sourceHealth[s.factor_type][s.health_status] || 0) + 1;
      }

      // Data quality errors (last 24h, unresolved)
      const since24h = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
      let dqQ = supabase
        .from("data_quality_errors")
        .select("severity", { count: "exact", head: false })
        .is("resolved_at", null)
        .gte("detected_at", since24h);
      if (depotId) dqQ = dqQ.eq("depot_id", depotId);
      const { data: dqErrors } = await dqQ;
      const dqBySeverity: Record<string, number> = {};
      for (const e of dqErrors || []) {
        dqBySeverity[e.severity] = (dqBySeverity[e.severity] || 0) + 1;
      }

      // Unresolved alerts
      let alertsQ = supabase
        .from("accuracy_alerts")
        .select("severity, prediction_type")
        .is("resolved_at", null)
        .order("observed_at", { ascending: false })
        .limit(20);
      if (depotId) alertsQ = alertsQ.eq("depot_id", depotId);
      const { data: alerts } = await alertsQ;

      // Active model versions
      let mvQ = supabase
        .from("model_versions")
        .select("parameter_group, version_tag, version_number, source, promoted_to_active_at")
        .eq("status", "active");
      if (depotId) mvQ = mvQ.eq("depot_id", depotId);
      const { data: activeVersions } = await mvQ;

      // Running A/B tests
      let abQ = supabase
        .from("ab_tests")
        .select("id, parameter_group, test_name, started_at, variant_a_samples, variant_b_samples")
        .eq("status", "running");
      if (depotId) abQ = abQ.eq("depot_id", depotId);
      const { data: runningTests } = await abQ;

      // SLO health
      let slosQ = supabase
        .from("accuracy_slos")
        .select("prediction_type, time_horizon_hours, slo_target, is_active")
        .eq("is_active", true);
      if (depotId) slosQ = slosQ.or(`depot_id.eq.${depotId},depot_id.is.null`);
      const { data: slos } = await slosQ;

      // Implemented action contracts
      const { data: contracts } = await supabase
        .from("downstream_action_contracts")
        .select("action_type, is_implemented");
      const implementedContracts = (contracts || []).filter(c => c.is_implemented).length;
      const totalContracts = (contracts || []).length;

      // Compute overall health verdict
      const snapHealthy = snapAgeMin != null && snapAgeMin < 60;
      const noCriticalDQ = (dqBySeverity.critical || 0) === 0;
      const noCriticalAlerts = (alerts || []).filter((a: any) => a.severity === "critical").length === 0;
      const sourcesOk = Object.values(sourceHealth).every((h: any) => h.down === 0);

      const verdict =
        snapHealthy && noCriticalDQ && noCriticalAlerts && sourcesOk
          ? "healthy"
          : snapHealthy && noCriticalAlerts
          ? "degraded"
          : "warming_up";

      return ok({
        as_of: new Date().toISOString(),
        depot_id: depotId || null,
        verdict,
        snapshot: {
          latest_snapshot_at: latestSnap?.snapshot_at || null,
          age_minutes: snapAgeMin,
          healthy: snapHealthy,
        },
        external_sources: sourceHealth,
        data_quality: {
          unresolved_24h: (dqErrors || []).length,
          by_severity: dqBySeverity,
        },
        accuracy_alerts: {
          unresolved: (alerts || []).length,
          by_severity: (alerts || []).reduce((acc: any, a: any) => {
            acc[a.severity] = (acc[a.severity] || 0) + 1; return acc;
          }, {}),
        },
        active_models: (activeVersions || []).map((v: any) => ({
          parameter_group: v.parameter_group,
          version_tag: v.version_tag,
          version_number: v.version_number,
          source: v.source,
          promoted_at: v.promoted_to_active_at,
        })),
        ab_tests_running: (runningTests || []).length,
        ab_tests: runningTests || [],
        slos_active: (slos || []).length,
        downstream_contracts: {
          total: totalContracts,
          implemented: implementedContracts,
          coverage_pct: totalContracts > 0
            ? +(implementedContracts / totalContracts * 100).toFixed(1)
            : 0,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ai/score-pending
    // Batch-score predictions whose horizon has elapsed. Intended for cron.
    // Writes rows into prediction_outcomes by comparing predicted vs actual.
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ai/score-pending") {
      const body = await req.json().catch(() => ({} as any));
      const depotId = body?.depot_id;
      const batchSize = body?.batch_size || 50;

      // Pull predictions whose time_horizon_hours has passed and that have no
      // outcome row yet.
      let q = supabase
        .from("ottoq_predictions")
        .select("id, depot_id, prediction_type, time_horizon_hours, predicted_value, created_at, confidence")
        .not("time_horizon_hours", "is", null)
        .limit(batchSize);

      if (depotId) q = q.eq("depot_id", depotId);

      const { data: preds, error: predErr } = await q;
      if (predErr) return err("INTERNAL", predErr.message, 500);

      const now = Date.now();
      const ready: any[] = [];
      for (const p of preds || []) {
        const horizonMs = (p.time_horizon_hours || 0) * 3600 * 1000;
        const horizonEnd = new Date(p.created_at).getTime() + horizonMs;
        if (horizonEnd < now) ready.push(p);
      }

      // Skip any that already have outcomes
      const readyIds = ready.map(r => r.id);
      if (readyIds.length === 0) {
        return ok({
          scored: 0,
          candidates: preds?.length || 0,
          ready: 0,
          note: "no predictions past their horizon",
        }, startTime);
      }

      const { data: existing } = await supabase
        .from("prediction_outcomes")
        .select("prediction_id")
        .in("prediction_id", readyIds);
      const alreadyScored = new Set((existing || []).map((e: any) => e.prediction_id));

      const pendingScoring = ready.filter(r => !alreadyScored.has(r.id));

      let written = 0;
      for (const p of pendingScoring) {
        // Use predicted_value as baseline; since we don't have ground truth
        // wired yet, score against the snapshot-at-horizon as a proxy.
        const { data: horizonSnap } = await supabase
          .from("depot_state_snapshots")
          .select("*")
          .eq("depot_id", p.depot_id)
          .order("snapshot_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (!horizonSnap) continue;

        // Simple MAPE-style scoring. Adjust per prediction_type as ground
        // truth sources mature (ocpp_sessions, completed tasks, etc.).
        const predVal = (p.predicted_value as any) || {};
        let accuracy = 0.5;  // neutral if we can't compare

        if (typeof predVal.expected_demand_kw === "number" && horizonSnap.current_demand_kw != null) {
          const mape = Math.abs(predVal.expected_demand_kw - horizonSnap.current_demand_kw)
            / Math.max(1, horizonSnap.current_demand_kw);
          accuracy = Math.max(0, 1 - mape);
        } else if (typeof predVal.expected_vehicles === "number") {
          const mape = Math.abs(predVal.expected_vehicles - horizonSnap.vehicles_on_site)
            / Math.max(1, horizonSnap.vehicles_on_site);
          accuracy = Math.max(0, 1 - mape);
        } else {
          // Use confidence as proxy when we truly can't score
          accuracy = p.confidence || 0.5;
        }

        await supabase.from("prediction_outcomes").insert({
          prediction_id: p.id,
          depot_id: p.depot_id,
          predicted_value: p.predicted_value,
          actual_value: {
            demand_kw: horizonSnap.current_demand_kw,
            vehicles_on_site: horizonSnap.vehicles_on_site,
            derived_from_snapshot_id: horizonSnap.id,
          },
          accuracy_score: Math.min(1, Math.max(0, accuracy)),
          scoring_method: "mape",
          time_horizon_hours: p.time_horizon_hours,
          prediction_type: p.prediction_type,
          scoring_delay_ms: Date.now() - new Date(p.created_at).getTime(),
          notes: "scored via proxy snapshot — upgrade to real ground truth as data sources mature",
        });
        written++;
      }

      return ok({
        scored: written,
        candidates: preds?.length || 0,
        ready: ready.length,
        already_scored: alreadyScored.size,
      }, startTime);
    }


    // -----------------------------------------------------------------------
    // POST /api/v1/av/arrival
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/av/arrival") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const vehicle = await store.getVehicleByAVId(body.platform, body.av_api_vehicle_id || body.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", `Vehicle not found for ${body.platform}:${body.av_api_vehicle_id}`, 404);

      if (body.soc_percent !== undefined) {
        await store.updateVehicle(vehicle.id, { current_soc: body.soc_percent });
      }

      await store.updateVehicleState(vehicle.id, "arrived_at_gate", null, "vehicle_telemetry");

      return ok({
        vehicle_id: vehicle.id,
        new_state: "arrived_at_gate",
        processed: true,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/av/telemetry
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/av/telemetry") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const vehicle = await store.getVehicleByAVId(body.platform, body.av_api_vehicle_id);
      if (!vehicle) return err("NOT_FOUND", `Vehicle not found`, 404);

      const updates: any = {};
      if (body.soc_percent !== undefined) updates.current_soc = body.soc_percent;
      updates.last_state_change = new Date().toISOString();

      if (Object.keys(updates).length > 0) {
        await store.updateVehicle(vehicle.id, updates);
      }

      return ok({
        vehicle_id: vehicle.id,
        updates_applied: Object.keys(updates).length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/retail/book
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/retail/book") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      if (!body.vehicle_id || !body.depot_id || !body.requested_date || !body.services?.length) {
        return err("VALIDATION_ERROR", "vehicle_id, depot_id, requested_date, and services required", 400);
      }

      const arrivalTime = body.requested_time
        ? `${body.requested_date}T${body.requested_time}`
        : `${body.requested_date}T10:00:00`;

      const schedule = await store.createSchedule({
        vehicle_id: body.vehicle_id,
        depot_id: body.depot_id,
        scheduled_date: body.requested_date,
        arrival_time: arrivalTime,
        departure_time: arrivalTime, // placeholder
        priority: "standard",
        is_priority_override: false,
        override_fee: 0,
        status: "confirmed",
        planned_services: body.services,
      });

      return ok({ booked: true, schedule_id: schedule?.id, arrival_time: arrivalTime }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/retail/:id/vehicle-status
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/retail\/[^/]+\/vehicle-status$/.test(path)) {
      const vehicleId = path.split("/")[4];
      const vehicle = await store.getVehicle(vehicleId);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${vehicleId} not found`, 404);

      const today = new Date().toISOString().split("T")[0];
      const schedule = await store.getScheduleForVehicle(vehicleId, today);
      const tasks = schedule ? await store.getTasksBySchedule(schedule.id) : [];

      const STATE_DESC: Record<string, string> = {
        en_route_to_depot: "Your vehicle is on its way to the depot",
        arrived_at_gate: "Your vehicle has arrived",
        staged_awaiting_service: "Waiting for service to begin",
        charging_dcfc: "Fast charging in progress",
        charging_l2: "Charging (Level 2)",
        in_wash_bay: "Being washed",
        in_detail_bay: "Being detailed",
        in_service_bay: "Being serviced",
        staged_for_departure: "Ready for pickup!",
      };

      return ok({
        vehicle_id: vehicleId,
        display_name: vehicle.display_name || vehicle.vin,
        state: vehicle.current_state,
        state_description: STATE_DESC[vehicle.current_state] || vehicle.current_state,
        soc: vehicle.current_soc,
        progress: {
          completed: tasks.filter((t: any) => t.status === "completed").length,
          total: tasks.length,
          current_service: tasks.find((t: any) => t.status === "in_progress")?.service_definition_id || null,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/charger/status-notification
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/charger/status-notification") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      return ok({
        charge_point_id: body.charge_point_id,
        connector_status: body.connector_status,
        processed: true,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/charger/transaction-event
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/charger/transaction-event") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      return ok({
        transaction_id: body.transaction_info?.transaction_id,
        event_type: body.event_type,
        processed: true,
      }, startTime);
    }

    // =====================================================================
    // OTTOW DISPATCH SYSTEM — Route Handlers
    // =====================================================================

    // =====================================================================
    // OTTOW NOTIFICATION INGESTION & AUTO-DISPATCH
    // =====================================================================

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/notifications/ingest — Receive incident notification
    // Accepts: OEM webhooks (via API key), fleet APIs, OTTO-Q engine, manual
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ottow/notifications/ingest") {
      const body = await req.json();

      // Determine source and depot
      const source = authenticatedSource?.source || body.source || "manual_dispatch";
      const depotId = authenticatedSource?.depot_id || body.depot_id;
      if (!depotId) return err("VALIDATION_ERROR", "depot_id required");

      // Require API key for external sources
      if (["oem_webhook", "fleet_api", "vehicle_telemetry"].includes(source) && !authenticatedSource) {
        return err("UNAUTHORIZED", "External sources require X-OTTO-Q-API-Key header", 401);
      }

      // Resolve vehicle
      const vehicle = await resolveVehicle(body);
      if (!vehicle) return err("NOT_FOUND", "Could not resolve vehicle from provided identifiers");
      const vehicleId = vehicle.id;

      const incidentCategory = body.incident_category || "other";
      const priority = body.priority || "standard";

      // Dedup: vehicle_id + category + 30-min time bucket
      const timeBucket = Math.floor(Date.now() / 1800000);
      const dedupKey = `${vehicleId}:${incidentCategory}:${timeBucket}`;

      // Check for existing
      const existing = await store.getNotificationByDedupKey(dedupKey);
      if (existing) {
        return json({
          data: {
            notification: existing,
            deduplicated: true,
            message: "Existing notification found for this vehicle and incident within the time window",
          },
          meta: { request_id: correlationId(), timestamp: new Date().toISOString(), processing_ms: Date.now() - startTime },
        }, 200);
      }

      // Insert notification
      const notification = await store.createNotification({
        depot_id: depotId,
        source,
        external_reference_id: body.external_reference_id || null,
        webhook_payload: body.raw_payload || (authenticatedSource ? body : null),
        status: "pending",
        vehicle_id: vehicleId,
        vehicle_platform: body.vehicle_platform || vehicle.platform,
        vehicle_external_id: body.vehicle_external_id || vehicle.av_api_vehicle_id,
        vehicle_vin: body.vehicle_vin || vehicle.vin,
        incident_category: incidentCategory,
        priority,
        incident_lat: body.incident_lat || null,
        incident_lng: body.incident_lng || null,
        incident_address: body.incident_address || null,
        description: body.description || null,
        exception_id: body.exception_id || null,
        dedup_key: dedupKey,
      });

      // Run auto-dispatch rules engine
      const decision = await evaluateAutoDispatch(notification);
      let mission = null;

      if (decision.action === "auto_dispatch") {
        // Create mission automatically
        mission = await createMissionFromNotification(notification, decision.driver || null);
        await store.updateNotification(notification.id, {
          status: "mission_created",
          acknowledged_at: new Date().toISOString(),
          auto_dispatch_eligible: true,
          auto_dispatch_reason: decision.reason,
          mission_id: mission.id,
        });
      } else if (decision.action === "reject") {
        await store.updateNotification(notification.id, {
          status: "rejected",
          rejection_reason: decision.reason,
          auto_dispatch_reason: decision.reason,
        });
      } else {
        // queue_for_review or alert_ops
        await store.updateNotification(notification.id, {
          auto_dispatch_reason: decision.reason,
        });
      }

      const updated = await store.getNotification(notification.id);

      return json({
        data: {
          notification: updated,
          deduplicated: false,
          dispatch_decision: {
            action: decision.action,
            reason: decision.reason,
            mission_id: mission?.id || null,
            driver_assigned: !!decision.driver,
          },
        },
        meta: { request_id: correlationId(), timestamp: new Date().toISOString(), processing_ms: Date.now() - startTime },
      }, 201);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/notifications — List notifications for a depot
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ottow/notifications") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("VALIDATION_ERROR", "depot_id required");
      const statusFilter = url.searchParams.get("status") || undefined;
      const limit = parseInt(url.searchParams.get("limit") || "50");

      const notifications = await store.getNotificationsByDepot(depotId, { status: statusFilter, limit });

      return ok({ depot_id: depotId, notifications, count: notifications.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/notifications/:id — Get notification detail
    // -----------------------------------------------------------------------
    const notifDetailMatch = path.match(/^\/api\/v1\/ottow\/notifications\/([^/]+)$/);
    if (method === "GET" && notifDetailMatch) {
      const notification = await store.getNotification(notifDetailMatch[1]);
      if (!notification) return err("NOT_FOUND", "Notification not found");
      return ok({ notification }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/notifications/:id/acknowledge — Accept into queue
    // -----------------------------------------------------------------------
    const notifAckMatch = path.match(/^\/api\/v1\/ottow\/notifications\/([^/]+)\/acknowledge$/);
    if (method === "POST" && notifAckMatch) {
      const notification = await store.getNotification(notifAckMatch[1]);
      if (!notification) return err("NOT_FOUND", "Notification not found");
      if (notification.status !== "pending") return err("INVALID_STATE", `Cannot acknowledge notification in '${notification.status}' state`);

      const body = await req.json().catch(() => ({}));
      const updated = await store.updateNotification(notification.id, {
        status: "acknowledged",
        acknowledged_at: new Date().toISOString(),
        reviewed_by_user_id: body.reviewed_by_user_id || null,
        reviewed_at: new Date().toISOString(),
      });

      return ok({ notification: updated }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/notifications/:id/create-mission — Convert to mission
    // -----------------------------------------------------------------------
    const notifMissionMatch = path.match(/^\/api\/v1\/ottow\/notifications\/([^/]+)\/create-mission$/);
    if (method === "POST" && notifMissionMatch) {
      const notification = await store.getNotification(notifMissionMatch[1]);
      if (!notification) return err("NOT_FOUND", "Notification not found");
      if (notification.status === "mission_created") return err("INVALID_STATE", "Mission already created from this notification");
      if (notification.status === "rejected") return err("INVALID_STATE", "Cannot create mission from rejected notification");

      const body = await req.json().catch(() => ({}));

      // Optionally assign a driver
      let driver = null;
      if (body.driver_staff_id) {
        driver = await store.getDriverByStaffId(body.driver_staff_id);
        if (!driver || driver.status !== "available") return err("VALIDATION_ERROR", "Driver not available");
      }

      const mission = await createMissionFromNotification(notification, driver);

      await store.updateNotification(notification.id, {
        status: "mission_created",
        acknowledged_at: notification.acknowledged_at || new Date().toISOString(),
        mission_id: mission.id,
      });

      return ok({
        notification_id: notification.id,
        mission_id: mission.id,
        status: mission.status,
        driver_assigned: !!driver,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/notifications/:id/reject — Reject notification
    // -----------------------------------------------------------------------
    const notifRejectMatch = path.match(/^\/api\/v1\/ottow\/notifications\/([^/]+)\/reject$/);
    if (method === "POST" && notifRejectMatch) {
      const notification = await store.getNotification(notifRejectMatch[1]);
      if (!notification) return err("NOT_FOUND", "Notification not found");
      if (notification.status === "mission_created") return err("INVALID_STATE", "Cannot reject — mission already created");

      const body = await req.json();
      if (!body.reason) return err("VALIDATION_ERROR", "rejection reason required");

      const updated = await store.updateNotification(notification.id, {
        status: "rejected",
        rejection_reason: body.reason,
        reviewed_by_user_id: body.reviewed_by_user_id || null,
        reviewed_at: new Date().toISOString(),
      });

      return ok({ notification: updated }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/dispatch-rules — List auto-dispatch rules
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ottow/dispatch-rules") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("VALIDATION_ERROR", "depot_id required");
      const rules = await store.getDispatchRules(depotId);
      return ok({ depot_id: depotId, rules, count: rules.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/dispatch-rules — Create a dispatch rule
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ottow/dispatch-rules") {
      const body = await req.json();
      if (!body.depot_id || !body.rule_name || !body.action) return err("VALIDATION_ERROR", "depot_id, rule_name, and action required");
      const rule = await store.createDispatchRule(body);
      return json({ data: { rule } }, 201);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/api-keys — Create an API key (returns key once)
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ottow/api-keys") {
      const body = await req.json();
      if (!body.depot_id || !body.source || !body.source_name) {
        return err("VALIDATION_ERROR", "depot_id, source, and source_name required");
      }

      // Generate random API key
      const keyBytes = new Uint8Array(32);
      crypto.getRandomValues(keyBytes);
      const plainKey = "ottow_" + Array.from(keyBytes).map(b => b.toString(16).padStart(2, "0")).join("");
      const keyHash = await sha256(plainKey);
      const keyPrefix = plainKey.substring(0, 14);

      const apiKey = await store.createApiKey({
        depot_id: body.depot_id,
        key_hash: keyHash,
        key_prefix: keyPrefix,
        source: body.source,
        source_name: body.source_name,
        allowed_platforms: body.allowed_platforms || null,
        created_by_user_id: body.created_by_user_id || null,
      });

      return json({
        data: {
          api_key: {
            id: apiKey.id,
            key: plainKey, // Only time the full key is returned
            key_prefix: keyPrefix,
            source: apiKey.source,
            source_name: apiKey.source_name,
          },
          warning: "Store this key securely — it will not be shown again.",
        },
      }, 201);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/api-keys — List API keys (prefix only, never full key)
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ottow/api-keys") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("VALIDATION_ERROR", "depot_id required");
      const keys = await store.getApiKeysByDepot(depotId);
      return ok({ depot_id: depotId, api_keys: keys, count: keys.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // DELETE /api/v1/ottow/api-keys/:id — Revoke an API key
    // -----------------------------------------------------------------------
    const apiKeyDeleteMatch = path.match(/^\/api\/v1\/ottow\/api-keys\/([^/]+)$/);
    if (method === "DELETE" && apiKeyDeleteMatch) {
      await store.deactivateApiKey(apiKeyDeleteMatch[1]);
      return ok({ revoked: true }, startTime);
    }

    // =====================================================================
    // OTTOW MISSION MANAGEMENT (existing endpoints)
    // =====================================================================

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions — Create a new OTTOW dispatch mission
    // -----------------------------------------------------------------------
    if (method === "POST" && path === "/api/v1/ottow/missions") {
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      if (!body.depot_id || !body.vehicle_id) {
        return err("VALIDATION_ERROR", "depot_id and vehicle_id are required", 400);
      }

      const vehicle = await store.getVehicle(body.vehicle_id);
      if (!vehicle) return err("NOT_FOUND", `Vehicle ${body.vehicle_id} not found`, 404);

      // Determine priority from exception severity if linked
      let priority = body.priority || "standard";
      let incidentCategory = body.incident_category || "other";

      if (body.exception_id) {
        const { data: exception } = await supabase.from("exceptions").select("*").eq("id", body.exception_id).single();
        if (exception) {
          if (exception.severity === "critical") priority = "critical";
          else if (exception.severity === "high") priority = "high";
          // Map exception_type to incident_category
          const typeMap: Record<string, string> = {
            safety_concern: "battery_thermal",
            malfunction: "mechanical",
            charger_fault: "charger_fault",
            sensor_anomaly: "sensor_failure",
            interior: "interior_damage",
          };
          incidentCategory = typeMap[exception.exception_type] || incidentCategory;
        }
      }

      const mission = await store.createMission({
        depot_id: body.depot_id,
        exception_id: body.exception_id || null,
        vehicle_id: body.vehicle_id,
        driver_staff_id: body.driver_staff_id || null,
        ottow_vehicle_id: body.ottow_vehicle_id || null,
        status: body.driver_staff_id ? "dispatched" : "reported",
        priority,
        incident_category: incidentCategory,
        pickup_location_lat: body.pickup_lat || null,
        pickup_location_lng: body.pickup_lng || null,
        pickup_address: body.pickup_address || null,
        pickup_notes: body.pickup_notes || null,
        eta_minutes: body.eta_minutes || null,
        distance_miles: body.distance_miles || null,
        notes: body.notes || null,
        dispatched_at: body.driver_staff_id ? new Date().toISOString() : null,
      });

      // Log creation event
      await store.createMissionEvent({
        mission_id: mission.id,
        event_type: "status_change",
        from_status: null,
        to_status: mission.status,
        actor_id: body.dispatched_by_user_id || null,
        actor_type: "dispatcher",
        notes: `Mission created for vehicle ${vehicle.display_name || vehicle.vin}`,
        metadata: { vehicle_id: body.vehicle_id, exception_id: body.exception_id },
      });

      // If driver was assigned immediately, update driver status
      if (body.driver_staff_id) {
        await store.updateDriverByStaffId(body.driver_staff_id, {
          status: "on_mission",
          current_mission_id: mission.id,
        });

        await store.createMissionEvent({
          mission_id: mission.id,
          event_type: "driver_assigned",
          actor_id: body.dispatched_by_user_id || null,
          actor_type: "dispatcher",
          metadata: { driver_staff_id: body.driver_staff_id },
        });
      }

      // Update exception status if linked
      if (body.exception_id) {
        await supabase.from("exceptions").update({ status: "investigating" }).eq("id", body.exception_id);
      }

      // Update vehicle state to reflect tow dispatch
      await store.updateVehicleState(
        body.vehicle_id,
        "ottow_dispatched",
        null,
        "ottow_system",
        body.dispatched_by_user_id,
        { mission_id: mission.id },
      );

      return ok({
        mission_id: mission.id,
        status: mission.status,
        priority,
        incident_category: incidentCategory,
        vehicle: {
          id: vehicle.id,
          display_name: vehicle.display_name,
          vin: vehicle.vin,
          platform: vehicle.platform,
          current_soc: vehicle.current_soc,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/missions — List missions for a depot
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ottow/missions") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const statusFilter = url.searchParams.get("status") || "active";
      const missions = await store.getMissionsByDepot(depotId, { status: statusFilter });

      // Enrich with vehicle and driver info
      const enriched = await Promise.all(missions.map(async (m: any) => {
        const vehicle = await store.getVehicle(m.vehicle_id);
        let driverName = null;
        if (m.driver_staff_id) {
          const { data: staff } = await supabase.from("staff_users").select("first_name, last_name, display_name")
            .eq("id", m.driver_staff_id).single();
          driverName = staff?.display_name || `${staff?.first_name} ${staff?.last_name}`;
        }
        const destStall = m.destination_stall_id ? await store.getStall(m.destination_stall_id) : null;

        return {
          id: m.id,
          status: m.status,
          priority: m.priority,
          incident_category: m.incident_category,
          vehicle: {
            id: vehicle?.id,
            display_name: vehicle?.display_name || vehicle?.vin,
            platform: vehicle?.platform,
            current_soc: vehicle?.current_soc,
          },
          driver_name: driverName,
          driver_staff_id: m.driver_staff_id,
          pickup_address: m.pickup_address,
          pickup_lat: m.pickup_location_lat,
          pickup_lng: m.pickup_location_lng,
          destination_stall: destStall ? {
            id: destStall.id,
            stall_code: destStall.stall_code,
            stall_type: destStall.stall_type,
          } : null,
          eta_minutes: m.eta_minutes,
          driver_location: m.driver_lat ? {
            lat: m.driver_lat,
            lng: m.driver_lng,
            heading: m.driver_heading,
            speed_mph: m.driver_speed_mph,
            updated_at: m.driver_location_updated_at,
          } : null,
          created_at: m.created_at,
          dispatched_at: m.dispatched_at,
          en_route_at: m.en_route_at,
          on_site_at: m.on_site_at,
          vehicle_secured_at: m.vehicle_secured_at,
          returning_at: m.returning_at,
          arrived_depot_at: m.arrived_depot_at,
          stall_assigned_at: m.stall_assigned_at,
          vehicle_delivered_at: m.vehicle_delivered_at,
          closed_at: m.closed_at,
        };
      }));

      return ok({ depot_id: depotId, missions: enriched, count: enriched.length }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/missions/:id — Get full mission detail with events
    // -----------------------------------------------------------------------
    if (method === "GET" && /^\/api\/v1\/ottow\/missions\/[^/]+$/.test(path)) {
      const missionId = path.split("/")[5];
      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      const vehicle = await store.getVehicle(mission.vehicle_id);
      const events = await store.getMissionEvents(missionId);
      const destStall = mission.destination_stall_id ? await store.getStall(mission.destination_stall_id) : null;

      let driverInfo = null;
      if (mission.driver_staff_id) {
        const { data: staff } = await supabase.from("staff_users").select("*")
          .eq("id", mission.driver_staff_id).single();
        driverInfo = staff ? {
          staff_id: staff.id,
          name: staff.display_name || `${staff.first_name} ${staff.last_name}`,
          role: staff.role,
        } : null;
      }

      // Calculate stage durations
      const stageDurations: Record<string, number | null> = {};
      const timestamps: Record<string, string | null> = {
        reported: mission.created_at,
        dispatched: mission.dispatched_at,
        en_route: mission.en_route_at,
        on_site: mission.on_site_at,
        vehicle_secured: mission.vehicle_secured_at,
        returning: mission.returning_at,
        arrived_depot: mission.arrived_depot_at,
        stall_assigned: mission.stall_assigned_at,
        vehicle_delivered: mission.vehicle_delivered_at,
        closed: mission.closed_at,
      };

      const stageOrder = ["reported","dispatched","en_route","on_site","vehicle_secured","returning","arrived_depot","stall_assigned","vehicle_delivered","closed"];
      for (let i = 0; i < stageOrder.length - 1; i++) {
        const from = timestamps[stageOrder[i]];
        const to = timestamps[stageOrder[i + 1]];
        if (from && to) {
          stageDurations[stageOrder[i]] = Math.round((new Date(to).getTime() - new Date(from).getTime()) / 1000);
        }
      }

      return ok({
        mission: {
          ...mission,
          vehicle: vehicle ? {
            id: vehicle.id,
            display_name: vehicle.display_name || vehicle.vin,
            vin: vehicle.vin,
            platform: vehicle.platform,
            make: vehicle.make,
            model: vehicle.model,
            year: vehicle.year,
            current_soc: vehicle.current_soc,
            current_state: vehicle.current_state,
          } : null,
          driver: driverInfo,
          destination_stall: destStall ? {
            id: destStall.id,
            stall_code: destStall.stall_code,
            stall_type: destStall.stall_type,
            zone: destStall.zone,
            relative_x: destStall.relative_x,
            relative_y: destStall.relative_y,
          } : null,
          stage_durations_seconds: stageDurations,
        },
        events,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/assign — Assign a driver
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/assign$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);
      if (!body.driver_staff_id) return err("VALIDATION_ERROR", "driver_staff_id required", 400);

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);
      if (mission.status !== "reported") {
        return err("CONFLICT", `Cannot assign driver: mission is ${mission.status}, expected reported`, 409);
      }

      // Check driver is available
      const driver = await store.getDriverByStaffId(body.driver_staff_id);
      if (!driver) return err("NOT_FOUND", `Driver not found for staff ${body.driver_staff_id}`, 404);
      if (driver.status !== "available") {
        return err("CONFLICT", `Driver is ${driver.status}, not available`, 409);
      }

      const now = new Date().toISOString();

      await store.updateMission(missionId, {
        driver_staff_id: body.driver_staff_id,
        ottow_vehicle_id: body.ottow_vehicle_id || null,
        status: "dispatched",
        dispatched_at: now,
      });

      await store.updateDriver(driver.id, {
        status: "on_mission",
        current_mission_id: missionId,
      });

      await store.createMissionEvent({
        mission_id: missionId,
        event_type: "driver_assigned",
        from_status: "reported",
        to_status: "dispatched",
        actor_id: body.assigned_by_user_id || null,
        actor_type: "dispatcher",
        metadata: { driver_staff_id: body.driver_staff_id, ottow_vehicle_id: body.ottow_vehicle_id },
      });

      // Notify driver
      await store.queueNotification({
        depot_id: mission.depot_id,
        recipient_type: "staff",
        recipient_id: body.driver_staff_id,
        event_type: "ottow_dispatch",
        title: "OTTOW Mission Assigned",
        body: `Dispatch to retrieve vehicle. Priority: ${mission.priority}`,
        vehicle_id: mission.vehicle_id,
        channels: ["push", "in_app"],
      });

      return ok({ mission_id: missionId, status: "dispatched", driver_staff_id: body.driver_staff_id }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/stage — Advance mission stage
    // -----------------------------------------------------------------------
    // Called by the driver app to progress through the lifecycle.
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/stage$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);
      if (!body.to_status) return err("VALIDATION_ERROR", "to_status required", 400);

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      const currentStatus = mission.status;
      const targetStatus = body.to_status;

      // Validate transition
      const allowed = VALID_TRANSITIONS[currentStatus];
      if (!allowed || !allowed.includes(targetStatus)) {
        return err("INVALID_TRANSITION", `Cannot transition from ${currentStatus} to ${targetStatus}`, 409, {
          current_status: currentStatus,
          allowed_transitions: allowed || [],
        });
      }

      // Cancellation check
      if (targetStatus === "cancelled" && NO_CANCEL_STAGES.includes(currentStatus)) {
        return err("CANCEL_NOT_ALLOWED", `Cannot cancel mission in ${currentStatus} stage — vehicle is en route to depot`, 409);
      }

      const now = new Date().toISOString();
      const updates: any = {
        status: targetStatus,
        [`${targetStatus}_at`]: now,
      };

      // Handle cancellation
      if (targetStatus === "cancelled") {
        updates.cancellation_reason = body.reason || "Driver/dispatcher cancelled";
        updates.cancelled_at = now;
      }

      // Update driver location if provided
      if (body.location) {
        updates.driver_lat = body.location.lat;
        updates.driver_lng = body.location.lng;
        updates.driver_heading = body.location.heading;
        updates.driver_speed_mph = body.location.speed_mph;
        updates.driver_location_updated_at = now;
      }

      // Update ETA if provided
      if (body.eta_minutes !== undefined) {
        updates.eta_minutes = body.eta_minutes;
      }

      await store.updateMission(missionId, updates);

      // Log the stage transition
      await store.createMissionEvent({
        mission_id: missionId,
        event_type: "status_change",
        from_status: currentStatus,
        to_status: targetStatus,
        location_lat: body.location?.lat,
        location_lng: body.location?.lng,
        actor_id: body.actor_id || mission.driver_staff_id,
        actor_type: body.actor_type || "driver",
        notes: body.notes || null,
        client_timestamp: body.client_timestamp || null,
        metadata: body.metadata || {},
      });

      // === Stage-specific side effects ===

      // When returning: pre-assign a stall
      if (targetStatus === "returning") {
        const stall = await assignStallForOTTOW(mission.depot_id, missionId, mission.incident_category);
        if (stall) {
          await store.updateMission(missionId, {
            destination_stall_id: stall.id,
            destination_stall_type: stall.stall_type,
            status: "stall_assigned",
            stall_assigned_at: now,
          });

          await store.createMissionEvent({
            mission_id: missionId,
            event_type: "stall_assigned",
            from_status: "returning",
            to_status: "stall_assigned",
            actor_type: "otto_q_engine",
            notes: `Auto-assigned stall ${stall.stall_code} (${stall.stall_type})`,
            metadata: { stall_id: stall.id, stall_code: stall.stall_code, stall_type: stall.stall_type },
          });
        }
      }

      // When vehicle delivered: update stall, vehicle state, and complete the circuit
      if (targetStatus === "vehicle_delivered") {
        if (mission.destination_stall_id) {
          // Occupy the stall
          await store.updateStall(mission.destination_stall_id, {
            status: "occupied",
            current_vehicle_id: mission.vehicle_id,
            reserved_for_mission_id: null,
          });

          // Update vehicle state based on incident category
          const newVehicleState = VEHICLE_STATE_ON_DELIVERY[mission.incident_category] || "staging";
          await store.updateVehicleState(
            mission.vehicle_id,
            newVehicleState,
            mission.destination_stall_id,
            "ottow_system",
            mission.driver_staff_id,
            { mission_id: missionId },
          );
        }

        // Notify ops
        const vehicle = await store.getVehicle(mission.vehicle_id);
        const stall = mission.destination_stall_id ? await store.getStall(mission.destination_stall_id) : null;
        await store.queueNotification({
          depot_id: mission.depot_id,
          recipient_type: "staff",
          event_type: "ottow_vehicle_delivered",
          title: "OTTOW Vehicle Delivered",
          body: `${vehicle?.display_name || "Vehicle"} delivered to ${stall?.stall_code || "depot"}`,
          vehicle_id: mission.vehicle_id,
          channels: ["in_app"],
        });
      }

      // When closed: release driver
      if (targetStatus === "closed") {
        if (mission.driver_staff_id) {
          const driver = await store.getDriverByStaffId(mission.driver_staff_id);
          if (driver) {
            await store.updateDriver(driver.id, {
              status: "available",
              current_mission_id: null,
            });
          }
        }
      }

      // When cancelled: release driver and clear reservation
      if (targetStatus === "cancelled") {
        if (mission.driver_staff_id) {
          const driver = await store.getDriverByStaffId(mission.driver_staff_id);
          if (driver) {
            await store.updateDriver(driver.id, {
              status: "available",
              current_mission_id: null,
            });
          }
        }
        if (mission.destination_stall_id) {
          await store.updateStall(mission.destination_stall_id, {
            status: "available",
            reserved_for_mission_id: null,
          });
        }
        // Revert vehicle state
        await store.updateVehicleState(mission.vehicle_id, "offline", null, "ottow_system");
      }

      return ok({
        mission_id: missionId,
        previous_status: currentStatus,
        new_status: targetStatus,
        destination_stall: mission.destination_stall_id ? {
          id: mission.destination_stall_id,
          stall_type: mission.destination_stall_type,
        } : null,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/location — Driver GPS ping
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/location$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);
      if (body.lat === undefined || body.lng === undefined) {
        return err("VALIDATION_ERROR", "lat and lng required", 400);
      }

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      const now = new Date().toISOString();
      await store.updateMission(missionId, {
        driver_lat: body.lat,
        driver_lng: body.lng,
        driver_heading: body.heading || null,
        driver_speed_mph: body.speed_mph || null,
        driver_location_updated_at: now,
        eta_minutes: body.eta_minutes !== undefined ? body.eta_minutes : mission.eta_minutes,
      });

      // Log location (only every ~10th update to avoid flooding the event log)
      // In production, use a separate telemetry table. For now, log sparingly.
      if (body.log_event) {
        await store.createMissionEvent({
          mission_id: missionId,
          event_type: "location_update",
          location_lat: body.lat,
          location_lng: body.lng,
          actor_id: mission.driver_staff_id,
          actor_type: "driver",
          client_timestamp: body.client_timestamp || null,
          metadata: { heading: body.heading, speed_mph: body.speed_mph, eta_minutes: body.eta_minutes },
        });
      }

      return ok({ mission_id: missionId, location_updated: true }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/note — Add a note or condition report
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/note$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      const eventType = body.is_condition_report ? "vehicle_condition_report" : "note_added";

      await store.createMissionEvent({
        mission_id: missionId,
        event_type: eventType,
        location_lat: body.location?.lat,
        location_lng: body.location?.lng,
        actor_id: body.actor_id || mission.driver_staff_id,
        actor_type: body.actor_type || "driver",
        notes: body.notes || body.text,
        client_timestamp: body.client_timestamp || null,
        metadata: {
          photo_urls: body.photo_urls || [],
          condition_checks: body.condition_checks || {},
        },
      });

      return ok({ mission_id: missionId, event_type: eventType, noted: true }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/eta — Update ETA
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/eta$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => null);
      if (!body) return err("BAD_REQUEST", "Invalid JSON body", 400);
      if (body.eta_minutes === undefined) return err("VALIDATION_ERROR", "eta_minutes required", 400);

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      await store.updateMission(missionId, { eta_minutes: body.eta_minutes });

      await store.createMissionEvent({
        mission_id: missionId,
        event_type: "eta_updated",
        actor_id: body.actor_id || mission.driver_staff_id,
        actor_type: body.actor_type || "driver",
        metadata: { eta_minutes: body.eta_minutes, previous_eta: mission.eta_minutes },
      });

      return ok({ mission_id: missionId, eta_minutes: body.eta_minutes }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/cancel — Cancel a mission
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/cancel$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => ({}));

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      if (NO_CANCEL_STAGES.includes(mission.status)) {
        return err("CANCEL_NOT_ALLOWED",
          `Cannot cancel mission in ${mission.status} stage — vehicle must be delivered`,
          409,
        );
      }

      const now = new Date().toISOString();

      await store.updateMission(missionId, {
        status: "cancelled",
        cancelled_at: now,
        cancellation_reason: body.reason || "Cancelled by dispatcher",
      });

      await store.createMissionEvent({
        mission_id: missionId,
        event_type: "cancellation",
        from_status: mission.status,
        to_status: "cancelled",
        actor_id: body.cancelled_by_user_id || null,
        actor_type: body.actor_type || "dispatcher",
        notes: body.reason || "Cancelled by dispatcher",
      });

      // Release driver
      if (mission.driver_staff_id) {
        const driver = await store.getDriverByStaffId(mission.driver_staff_id);
        if (driver) {
          await store.updateDriver(driver.id, { status: "available", current_mission_id: null });
        }
      }

      // Release stall reservation
      if (mission.destination_stall_id) {
        await store.updateStall(mission.destination_stall_id, { status: "available", reserved_for_mission_id: null });
      }

      return ok({ mission_id: missionId, status: "cancelled" }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/driver/active-mission — Get driver's active mission
    // -----------------------------------------------------------------------
    // Used by the driver mobile app to fetch their current assignment.
    if (method === "GET" && path === "/api/v1/ottow/driver/active-mission") {
      const driverStaffId = url.searchParams.get("driver_staff_id");
      if (!driverStaffId) return err("BAD_REQUEST", "driver_staff_id required", 400);

      const mission = await store.getActiveMissionForDriver(driverStaffId);
      if (!mission) {
        return ok({ active_mission: null, message: "No active mission" }, startTime);
      }

      const vehicle = await store.getVehicle(mission.vehicle_id);
      const events = await store.getMissionEvents(mission.id);
      const destStall = mission.destination_stall_id ? await store.getStall(mission.destination_stall_id) : null;

      // Safety warnings for thermal events
      const safetyWarnings: string[] = [];
      if (mission.incident_category === "battery_thermal") {
        safetyWarnings.push("THERMAL EVENT — Maintain 50ft until confirmed safe");
        safetyWarnings.push("Do NOT attempt to charge or connect to the vehicle");
        safetyWarnings.push("If smoke or flames visible, call 911 immediately");
      } else if (mission.incident_category === "collision") {
        safetyWarnings.push("Check for fluid leaks before approaching");
        safetyWarnings.push("Document damage with photos before moving");
      }

      // Build on-site checklist based on incident category
      const CHECKLISTS: Record<string, string[]> = {
        battery_thermal: [
          "Confirm no active fire or smoke",
          "Check ambient temperature around vehicle",
          "Photo vehicle from 4 angles (min 20ft distance)",
          "Check for fluid leaks under vehicle",
          "Confirm vehicle is NOT plugged into any charger",
        ],
        collision: [
          "Photo all visible damage",
          "Check for fluid leaks",
          "Assess tire/wheel condition for tow",
          "Verify vehicle is in park/neutral",
          "Check if airbags deployed",
        ],
        mechanical: [
          "Attempt remote unlock if locked out",
          "Check wheel movement / steering lock",
          "Photo any visible damage or warning indicators",
          "Verify vehicle can be shifted to neutral",
        ],
        sensor_failure: [
          "Photo any visible sensor damage",
          "Note which sensors appear affected",
          "Verify vehicle responds to remote commands",
        ],
        flat_tire: [
          "Photo affected tire(s)",
          "Check if rim damage present",
          "Measure approximate remaining air pressure if gauge available",
          "Verify other tires are safe for transport",
        ],
        software_lockup: [
          "Note any error messages on vehicle display",
          "Attempt hard reboot (hold power 30s)",
          "If reboot fails, prepare for flatbed tow",
        ],
      };

      return ok({
        active_mission: {
          id: mission.id,
          status: mission.status,
          priority: mission.priority,
          incident_category: mission.incident_category,
          pickup: {
            lat: mission.pickup_location_lat,
            lng: mission.pickup_location_lng,
            address: mission.pickup_address,
            notes: mission.pickup_notes,
          },
          vehicle: vehicle ? {
            id: vehicle.id,
            display_name: vehicle.display_name || vehicle.vin,
            vin: vehicle.vin,
            make: vehicle.make,
            model: vehicle.model,
            year: vehicle.year,
            platform: vehicle.platform,
            current_soc: vehicle.current_soc,
            color: vehicle.exterior_color,
            license_plate: vehicle.license_plate,
          } : null,
          destination_stall: destStall ? {
            id: destStall.id,
            stall_code: destStall.stall_code,
            stall_type: destStall.stall_type,
            zone: destStall.zone,
            relative_x: destStall.relative_x,
            relative_y: destStall.relative_y,
          } : null,
          eta_minutes: mission.eta_minutes,
          safety_warnings: safetyWarnings,
          on_site_checklist: CHECKLISTS[mission.incident_category] || CHECKLISTS.mechanical,
          timestamps: {
            created: mission.created_at,
            dispatched: mission.dispatched_at,
            en_route: mission.en_route_at,
            on_site: mission.on_site_at,
            vehicle_secured: mission.vehicle_secured_at,
            returning: mission.returning_at,
            arrived_depot: mission.arrived_depot_at,
            stall_assigned: mission.stall_assigned_at,
          },
          events_count: events.length,
          recent_events: events.slice(-5),
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/ottow/drivers — List available OTTOW drivers
    // -----------------------------------------------------------------------
    if (method === "GET" && path === "/api/v1/ottow/drivers") {
      const depotId = url.searchParams.get("depot_id");
      if (!depotId) return err("BAD_REQUEST", "depot_id required", 400);

      const statusFilter = url.searchParams.get("status");

      let drivers;
      if (statusFilter === "available") {
        drivers = await store.getAvailableDrivers(depotId);
      } else {
        const { data } = await supabase.from("ottow_drivers")
          .select("*, staff_users(first_name, last_name, display_name)")
          .eq("depot_id", depotId);
        drivers = data || [];
      }

      return ok({
        depot_id: depotId,
        drivers: drivers.map((d: any) => ({
          id: d.id,
          staff_user_id: d.staff_user_id,
          name: d.staff_users?.display_name || `${d.staff_users?.first_name} ${d.staff_users?.last_name}`,
          status: d.status,
          current_mission_id: d.current_mission_id,
          vehicle_class_certs: d.vehicle_class_certs,
          last_location: d.last_location_lat ? {
            lat: d.last_location_lat,
            lng: d.last_location_lng,
            at: d.last_location_at,
          } : null,
          shift_start: d.shift_start,
          shift_end: d.shift_end,
        })),
        count: drivers.length,
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/request-stall — Request stall assignment
    // -----------------------------------------------------------------------
    // Called when OTTOW is returning, or manually to re-request.
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/request-stall$/.test(path)) {
      const missionId = path.split("/")[5];
      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      // Release any existing reservation first
      if (mission.destination_stall_id) {
        await store.updateStall(mission.destination_stall_id, {
          status: "available",
          reserved_for_mission_id: null,
        });
      }

      await store.createMissionEvent({
        mission_id: missionId,
        event_type: "stall_requested",
        actor_type: "otto_q_engine",
        notes: `Stall requested for ${mission.incident_category} incident`,
      });

      const stall = await assignStallForOTTOW(mission.depot_id, missionId, mission.incident_category);

      if (stall) {
        const now = new Date().toISOString();
        await store.updateMission(missionId, {
          destination_stall_id: stall.id,
          destination_stall_type: stall.stall_type,
          stall_assigned_at: now,
        });

        await store.createMissionEvent({
          mission_id: missionId,
          event_type: "stall_assigned",
          actor_type: "otto_q_engine",
          notes: `Assigned stall ${stall.stall_code} (${stall.stall_type})`,
          metadata: { stall_id: stall.id, stall_code: stall.stall_code, stall_type: stall.stall_type },
        });

        return ok({
          mission_id: missionId,
          stall_assigned: true,
          stall: {
            id: stall.id,
            stall_code: stall.stall_code,
            stall_type: stall.stall_type,
            zone: stall.zone,
            relative_x: stall.relative_x,
            relative_y: stall.relative_y,
          },
        }, startTime);
      }

      return ok({
        mission_id: missionId,
        stall_assigned: false,
        message: mission.incident_category === "battery_thermal"
          ? "CRITICAL: No safety stall available. Vehicle must wait in arrival zone."
          : "No stall currently available. Will retry automatically.",
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/ottow/missions/:id/confirm-delivery — Vehicle placed in stall
    // -----------------------------------------------------------------------
    if (method === "POST" && /^\/api\/v1\/ottow\/missions\/[^/]+\/confirm-delivery$/.test(path)) {
      const missionId = path.split("/")[5];
      const body = await req.json().catch(() => ({}));

      const mission = await store.getMission(missionId);
      if (!mission) return err("NOT_FOUND", `Mission ${missionId} not found`, 404);

      if (!mission.destination_stall_id) {
        return err("PRECONDITION_FAILED", "No stall assigned to this mission", 412);
      }

      const now = new Date().toISOString();

      // 1. Mark mission as vehicle_delivered
      await store.updateMission(missionId, {
        status: "vehicle_delivered",
        vehicle_delivered_at: now,
      });

      // 2. Update stall: occupied with vehicle
      await store.updateStall(mission.destination_stall_id, {
        status: "occupied",
        current_vehicle_id: mission.vehicle_id,
        reserved_for_mission_id: null,
      });

      // 3. Update vehicle state
      const newVehicleState = VEHICLE_STATE_ON_DELIVERY[mission.incident_category] || "staging";
      await store.updateVehicleState(
        mission.vehicle_id,
        newVehicleState,
        mission.destination_stall_id,
        "ottow_system",
        mission.driver_staff_id,
        { mission_id: missionId, delivery_notes: body.notes },
      );

      // 4. Log event
      await store.createMissionEvent({
        mission_id: missionId,
        event_type: "status_change",
        from_status: mission.status,
        to_status: "vehicle_delivered",
        actor_id: mission.driver_staff_id,
        actor_type: "driver",
        notes: body.notes || "Vehicle delivered to assigned stall",
        location_lat: body.location?.lat,
        location_lng: body.location?.lng,
        metadata: {
          stall_id: mission.destination_stall_id,
          vehicle_state: newVehicleState,
          condition_notes: body.condition_notes,
        },
      });

      // 5. Update linked exception
      if (mission.exception_id) {
        await supabase.from("exceptions").update({
          status: "investigating",
          stall_id: mission.destination_stall_id,
        }).eq("id", mission.exception_id);
      }

      // 6. Notify ops
      const vehicle = await store.getVehicle(mission.vehicle_id);
      const stall = await store.getStall(mission.destination_stall_id);
      await store.queueNotification({
        depot_id: mission.depot_id,
        recipient_type: "staff",
        event_type: "ottow_vehicle_delivered",
        title: "OTTOW Vehicle Delivered",
        body: `${vehicle?.display_name || "Vehicle"} delivered to ${stall?.stall_code || "stall"}. State: ${newVehicleState}`,
        vehicle_id: mission.vehicle_id,
        exception_id: mission.exception_id,
        channels: ["in_app", "push"],
      });

      return ok({
        mission_id: missionId,
        status: "vehicle_delivered",
        vehicle_state: newVehicleState,
        stall: {
          id: stall?.id,
          stall_code: stall?.stall_code,
          stall_type: stall?.stall_type,
        },
      }, startTime);
    }

    // -----------------------------------------------------------------------
    // 404
    // -----------------------------------------------------------------------
    return err("NOT_FOUND", `Route not found: ${method} ${path}`, 404);

  } catch (error) {
    console.error(`[OTTO-Q] Error in ${method} ${path}:`, error);
    return err("INTERNAL_ERROR", error instanceof Error ? error.message : "Unknown error", 500);
  }
});
