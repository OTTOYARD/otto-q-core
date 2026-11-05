-- 02_types.sql: 27 statements, exported from production's catalog
-- @@ enum public.av_platform
CREATE TYPE public.av_platform AS ENUM ('waymo', 'motional', 'tesla', 'cruise', 'zoox', 'aurora', 'nuro', 'uber_av', 'generic', 'not_applicable');
-- @@ enum public.bess_status
CREATE TYPE public.bess_status AS ENUM ('online', 'offline', 'charging', 'discharging', 'standby', 'fault');
-- @@ enum public.circuit_breaker_state
CREATE TYPE public.circuit_breaker_state AS ENUM ('closed', 'open', 'half_open');
-- @@ enum public.emergency_reason
CREATE TYPE public.emergency_reason AS ENUM ('low_soc', 'vehicle_incident', 'oem_recall', 'sensor_fault', 'passenger_complaint', 'fleet_operator_request', 'regulatory', 'weather_event', 'software_update_required', 'other');
-- @@ enum public.exception_severity
CREATE TYPE public.exception_severity AS ENUM ('low', 'medium', 'high', 'critical');
-- @@ enum public.exception_status
CREATE TYPE public.exception_status AS ENUM ('open', 'acknowledged', 'in_progress', 'resolved', 'escalated');
-- @@ enum public.exception_type
CREATE TYPE public.exception_type AS ENUM ('vehicle_damage', 'vehicle_malfunction', 'sensor_anomaly', 'tire_issue', 'excessive_contamination', 'charger_fault', 'wash_system_fault', 'service_bay_fault', 'vehicle_unresponsive', 'schedule_conflict', 'unauthorized_movement', 'safety_concern', 'other');
-- @@ enum public.maintenance_category
CREATE TYPE public.maintenance_category AS ENUM ('health_check', 'fluid_check', 'brake_inspection', 'tire_rotation', 'tire_replacement', 'battery_health', 'sensor_calibration', 'software_update', 'exterior_inspection', 'interior_deep_clean', 'hvac_service', 'full_service', 'other');
-- @@ enum public.maintenance_frequency
CREATE TYPE public.maintenance_frequency AS ENUM ('daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'semi_annual', 'annual', 'as_needed');
-- @@ enum public.modification_type
CREATE TYPE public.modification_type AS ENUM ('arrival_change', 'departure_change', 'service_add', 'service_remove', 'priority_change', 'cancellation', 'full_reschedule', 'stall_reassignment');
-- @@ enum public.notification_channel
CREATE TYPE public.notification_channel AS ENUM ('in_app', 'webhook', 'email', 'sms');
-- @@ enum public.notification_status
CREATE TYPE public.notification_status AS ENUM ('queued', 'sent', 'delivered', 'failed', 'read');
-- @@ enum public.ocpp_charging_state
CREATE TYPE public.ocpp_charging_state AS ENUM ('Charging', 'EVConnected', 'SuspendedEV', 'SuspendedEVSE', 'Idle');
-- @@ enum public.ocpp_connector_status
CREATE TYPE public.ocpp_connector_status AS ENUM ('Available', 'Occupied', 'Reserved', 'Unavailable', 'Faulted');
-- @@ enum public.ocpp_session_status
CREATE TYPE public.ocpp_session_status AS ENUM ('active', 'completed', 'faulted', 'cancelled');
-- @@ enum public.ocpp_transaction_event_type
CREATE TYPE public.ocpp_transaction_event_type AS ENUM ('Started', 'Updated', 'Ended');
-- @@ enum public.priority_tier
CREATE TYPE public.priority_tier AS ENUM ('standard', 'priority', 'vip');
-- @@ enum public.recall_action
CREATE TYPE public.recall_action AS ENUM ('no_change', 'return_early', 'return_now', 'divert_nearest_depot', 'request_tow');
-- @@ enum public.recall_urgency
CREATE TYPE public.recall_urgency AS ENUM ('none', 'advisory', 'recommended', 'critical');
-- @@ enum public.schedule_status
CREATE TYPE public.schedule_status AS ENUM ('draft', 'confirmed', 'in_progress', 'completed', 'cancelled', 'modified');
-- @@ enum public.staff_role
CREATE TYPE public.staff_role AS ENUM ('charging_tech', 'cleaning_tech', 'maintenance_tech', 'yard_supervisor', 'ops_manager', 'retail_concierge');
-- @@ enum public.stall_type
CREATE TYPE public.stall_type AS ENUM ('dcfc', 'l2', 'wash_bay', 'detail_bay', 'service_bay', 'staging', 'parking', 'safety');
-- @@ enum public.tariff_label
CREATE TYPE public.tariff_label AS ENUM ('super_off_peak', 'off_peak', 'mid_peak', 'on_peak');
-- @@ enum public.task_status
CREATE TYPE public.task_status AS ENUM ('pending', 'vehicle_en_route', 'in_progress', 'completed', 'skipped', 'exception', 'cancelled');
-- @@ enum public.trigger_source
CREATE TYPE public.trigger_source AS ENUM ('otto_q_engine', 'charging_tech', 'cleaning_tech', 'maintenance_tech', 'yard_supervisor', 'ops_manager', 'fleet_operator', 'retail_member', 'vehicle_telemetry', 'charger_ocpp', 'system_timer', 'ottow_dispatch', 'manual_override');
-- @@ enum public.vehicle_category
CREATE TYPE public.vehicle_category AS ENUM ('autonomous', 'retail', 'delivery_bot', 'humanoid', 'shuttle');
-- @@ enum public.vehicle_state
CREATE TYPE public.vehicle_state AS ENUM ('offline', 'deployed', 'en_route_to_depot', 'arrived_at_gate', 'staged_awaiting_service', 'charging_dcfc', 'charging_l2', 'charge_complete_holding', 'in_wash_bay', 'in_detail_bay', 'in_service_bay', 'service_complete_holding', 'staged_for_departure', 'en_route_to_deployment', 'emergency_staged', 'tow_requested', 'out_of_service');
