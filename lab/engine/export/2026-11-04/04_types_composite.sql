-- 04_types_composite.sql: 3 statements, exported from production's catalog
-- @@ composite public.ottoq_charge_clock_evidence
CREATE TYPE public.ottoq_charge_clock_evidence AS (sid uuid, run uuid, kind text, band text, who jsonb, cls text, mdl text, veh text, lr double precision, w double precision, st timestamp with time zone, en timestamp with time zone, bat numeric, s0 numeric, s1 numeric, ckw numeric, vkw numeric, air double precision);
-- @@ composite public.ottoq_decide_tick_result
CREATE TYPE public.ottoq_decide_tick_result AS (tick_seq bigint, sim_clock timestamp with time zone, requests_built integer, enacted integer, overridden integer, deferred integer, errored integer, shield_disarmed integer, total_latency_ms integer);
-- @@ composite public.ottoq_rule_result
CREATE TYPE public.ottoq_rule_result AS (passed boolean, reason text, severity_override text, payload jsonb, suggested_action text);
