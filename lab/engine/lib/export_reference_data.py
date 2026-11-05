#!/usr/bin/env python3
"""Export the twin depot's reference data from production, read-only, for the lab.

CLAUDE.md rule 8: the twin depot (11111111-...) is the only site. The lab holds that depot's
configuration and nothing else: no run data (registry classes engine / run_ledger), no evidence
ledgers, no history, no other depot, and nothing that identifies a person or holds a credential.
Which tables are copied, and why, is the explicit list below (TABLES); a table not on it is not
copied, and the exporter refuses to start if a listed table has disappeared from production or
has been registered as run-scoped or evidence since this list was written.

Rows travel as their composite text form (`(t.*)::text`), read with extra_float_digits = 3,
DateStyle ISO, IntervalStyle postgres and bytea_output hex, so every value -- floats, numerics,
timestamps, ranges, geometry, jsonb -- parses back to the same value in the lab. The world
fingerprint of the twin depot (ottoq.ottoq_world_fingerprint_sections, the engine's own hash of
vehicles, stalls, chargers, need profiles and BESS) is computed on production immediately before
and after the rows are read; the lab recomputes it after loading.

    python -I lab/engine/lib/export_reference_data.py --out DIR
writes DIR/<schema>.<table>.json ({read_at, filter, count, rows}) and DIR/manifest.json.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prod_read  # noqa: E402
from export_prod import SECRET_PATTERNS  # noqa: E402

TWIN = "11111111-1111-1111-1111-111111111111"
TWIN_LIT = f"'{TWIN}'::uuid"
TWIN_VEHICLES = f"(select v.id from public.vehicles v where v.home_depot_id = {TWIN_LIT})"
TWIN_STALLS = f"(select s.id from public.stalls s where s.depot_id = {TWIN_LIT})"

# filter kinds
DEPOT = f"depot_id is null or depot_id = {TWIN_LIT}"          # depot-keyed; NULL = applies everywhere
VEHICLE = f"vehicle_id in {TWIN_VEHICLES}"
STALL = f"stall_id in {TWIN_STALLS}"
ALL = "true"

# (schema, table, filter, why). Grouped as the engine uses them.
TABLES: list[tuple[str, str, str, str]] = [
    # -- the depot itself
    ("public", "depots", f"id = {TWIN_LIT}", "the twin depot's row"),
    ("public", "stalls", DEPOT, "its 158 stalls"),
    ("public", "ottoq_ocpp_chargers", DEPOT, "its chargers"),
    ("public", "ottoq_site_structures", DEPOT, "site geometry the twin and renderer read"),
    ("public", "ottoq_service_point_capabilities", STALL, "(asset_class, operation) pairs per stall"),
    ("public", "ottoq_bess_units", DEPOT, "the battery (state lives on the row)"),
    ("public", "ottoq_canopy_state", DEPOT, "solar canopies"),
    ("public", "ottoq_tariff_windows", DEPOT, "tariff windows"),
    ("public", "ottoq_depot_tariffs", DEPOT, "tariffs"),
    ("public", "tariff_schedules", DEPOT, "tariff schedules"),
    ("public", "ottoq_depot_staffing", DEPOT, "technician pools"),
    ("public", "ottoq_depot_shifts", DEPOT, "shifts"),
    ("public", "waves", DEPOT, "dispatch waves"),
    ("public", "ottoq_grid_events", DEPOT, "grid events (EN.004/EN.005 read them)"),
    ("public", "ottoq_site_buildouts", DEPOT, "charger build-outs"),
    ("public", "ottoq_site_buildout_active", DEPOT, "which build-out is on"),
    ("public", "ottoq_site_base_history", DEPOT, "the stall-type history ottoq_stall_type_at reads"),
    ("public", "ottoq_fleet_buildouts", DEPOT, "fleet build-outs"),
    ("public", "ottoq_fleet_buildout_active", DEPOT, "which fleet build-out is on"),
    ("public", "engine_config", DEPOT, "engine configuration"),
    ("public", "action_guardrails", DEPOT, "guardrails"),
    ("public", "accuracy_slos", DEPOT, "accuracy SLOs"),
    ("public", "model_parameters", DEPOT, "model parameters"),
    ("public", "model_versions", DEPOT, "active model versions"),
    ("public", "service_definitions", DEPOT, "service catalogue (fallback)"),
    ("public", "schedule_tasks", DEPOT, "legacy schedule tasks at the depot"),
    ("public", "vehicle_schedules", DEPOT, "vehicle schedules at the depot"),
    ("public", "external_factor_sources", DEPOT, "external factor sources"),
    ("public", "ottoq_rule_overrides", DEPOT, "per-depot rule overrides"),
    ("public", "ottoq_model_routes", DEPOT, "which model serves which call"),
    ("public", "ottoq_scenarios", DEPOT, "the scenarios a run starts from"),
    ("twin", "ottoq_twin_operators", DEPOT, "the twin's operators"),
    # -- its fleet (the owners' cars; no person, no credential)
    ("public", "vehicles", f"home_depot_id = {TWIN_LIT}", "the 120 cars homed at the twin depot"),
    ("public", "vehicle_need_profile", VEHICLE, "their need profiles"),
    # -- learned estimates (fits, not the evidence they were fitted from)
    ("public", "ottoq_charge_clock_fits", DEPOT, "the learned charge clock the kernel's seating reads"),
    ("public", "ottoq_charge_fault_fits", DEPOT, "learned charger fault rates"),
    ("public", "ottoq_charge_window_calibration", DEPOT, "charge window calibration"),
    ("public", "ottoq_learned_estimates", DEPOT, "learned estimates"),
    ("public", "ottoq_evidence_regimes", DEPOT, "evidence regimes the fits honour (0625)"),
    # -- owners and contracts
    ("public", "fleet_operators", ALL, "the owners (companies)"),
    ("public", "ottoq_fleet_operator_slas", ALL, "their contracts"),
    ("public", "ottoq_oem_webhook_patterns", ALL, "OEM webhook emulation patterns"),
    ("public", "ottoq_service_tariffs", ALL, "service tariffs"),
    # -- the engine's catalogs and settings
    ("public", "ottoq_rules", ALL, "the L1 shield's rules"),
    ("public", "ottoq_rule_parameters", ALL, "rule parameters"),
    ("public", "ottoq_policy_param_catalog", ALL, "the dial catalog"),
    ("public", "ottoq_policy_params", f"scope_type = 'global' or (scope_type = 'depot' and scope_id = {TWIN_LIT})",
     "dial settings: global and the twin depot's; never a past run's"),
    ("public", "ottoq_event_types_catalog", ALL, "event vocabulary"),
    ("public", "ottoq_state_transitions", ALL, "the transition catalog SM.001 reads"),
    ("public", "ottoq_variability_catalog", ALL, "variability catalog"),
    ("public", "ottoq_calibration_datasets", ALL, "calibration datasets (ACN, TLC, DMV, NOAA)"),
    ("public", "ottoq_calibration_distributions", ALL, "fitted quantile grids"),
    ("public", "ottoq_calibration_correlations", ALL, "calibration correlations"),
    ("public", "ottoq_calibration_profiles", ALL, "calibration profiles"),
    ("public", "ottoq_dtc_catalog", ALL, "fault code catalog"),
    ("public", "service_cadence_policy", ALL, "the live service catalogue"),
    ("public", "ottoq_operation_catalog", ALL, "operation catalog"),
    ("public", "ottoq_vehicle_classes", ALL, "vehicle classes"),
    ("public", "ottoq_feed_plans", ALL, "feed plans"),
    ("public", "ottoq_sim_scenarios", ALL, "sim scenario definitions"),
    ("public", "ottoq_proposer_precedence", ALL, "proposer precedence"),
    ("public", "ottoq_certified_proposers", ALL, "certified proposers"),
    ("public", "ottoq_recall_implementations", ALL, "recall implementations"),
    ("public", "ottoq_command_actor_registry", ALL, "command actors"),
    ("public", "ottoq_enactment_branches", ALL, "enactment branches"),
    ("public", "ottoq_emergency_protocols", ALL, "emergency protocols"),
    ("public", "ottoq_energy_rates", ALL, "energy rates"),
    ("public", "ottoq_margin_prices", ALL, "margin prices"),
    ("public", "ottoq_reward_weights", ALL, "reward weights"),
    ("public", "ottoq_kpi_touch_actor_types", ALL, "KPI touch actor types"),
    ("public", "ottoq_kpi_touch_lanes", ALL, "KPI touch lanes"),
    ("public", "ottoq_v2_signal_ttl", ALL, "signal TTLs"),
    ("public", "ottoq_features", ALL, "feature definitions"),
    ("public", "ottoq_anomaly_detectors", ALL, "anomaly detectors"),
    ("public", "ottoq_prediction_types_catalog", ALL, "prediction types"),
    ("public", "ottoq_prediction_rule_links", ALL, "prediction-rule links"),
    ("public", "ottoq_specialization_strategies", ALL, "specialization strategies"),
    ("public", "ottoq_retraining_triggers", ALL, "retraining triggers"),
    ("public", "ottoq_intelligence_sources", ALL, "intelligence sources"),
    ("public", "downstream_action_contracts", ALL, "downstream action contracts"),
    ("public", "ottoq_agent_prompts", ALL, "the agent's prompts"),
    ("public", "ottow_dispatch_rules", DEPOT, "work-side dispatch rules"),
    # -- the engine's bookkeeping about itself
    ("public", "ottoq_run_scope_registry", ALL, "the run-scope registry the purge reads"),
    ("public", "ottoq_retention_policy", ALL, "retention policy"),
    ("public", "ottoq_retention_state", ALL, "retention state"),
    ("public", "ottoq_retention_engine_allowlist", ALL, "retention allowlist"),
    ("public", "ottoq_write_slimming_policy", ALL, "write slimming policy"),
    ("public", "ottoq_cert_columns", ALL, "the canon matrix's columns"),
    ("public", "ottoq_cert_lineage", ALL, "migration lineage the recert floor reads"),
    ("public", "ottoq_signing_keys", ALL, "signing key REGISTRY (secret_ref only; the secrets stay in production's vault)"),
]

# Never copied, with the reason, so the list above is reviewable against what was left out.
EXCLUDED = {
    "personal data or credentials": ["ottoq_oauth_auth_requests", "ottoq_oauth_clients", "ottoq_oauth_device_codes",
                                     "ottoq_oauth_grants", "ottoq_oauth_tokens", "ottoq_owner_accounts", "staff_users",
                                     "retail_members", "ottoq_agent_demo_passcode", "ottow_api_keys", "ottoq_service_tokens",
                                     "ottoq_agent_principals", "api_integrations", "ottoq_v2_signing_keys", "ottow_drivers",
                                     "notifications", "ottoq_audit_bundles", "ottoq_service_endpoints"],
    "history, logs and outputs (the past, not an input)": [
        "vehicle_state_log", "bess_snapshots", "depot_state_snapshots", "ai_decision_log", "autonomous_action_log",
        "data_quality_errors", "decision_fusion_log", "demand_management_log", "early_recall_log",
        "emergency_queue_insertions", "external_factors_log", "fleet_features_daily", "integration_health",
        "maintenance_log", "ocpp_meter_values", "ottoq_agent_call_ledger", "ottoq_anomaly_observations",
        "ottoq_arbiter_assessments", "ottoq_audit_reports", "ottoq_calibration_metrics", "ottoq_counterfactuals",
        "ottoq_data_drift_metrics", "ottoq_depot_benchmarks_daily", "ottoq_depot_cost_daily", "ottoq_emergency_invocations",
        "ottoq_feature_values", "ottoq_incident_reports", "ottoq_inference_log", "ottoq_intelligence_snapshot",
        "ottoq_predictions", "ottoq_prediction_accuracy_heatmap", "ottoq_recommendations", "ottoq_sla_conformance_daily",
        "ottoq_sla_violations", "ottoq_visit_cost_attribution", "prediction_accuracy_daily", "prediction_explanations",
        "prediction_outcomes", "progression_decisions", "schedule_modifications", "model_tuning_runs", "tuning_iterations",
        "ottoq_training_runs", "ab_tests", "accuracy_alerts", "depot_visit_reports", "dispatch_commands",
        "ottow_mission_events", "ottow_missions", "ottow_notifications", "vehicle_telemetry", "ottoq_research_findings",
        "ottoq_schema_snapshots", "ottoq_benchmark_frames", "charger_cooldowns", "charger_health_scores",
        "demand_shaping_plans", "maintenance_schedules"],
    "the research wing's and certification's own state (the lab starts its own)": [
        "ottoq_throughput_sweep_cells", "ottoq_throughput_sweeps", "ottoq_dial_experiments", "ottoq_cert_queue",
        "ottoq_proposal_replay", "ottoq_run_once_claim"],
    "registry class engine / run_ledger / evidence": ["(every table so registered; checked at export time)"],
    "scratch, proof and backup tables": ["(names matching the scratch patterns; schema only, no rows)"],
}

SETTINGS = ("select pg_catalog.set_config('search_path', '', true), pg_catalog.set_config('extra_float_digits', '3', true), "
            "pg_catalog.set_config('DateStyle', 'ISO, MDY', true), pg_catalog.set_config('IntervalStyle', 'postgres', true), "
            "pg_catalog.set_config('bytea_output', 'hex', true), pg_catalog.set_config('TimeZone', 'UTC', true); ")


def fingerprint_sql(lab_fn: str) -> str:
    """The body of ottoq.ottoq_world_fingerprint_sections, as the lab holds it, with the depot inlined.

    Run on production through the read-only endpoint (the read-only role cannot EXECUTE the
    function); the lab calls the function itself. The body is the production body (the lab's copy
    is byte-identical, lib/fidelity_full.py), so both sides hash with one algorithm."""
    body = lab_fn.split("AS $function$", 1)[1].rsplit("$function$", 1)[0]
    return body.replace("p_depot", TWIN_LIT)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--export", required=True, help="the schema export (its 06_functions.sql holds the fingerprint body)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    # The fingerprint body, from the schema export (production's own text).
    fn_text = open(os.path.join(a.export, "06_functions.sql"), encoding="utf-8").read()
    start = fn_text.index("CREATE OR REPLACE FUNCTION ottoq.ottoq_world_fingerprint_sections(p_depot uuid)")
    fp_sql = fingerprint_sql(fn_text[start:fn_text.index("\n-- @@ ", start)])
    # the session's own settings, so floats print as production's engine prints them
    fp_query = "select pg_catalog.set_config('search_path', 'ottoq, public, extensions', true); " + fp_sql

    names = [f"'{s}.{t}'" for s, t, _, _ in TABLES]
    check = prod_read.query(
        "select x.n, c.oid is not null as present, (select pg_catalog.string_agg(distinct r.class, ',') "
        "from public.ottoq_run_scope_registry r where r.table_schema || '.' || r.table_name = x.n) as reg "
        f"from pg_catalog.unnest(array[{', '.join(names)}]) x(n) left join pg_catalog.pg_class c "
        "on c.oid = pg_catalog.to_regclass(x.n)")
    bad = [r for r in check if not r["present"] or (r["reg"] and set(r["reg"].split(",")) - {"stamp"})]
    if bad:
        raise SystemExit(f"refusing: listed tables missing or registered as run data/evidence: {bad}")

    fp_before = prod_read.query(fp_query)[0]
    fp_before_at = prod_read.query("select now()::text as at")[0]["at"]
    files = []
    for schema, table, flt, why in TABLES:
        q = (SETTINGS + f"select pg_catalog.now()::text as read_at, coalesce(pg_catalog.json_agg(r order by r), '[]'::json) as rows "
             f"from (select (t.*)::text as r from {schema}.{table} t where {flt}) q")
        res = prod_read.query(q)[0]
        rows = res["rows"] if isinstance(res["rows"], list) else json.loads(res["rows"])
        for r in rows:
            for pat in SECRET_PATTERNS:
                if pat.search(r):
                    raise SystemExit(f"refusing: a row of {schema}.{table} matches a secret pattern ({pat.pattern})")
        doc = {"table": f"{schema}.{table}", "filter": flt, "why": why, "read_at": res["read_at"],
               "count": len(rows), "rows": rows}
        path = os.path.join(a.out, f"{schema}.{table}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=0)
            fh.write("\n")
        data = open(path, "rb").read()
        files.append({"table": f"{schema}.{table}", "rows": len(rows), "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest(), "read_at": res["read_at"]})
        print(f"  {schema}.{table:<40} {len(rows):>7} rows", file=sys.stderr)
    fp_after = prod_read.query(fp_query)[0]
    fp_after_at = prod_read.query("select now()::text as at")[0]["at"]

    manifest = {
        "exported_by": "lab/engine/lib/export_reference_data.py",
        "depot": TWIN,
        "finished_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "world_fingerprint": {"before": fp_before, "before_read_at": fp_before_at,
                              "after": fp_after, "after_read_at": fp_after_at,
                              "stable_during_export": fp_before == fp_after},
        "tables": files,
        "excluded": EXCLUDED,
    }
    with open(os.path.join(a.out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
        fh.write("\n")
    total = sum(f["rows"] for f in files)
    print(f"== {len(files)} tables, {total} rows; world fingerprint stable during export: {fp_before == fp_after}",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
