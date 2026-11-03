-- lab/engine/sql/20_repo_gaps.sql
-- Objects the engine's own tables and functions need that exist in production
-- and in NO file of this repository. They are not Supabase objects: they were
-- created before db/baseline/ was exported (2026-08-03) and the export did not
-- include them. Without this file 30+ baseline tables and the functions typed on
-- them cannot be created at all, so it is applied before the baseline -- and it
-- is a finding in its own right (see reports/fidelity_*.md).
--
-- Provenance: production catalog (pg_enum, pg_attribute of the composite types,
-- pg_namespace), read-only through the Supabase MCP tool on 2026-11-03,
-- 15:58-16:05 UTC (9:58-10:05 AM CT). These are END-STATE definitions: no repo
-- file alters any of them (grep for ALTER TYPE finds only 0632, on a type 0622
-- creates), so the end state is also the state the baseline expects.
-- Not taken from production: anything a repo file creates. In particular
-- public.ottoq_charge_clock_evidence is left to 0622 (CREATE TYPE) and 0632.

-- The two engine schemas (created 2026-07-29 by pre-baseline migration 437,
-- per the comment in db/baseline/rls_policies.sql). ACL as production reads.
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS twin;
GRANT USAGE ON SCHEMA ottoq, twin TO service_role;

-- 26 enum types in public.
CREATE TYPE public.av_platform AS ENUM ('waymo','motional','tesla','cruise','zoox','aurora','nuro','uber_av','generic','not_applicable');
CREATE TYPE public.bess_status AS ENUM ('online','offline','charging','discharging','standby','fault');
CREATE TYPE public.circuit_breaker_state AS ENUM ('closed','open','half_open');
CREATE TYPE public.emergency_reason AS ENUM ('low_soc','vehicle_incident','oem_recall','sensor_fault','passenger_complaint','fleet_operator_request','regulatory','weather_event','software_update_required','other');
CREATE TYPE public.exception_severity AS ENUM ('low','medium','high','critical');
CREATE TYPE public.exception_status AS ENUM ('open','acknowledged','in_progress','resolved','escalated');
CREATE TYPE public.exception_type AS ENUM ('vehicle_damage','vehicle_malfunction','sensor_anomaly','tire_issue','excessive_contamination','charger_fault','wash_system_fault','service_bay_fault','vehicle_unresponsive','schedule_conflict','unauthorized_movement','safety_concern','other');
CREATE TYPE public.maintenance_category AS ENUM ('health_check','fluid_check','brake_inspection','tire_rotation','tire_replacement','battery_health','sensor_calibration','software_update','exterior_inspection','interior_deep_clean','hvac_service','full_service','other');
CREATE TYPE public.maintenance_frequency AS ENUM ('daily','weekly','biweekly','monthly','quarterly','semi_annual','annual','as_needed');
CREATE TYPE public.modification_type AS ENUM ('arrival_change','departure_change','service_add','service_remove','priority_change','cancellation','full_reschedule','stall_reassignment');
CREATE TYPE public.notification_channel AS ENUM ('in_app','webhook','email','sms');
CREATE TYPE public.notification_status AS ENUM ('queued','sent','delivered','failed','read');
CREATE TYPE public.ocpp_charging_state AS ENUM ('Charging','EVConnected','SuspendedEV','SuspendedEVSE','Idle');
CREATE TYPE public.ocpp_connector_status AS ENUM ('Available','Occupied','Reserved','Unavailable','Faulted');
CREATE TYPE public.ocpp_session_status AS ENUM ('active','completed','faulted','cancelled');
CREATE TYPE public.ocpp_transaction_event_type AS ENUM ('Started','Updated','Ended');
CREATE TYPE public.priority_tier AS ENUM ('standard','priority','vip');
CREATE TYPE public.recall_action AS ENUM ('no_change','return_early','return_now','divert_nearest_depot','request_tow');
CREATE TYPE public.recall_urgency AS ENUM ('none','advisory','recommended','critical');
CREATE TYPE public.schedule_status AS ENUM ('draft','confirmed','in_progress','completed','cancelled','modified');
CREATE TYPE public.staff_role AS ENUM ('charging_tech','cleaning_tech','maintenance_tech','yard_supervisor','ops_manager','retail_concierge');
CREATE TYPE public.stall_type AS ENUM ('dcfc','l2','wash_bay','detail_bay','service_bay','staging','parking','safety');
CREATE TYPE public.tariff_label AS ENUM ('super_off_peak','off_peak','mid_peak','on_peak');
CREATE TYPE public.task_status AS ENUM ('pending','vehicle_en_route','in_progress','completed','skipped','exception','cancelled');
CREATE TYPE public.trigger_source AS ENUM ('otto_q_engine','charging_tech','cleaning_tech','maintenance_tech','yard_supervisor','ops_manager','fleet_operator','retail_member','vehicle_telemetry','charger_ocpp','system_timer','ottow_dispatch','manual_override');
CREATE TYPE public.vehicle_category AS ENUM ('autonomous','retail','delivery_bot','humanoid','shuttle');
CREATE TYPE public.vehicle_state AS ENUM ('offline','deployed','en_route_to_depot','arrived_at_gate','staged_awaiting_service','charging_dcfc','charging_l2','charge_complete_holding','in_wash_bay','in_detail_bay','in_service_bay','service_complete_holding','staged_for_departure','en_route_to_deployment','emergency_staged','tow_requested','out_of_service');

-- 2 composite types in public that baseline functions return.
CREATE TYPE public.ottoq_decide_tick_result AS (tick_seq bigint, sim_clock timestamp with time zone, requests_built integer, enacted integer, overridden integer, deferred integer, errored integer, shield_disarmed integer, total_latency_ms integer);
CREATE TYPE public.ottoq_rule_result AS (passed boolean, reason text, severity_override text, payload jsonb, suggested_action text);
