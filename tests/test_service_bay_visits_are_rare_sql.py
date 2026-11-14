"""db/migrations/0837 and 0838, EXECUTED: a service bay visit is rare (CLAUDE.md rule 15).

WHY THIS EXISTS. Chase, 2026-11-14: "more than two or three vehicles a day to visit the service bay would be way too
much." Two generators made over a hundred a day at the twin depot. busy_day scaled every car's maintenance interval by
0.01 and its calibration interval by 0.02 (0837 sets both to 1). And the 'service_manifest' feed plan drew maintenance,
calibration, a cosmetic repair and a fault repair on every arrival, whatever the car's mileage (0838 promotes version 2:
the two scheduled services at 0, since 0715 writes them when a car's own interval is due, and the two repairs rare).
Executed here on minimal stand-ins (the tables and the promotion door the two files touch):
  - 0837 changes the two scales and nothing else in any scenario, keeps the wear phase on, refuses while a run is
    running, refuses a row or a loader that is not the one read, and refuses a second apply;
  - 0838 writes version 2 as version 1 but for four numbers, promotes it under a person's name, leaves version 1
    superseded, draws no maintenance and no calibration in 400 arrivals, and refuses the same things.
The loader and the observer are pinned by md5 in each file's P1; here the pin is pointed at the stand-in, which is said
where it is done. It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import re
import subprocess
import tempfile
import uuid

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
N37 = "0837_a_busy_day_no_longer_shortens_every_cars_maintenance_interval"
N38 = "0838_scheduled_service_comes_from_a_cars_own_interval_and_a_fault_is_rare"
M37 = os.path.join(ROOT, "db", "migrations", N37 + ".sql")
M38 = os.path.join(ROOT, "db", "migrations", N38 + ".sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
BUSY = ('{"wear_phase":{"enabled":true,"soil_seed_fraction":0.85},"policy_overrides":{"reserve_margin_pct":30},'
        '"vehicle_overrides":{"pm_interval_km_scale":0.01,"calib_interval_h_scale":0.02},"target_deployed_fraction":0.45}')
PLAN1 = ('{"adjustable":["probabilities.*"],"probabilities":{"sensor_clean":0.2,"exterior_wash":0.2,"interior_tidy":0.35,'
         '"mechanical_pm":0.05,"cosmetic_repair":0.02,"sensor_calibration":0.04,"interior_deep_clean":0.1},'
         '"probability_clamp":[0.005,0.9],"wash_cadence_cycles":3}')

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

STUB = f"""
CREATE SCHEMA twin;
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
INSERT INTO public.ottoq_cert_lineage VALUES ('0715_stand_in', true, 'stand-in', now(), true);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid, status text);
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, home_depot_id uuid, category text);
INSERT INTO public.vehicles VALUES (gen_random_uuid(), '{DEPOT}', 'autonomous');
CREATE TABLE public.ottoq_sim_scenarios (scenario_code text PRIMARY KEY, fleet_overrides jsonb);
INSERT INTO public.ottoq_sim_scenarios VALUES ('normal_day', NULL), ('heat_wave', '{{}}'), ('busy_day', '{BUSY}');
-- stand-in loader: only its md5 is read (0837 P1)
CREATE FUNCTION public.ottoq_scenario_apply_fleet_overrides(uuid) RETURNS jsonb LANGUAGE sql AS 'SELECT NULL::jsonb';
CREATE TABLE public.ottoq_feed_plans (plan_id uuid PRIMARY KEY, var_key text, version integer, status text, method text,
  plan jsonb, provenance jsonb, authored_by text, rationale text, created_at timestamptz DEFAULT now(),
  UNIQUE (var_key, version));
CREATE TABLE public.ottoq_feed_plan_promotions (promotion_id bigserial, plan_id uuid, var_key text, version integer,
  replaced_plan uuid, replaced_ver integer, promoted_by text, reason text, authored_by text,
  promoted_at timestamptz DEFAULT now());
INSERT INTO public.ottoq_feed_plans VALUES (gen_random_uuid(), 'service_manifest', 1, 'active', 'policy', '{PLAN1}',
  '{{}}', 'dossier_v1', 'r');
CREATE FUNCTION public.ottoq_feed_plan(p text) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT plan FROM public.ottoq_feed_plans WHERE var_key = p AND status = 'active' ORDER BY version DESC LIMIT 1 $$;
-- stand-in for 0716's door: the status moves and the promotion row, as the live function writes them
CREATE FUNCTION public.ottoq_feed_plan_promote(p_plan_id uuid, p_by text, p_reason text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_new public.ottoq_feed_plans; v_old public.ottoq_feed_plans;
BEGIN
  SELECT * INTO v_new FROM public.ottoq_feed_plans WHERE plan_id = p_plan_id;
  SELECT * INTO v_old FROM public.ottoq_feed_plans
   WHERE var_key = v_new.var_key AND status = 'active' ORDER BY version DESC LIMIT 1;
  UPDATE public.ottoq_feed_plans SET status = 'superseded' WHERE var_key = v_new.var_key AND status = 'active';
  UPDATE public.ottoq_feed_plans SET status = 'active' WHERE plan_id = v_new.plan_id;
  INSERT INTO public.ottoq_feed_plan_promotions (plan_id, var_key, version, replaced_plan, replaced_ver, promoted_by,
                                                 reason, authored_by)
  VALUES (v_new.plan_id, v_new.var_key, v_new.version, v_old.plan_id, v_old.version, p_by, p_reason, v_new.authored_by);
  RETURN jsonb_build_object('ok', true, 'var_key', v_new.var_key, 'version', v_new.version,
                            'replaced_version', v_old.version, 'promoted_by', p_by);
END $$;
-- stand-in observer: the four draws as the live body makes them (probability x long-tail 0.5 x the 80%-of-interval
-- step 4 for the two scheduled services; fault_repair_p, default 0.02). The live body is pinned by md5 in 0838 P1.
CREATE FUNCTION twin.ottoq_sim_observe_asset(p_vehicle_id uuid, p_sim_run_id uuid, p_run uuid, p_seed bigint,
                                             p_clock timestamptz, p_depot_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_plan jsonb := public.ottoq_feed_plan('service_manifest');
        r numeric := (hashtext(p_seed::text || p_clock::text) & 65535) / 65536.0;
BEGIN
  RETURN jsonb_build_object(
    'mechanical_pm', r < LEAST(0.95, (v_plan #>> '{{probabilities,mechanical_pm}}')::numeric * 0.5 * 4),
    'sensor_calibration', r < LEAST(0.95, (v_plan #>> '{{probabilities,sensor_calibration}}')::numeric * 0.5 * 4),
    'cosmetic_repair', r < (v_plan #>> '{{probabilities,cosmetic_repair}}')::numeric * 0.5,
    'fault', r < COALESCE((v_plan ->> 'fault_repair_p')::numeric, 0.02));
END $$;
"""


@pytest.fixture()
def db():
    name = f"ottoq_svc_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, _, err = d.run(STUB)
        assert rc == 0, f"stub did not load: {err}"
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d, path, fn):
    """Run a migration with its md5 pin pointed at this database's stand-in for `fn` (the pin itself is tested by
    running the file as committed, where it must refuse)."""
    md5 = d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE proname = '{fn}'")
    with open(path) as f:
        sql = f.read()
    pinned = re.findall(r"IS DISTINCT FROM '([0-9a-f]{32})'", sql)
    assert len(pinned) == 1, pinned
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as t:
        t.write(sql.replace(pinned[0], md5))
    try:
        return d.file(t.name)
    finally:
        os.unlink(t.name)


def test_0837_sets_the_two_scales_to_one_and_changes_nothing_else(db):
    before = db.val("SELECT string_agg(scenario_code || COALESCE(fleet_overrides::text, 'null'), '|' ORDER BY 1) "
                    "FROM ottoq_sim_scenarios WHERE scenario_code <> 'busy_day'")
    rc, err = _apply(db, M37, "ottoq_scenario_apply_fleet_overrides")
    assert rc == 0, err
    fo = db.json("SELECT fleet_overrides FROM ottoq_sim_scenarios WHERE scenario_code = 'busy_day'")
    assert fo["vehicle_overrides"] == {"pm_interval_km_scale": 1, "calib_interval_h_scale": 1}
    assert fo["wear_phase"] == {"enabled": True, "soil_seed_fraction": 0.85}
    assert fo["policy_overrides"] == {"reserve_margin_pct": 30} and fo["target_deployed_fraction"] == 0.45
    assert db.val("SELECT string_agg(scenario_code || COALESCE(fleet_overrides::text, 'null'), '|' ORDER BY 1) "
                  "FROM ottoq_sim_scenarios WHERE scenario_code <> 'busy_day'") == before
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{N37}'") == "truetrue"
    rc, err = _apply(db, M37, "ottoq_scenario_apply_fleet_overrides")
    assert rc != 0 and "0837 P2: already applied" in err


def test_0837_refuses_a_running_run_a_row_not_as_read_and_a_loader_not_as_read(db):
    rc, err = db.file(M37)                                  # as committed: the stand-in loader is not the one read
    assert rc != 0 and "0837 P1: the scenario loader is not the function read" in err
    db.val("INSERT INTO ottoq_sim_runs VALUES (gen_random_uuid(), 'running')")
    rc, err = _apply(db, M37, "ottoq_scenario_apply_fleet_overrides")
    assert rc != 0 and "0837 P0: a run is running" in err
    db.val("UPDATE ottoq_sim_runs SET status = 'completed'")
    db.val("UPDATE ottoq_sim_scenarios SET fleet_overrides = jsonb_set(fleet_overrides, "
           "'{vehicle_overrides,pm_interval_km_scale}', '0.5') WHERE scenario_code = 'busy_day'")
    rc, err = _apply(db, M37, "ottoq_scenario_apply_fleet_overrides")
    assert rc != 0 and "0837 P1: busy_day's vehicle_overrides are not the ones read" in err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name LIKE '0837%'") == "0"


def test_0837_refuses_to_leave_another_scenario_scaling_an_interval(db):
    db.val("""UPDATE ottoq_sim_scenarios SET fleet_overrides = '{"vehicle_overrides":{"calib_interval_h_scale":0.1}}'
               WHERE scenario_code = 'heat_wave'""")
    rc, err = _apply(db, M37, "ottoq_scenario_apply_fleet_overrides")
    assert rc != 0 and "0837 V1 FAILED: 1 scenario(s) still scale a maintenance interval" in err
    assert db.val("SELECT fleet_overrides #>> '{vehicle_overrides,pm_interval_km_scale}' FROM ottoq_sim_scenarios "
                  "WHERE scenario_code = 'busy_day'") == "0.01"          # rolled back whole


def _ready38(d):
    rc, err = _apply(d, M37, "ottoq_scenario_apply_fleet_overrides")
    assert rc == 0, err


def test_0838_promotes_version_two_with_four_numbers_changed(db):
    _ready38(db)
    draws = ("SELECT count(*) FILTER (WHERE (o ->> 'mechanical_pm')::boolean) || '/' || "
             "count(*) FILTER (WHERE (o ->> 'sensor_calibration')::boolean) FROM generate_series(1, 400) g, "
             "LATERAL twin.ottoq_sim_observe_asset((SELECT id FROM vehicles LIMIT 1), NULL, NULL, 838 + g, "
             "'2026-11-14 15:00:00+00'::timestamptz + (g || ' minutes')::interval, NULL) o")
    pm, cal = (int(x) for x in db.val(draws).split("/"))
    assert pm > 0 and cal > 0                                # version 1 draws both
    rc, err = _apply(db, M38, "ottoq_sim_observe_asset")
    assert rc == 0, err
    assert "0838 V2 PASSED: 400 arrivals drew 0 maintenance, 0 calibration" in err
    assert db.val(draws) == "0/0"
    rows = db.json("SELECT jsonb_agg(jsonb_build_object('v', version, 'st', status, 'plan', plan, 'by', authored_by) "
                   "ORDER BY version) FROM ottoq_feed_plans WHERE var_key = 'service_manifest'")
    assert [(r["v"], r["st"]) for r in rows] == [(1, "superseded"), (2, "active")]
    old, new = rows[0]["plan"], rows[1]["plan"]
    assert new["probabilities"]["mechanical_pm"] == 0 and new["probabilities"]["sensor_calibration"] == 0
    assert new["probabilities"]["cosmetic_repair"] == 0.001 and new["fault_repair_p"] == 0.002
    for k in ("sensor_clean", "exterior_wash", "interior_tidy", "interior_deep_clean"):
        assert new["probabilities"][k] == old["probabilities"][k]
    assert {k: v for k, v in new.items() if k not in ("probabilities", "fault_repair_p")} == \
           {k: v for k, v in old.items() if k != "probabilities"}
    assert db.val("SELECT promoted_by || '/' || replaced_ver FROM ottoq_feed_plan_promotions") == \
           "Chase (delegated to Claude Code: 0838)/1"
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{N38}'") == "truetrue"
    rc, err = _apply(db, M38, "ottoq_sim_observe_asset")
    assert rc != 0 and "0838 P2: already applied" in err


def test_0838_refuses_out_of_order_a_running_run_a_plan_and_an_observer_not_as_read(db):
    rc, err = _apply(db, M38, "ottoq_sim_observe_asset")
    assert rc != 0 and "0838 P1: 0715 or 0837 is not classified" in err
    _ready38(db)
    rc, err = db.file(M38)                                  # as committed: the stand-in observer is not the one read
    assert rc != 0 and "0838 P1: the observer is not the function read" in err
    db.val("INSERT INTO ottoq_sim_runs VALUES (gen_random_uuid(), 'running')")
    rc, err = _apply(db, M38, "ottoq_sim_observe_asset")
    assert rc != 0 and "0838 P0: a run is running" in err
    db.val("UPDATE ottoq_sim_runs SET status = 'completed'")
    db.val("UPDATE ottoq_feed_plans SET plan = plan || '{\"fault_repair_p\":0.02}' WHERE version = 1")
    rc, err = _apply(db, M38, "ottoq_sim_observe_asset")
    assert rc != 0 and "0838 P1: the active service_manifest plan is not version 1 as read" in err
    assert db.val("SELECT count(*) FROM ottoq_feed_plans") == "1"
