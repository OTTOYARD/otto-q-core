"""db/migrations/0840, EXECUTED on a scratch PostgreSQL: each fast-charger canopy's board is on the one-line.

WHY THIS EXISTS. 0840 widens 0810's kind CHECK, puts one board per fast-charger canopy under TX-AUX, adds a read-only
function that counts each board's OTTO-CLEAN ARMs at work, and replaces 0810's capture and design rule, which its P1
pins by md5. Here the tree, its sizing helpers, the design rule and the capture are 0810's own statements, taken from
the 0810 file, so P1's pins are 0810's and are not pointed at a stand-in. The other tables those statements read are
minimal stand-ins, on a 30-post depot shaped as the twin's (3 canopies, 5 posts a side). Executed:
  - 0840 applies unmodified, and the three bodies it stores hash as its APPLIED note says production's do;
  - it refuses a live run at the twin depot, a capture that is not 0810's, and a second apply, changing nothing;
  - the board-load function counts arms (distinct stalls), not atoms, inside each routine's own window, for its own
    run only, and gives an idle board its standby;
  - the capture writes each board as a leaf, TX-AUX carries their sum, and a second capture at one instant is a no-op;
  - the header's ROLLBACK, step by step, gives back 0810's two bodies, its tree and its CHECK, and 0840 applies again.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import glob
import os
import re
import subprocess
import uuid

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
M0810 = glob.glob(os.path.join(ROOT, "db", "migrations", "0810_*.sql"))[0]
M0840 = os.path.join(ROOT, "db", "migrations",
                     "0840_each_canopy_board_is_on_the_one_line_and_is_measured_from_its_working_arms.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "22222222-0840-4000-8000-000000000001"
OTHER = "22222222-0840-4000-8000-000000000002"
T = "2026-11-14 15:00:00+00"
MD5_0810 = {"ottoq_power_capture": "3ea79ddd37f41673d3f556e6c524bc92",
            "ottoq_power_one_line_design": "e7f03b76c4d9fd3ebbfa671ad4a53218"}
MD5_0840 = {"ottoq_power_capture": "1ed53750b3f5ca68edf9677c7ce0ccf4",
            "ottoq_power_one_line_design": "e76817a2385e7c77651e44ea631b277d",
            "ottoq_power_canopy_board_load": "dcb1deb928123179cf05927806c8755f"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _statements(sql):
    """Split a migration into statements, honouring comments, quoted strings and dollar quotes."""
    out, buf, i, n = [], [], 0, len(sql)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j < 0 else j
            buf.append(sql[i:j]); i = j
        elif sql.startswith("/*", i):
            j = sql.find("*/", i) + 2
            buf.append(sql[i:j]); i = j
        elif c == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and sql.startswith("''", j):
                    j += 2
                elif sql[j] == "'":
                    break
                else:
                    j += 1
            buf.append(sql[i:j + 1]); i = j + 1
        elif c == "$" and re.match(r"\$[A-Za-z_]*\$", sql[i:]):
            tag = re.match(r"\$[A-Za-z_]*\$", sql[i:]).group(0)
            j = sql.find(tag, i + len(tag)) + len(tag)
            buf.append(sql[i:j]); i = j
        elif c == ";":
            out.append("".join(buf).strip()); buf = []; i += 1
        else:
            buf.append(c); i += 1
    if "".join(buf).strip():
        out.append("".join(buf).strip())
    return out


def _code(stmt):
    """A statement without its leading comment lines."""
    return re.sub(r"^(\s*--[^\n]*\n)+", "", stmt).strip()


WANTED = [r"CREATE TABLE public\.ottoq_power_nodes \(", r"CREATE (UNIQUE )?INDEX \w+ ON public\.ottoq_power_nodes ",
          r"CREATE FUNCTION public\.ottoq_power_standard_kva\(", r"CREATE FUNCTION public\.ottoq_power_thermal_step\(",
          r"CREATE FUNCTION public\.ottoq_power_aging_factor\(", r"CREATE FUNCTION public\.ottoq_power_one_line_design\(",
          r"INSERT INTO public\.ottoq_power_nodes\s+SELECT \* FROM public\.ottoq_power_one_line_design",
          r"CREATE TABLE public\.ottoq_power_node_ticks \(", r"CREATE INDEX \w+ ON public\.ottoq_power_node_ticks ",
          r"CREATE TABLE public\.ottoq_power_node_study \(", r"CREATE FUNCTION public\.ottoq_power_capture\("]


def _from_0810():
    picked, seen = [], set()
    for s in _statements(open(M0810).read()):
        code = _code(s)
        hits = [w for w in WANTED if re.match(w, code)]
        if hits:
            picked.append(code)
            seen.update(hits)
    assert seen == set(WANTED), f"0810's file no longer has: {sorted(set(WANTED) - seen)}"
    return ";\n".join(picked) + ";\n"


STUB = f"""
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END $r$;
CREATE SCHEMA ottoq;
CREATE TYPE public.ocpp_session_status AS ENUM ('pending', 'active', 'completed', 'faulted');
CREATE TABLE public.depots (id uuid PRIMARY KEY);
INSERT INTO public.depots VALUES ('{DEPOT}');
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, ocpp_identifier text, max_kw numeric,
  decommissioned_at timestamptz, station_state text, last_fault_payload jsonb);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid, stall_type text, canopy_code text, equipment_config jsonb,
  display_name text, ocpp_charger_id uuid);
CREATE TABLE public.ottoq_bess_units (bess_id uuid PRIMARY KEY, depot_id uuid, bess_identifier text, max_charge_kw numeric,
  max_discharge_kw numeric);
CREATE TABLE public.ottoq_canopy_state (depot_id uuid, nameplate_ac_kw numeric);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, scenario_code text,
  random_seed bigint);
CREATE TABLE public.ottoq_weather_snapshots (depot_id uuid, sim_run_id uuid, sim_clock_at timestamptz, ambient_temp_c numeric);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stall_id uuid, depot_id uuid,
  status public.ocpp_session_status, started_at timestamptz, ended_at timestamptz, sim_run_id uuid, last_meter_value jsonb);
CREATE TABLE public.ottoq_visit_needs (visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid, depot_id uuid,
  sim_run_id uuid, status text DEFAULT 'open', atoms jsonb, created_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial PRIMARY KEY, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text, taken_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, forces_dial_restart boolean,
  note text NOT NULL, classified_at timestamptz NOT NULL);
-- stand-ins: no certification in flight; a run is live when one is 'running'; the world is the depot's stalls
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE FUNCTION public.ottoq_depot_running_run(uuid) RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT sim_run_id FROM public.ottoq_sim_runs WHERE depot_id = $1 AND status = 'running' LIMIT 1 $$;
CREATE FUNCTION ottoq.ottoq_world_fingerprint_sections(uuid) RETURNS jsonb LANGUAGE sql STABLE AS
  $$ SELECT jsonb_build_object('stalls', md5(string_agg(id::text || stall_type, ',' ORDER BY id)))
       FROM public.stalls WHERE depot_id = $1 $$;
-- the twin depot's fast chargers: 3 canopies, 5 posts a side, 350 kW each; one battery; 600 kW of canopy solar
INSERT INTO public.ottoq_ocpp_chargers (charger_id, ocpp_identifier, max_kw)
SELECT md5('chg' || c || s || p)::uuid, format('OTTO-C%s-%s%s', c, s, p), 350
  FROM generate_series(1, 3) c, unnest(ARRAY['W', 'E']) s, generate_series(1, 5) p;
INSERT INTO public.stalls (id, depot_id, stall_type, canopy_code, equipment_config, display_name, ocpp_charger_id)
SELECT md5('stall' || c || s || p)::uuid, '{DEPOT}', 'dcfc', format('CANOPY-%s', lpad(c::text, 2, '0')),
       jsonb_build_object('canopy_side', s), format('Fast charger %s-%s%s', c, s, p), md5('chg' || c || s || p)::uuid
  FROM generate_series(1, 3) c, unnest(ARRAY['W', 'E']) s, generate_series(1, 5) p;
INSERT INTO public.ottoq_bess_units VALUES (gen_random_uuid(), '{DEPOT}', 'BESS-01', 1500, 1500);
INSERT INTO public.ottoq_canopy_state VALUES ('{DEPOT}', 200), ('{DEPOT}', 200), ('{DEPOT}', 200);
"""


@pytest.fixture()
def db():
    name = f"ottoq_0840_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, _, err = d.run(STUB)
        assert rc == 0, err
        rc, _, err = d.run(_from_0810())
        assert rc == 0, err
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _md5(d, fn):
    return d.val(f"SELECT md5(p.prosrc) FROM pg_proc p WHERE p.proname = '{fn}' AND p.pronamespace = 'public'::regnamespace")


def _apply(d):
    rc, err = d.file(M0840)
    return rc, err


def _atom(svc, stall, start, end, status="in_progress", done=None, by="stall_cabin_robot"):
    a = {"svc": svc, "performed_by": by, "robot_stall_id": stall, "status": status, "started_at": start, "ends_at": end}
    if done:
        a["done_at"] = done
    return a


def _visit(d, run, atoms):
    import json
    run_sql = "NULL" if run is None else f"'{run}'"
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, depot_id, sim_run_id, atoms)
              VALUES (gen_random_uuid(), '{DEPOT}', {run_sql}, $j${json.dumps(atoms)}$j$::jsonb) RETURNING 1""")


def _stall(d, canopy, side, post):
    return d.val(f"SELECT md5('stall' || '{canopy}' || '{side}' || '{post}')::uuid")


def test_the_0810_bodies_here_are_the_ones_0840_pins(db):
    for fn, h in MD5_0810.items():
        assert _md5(db, fn) == h, fn
    assert db.val(f"SELECT count(*) FROM public.ottoq_power_nodes WHERE depot_id = '{DEPOT}'") == "42"


def test_0840_applies_on_0810_and_stores_the_bodies_production_stores(db):
    rc, err = _apply(db)
    assert rc == 0, err
    for fn, h in MD5_0840.items():
        assert _md5(db, fn) == h, fn
    boards = db.json(f"""SELECT jsonb_agg(jsonb_build_object('code', node_code, 'parent', parent_code, 'canopy', canopy_code,
                                 'kw', rated_kw, 'arms', (provenance->>'arms')::int) ORDER BY node_code)
                           FROM public.ottoq_power_nodes WHERE depot_id = '{DEPOT}' AND kind = 'canopy_board'""")
    assert [b["code"] for b in boards] == ["BOARD-A", "BOARD-B", "BOARD-C"]
    assert {b["parent"] for b in boards} == {"TX-AUX"}
    assert [b["canopy"] for b in boards] == ["CANOPY-01", "CANOPY-02", "CANOPY-03"]
    assert all(float(b["kw"]) == 54 and b["arms"] == 10 for b in boards)
    aux = db.json(f"""SELECT jsonb_build_object('kva', rated_kva, 'conn', provenance->>'connected_kw', 'title', title)
                        FROM public.ottoq_power_nodes WHERE depot_id = '{DEPOT}' AND node_code = 'TX-AUX'""")
    assert float(aux["kva"]) == 2500 and float(aux["conn"]) == 1912
    assert aux["title"] == "Transformer TX-AUX (battery, building, canopy solar, canopy boards)"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0840_pre'") == "2"
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0840_%'") == "falsefalse"
    rc, _, err = db.run(f"""INSERT INTO public.ottoq_power_nodes (depot_id, node_code, parent_code, kind, rated_kw, title)
                            VALUES ('{DEPOT}', 'X', 'TX-AUX', 'nonsense', 1, 'x')""")
    assert rc != 0 and "ottoq_power_nodes_kind_check" in err
    # the probe V5 ran was rolled back
    assert db.val("SELECT count(*) FROM public.ottoq_power_node_ticks") == "0"


def test_0840_refuses_a_live_run_a_capture_not_0810s_and_a_second_apply(db):
    db.val(f"INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}', 'running', 'busy_day', 1) RETURNING 1")
    rc, err = _apply(db)
    assert rc != 0 and "0840 P0" in err
    assert db.val("SELECT count(*) FROM public.ottoq_power_nodes WHERE kind = 'canopy_board'") == "0"
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}' RETURNING 1")

    def swap(a, b):   # one comment word in the capture's body, changed in place by its own definition
        rc, _, err = db.run(f"""DO $s$ BEGIN EXECUTE replace(pg_get_functiondef(
            'public.ottoq_power_capture(uuid,uuid,timestamptz,numeric,numeric,numeric)'::regprocedure), '{a}', '{b}'); END $s$""")
        assert rc == 0, err
    swap("a second snapshot at one instant", "a second snapshot at one moment")
    assert _md5(db, "ottoq_power_capture") != MD5_0810["ottoq_power_capture"]
    rc, err = _apply(db)
    assert rc != 0 and "0840 P1" in err
    assert db.val("SELECT count(*) FROM public.ottoq_power_nodes WHERE kind = 'canopy_board'") == "0"
    swap("a second snapshot at one moment", "a second snapshot at one instant")
    assert _md5(db, "ottoq_power_capture") == MD5_0810["ottoq_power_capture"]

    rc, err = _apply(db)
    assert rc == 0, err
    rc, err = _apply(db)
    assert rc != 0 and "0840 P1" in err
    assert db.val("SELECT count(*) FROM public.ottoq_power_nodes WHERE kind = 'canopy_board'") == "3"
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0840_%'") == "1"


def test_the_board_load_counts_arms_inside_their_windows_for_their_run(db):
    rc, err = _apply(db)
    assert rc == 0, err
    a1, a2, a3, a4, a5 = (_stall(db, 1, "W", p) for p in range(1, 6))
    a6 = _stall(db, 1, "E", 1)
    b1, c1 = _stall(db, 2, "W", 1), _stall(db, 3, "W", 1)
    before, after, later = "2026-11-14 14:50:00+00", "2026-11-14 15:10:00+00", "2026-11-14 15:20:00+00"
    early = "2026-11-14 14:55:00+00"
    _visit(db, RUN, [
        _atom("interior_deep_clean", a1, before, after),                                   # an arm at work
        _atom("interior_tidy", a1, before, after, status="done", done=later),              # the same arm: one, not two
        _atom("interior_tidy", a2, before, early, status="done", done=after),              # ran past its plan: at work
        _atom("interior_tidy", a3, before, after, status="done", done=early),              # done before the instant
        _atom("interior_tidy", a4, before, after, status="cancelled"),                     # cancelled
        _atom("sensor_clean", a5, before, after, by="technician"),                         # not an arm
        _atom("interior_tidy", a6, after, later),                                          # not yet started
        _atom("interior_tidy", b1, before, after),                                         # canopy 2
    ])
    _visit(db, OTHER, [_atom("interior_tidy", c1, before, after)])                         # another run
    _visit(db, None, [_atom("interior_tidy", c1, before, after)])                          # no run
    db.val(f"INSERT INTO public.ottoq_visit_needs (depot_id, sim_run_id, atoms) VALUES ('{DEPOT}', '{RUN}', '{{}}') RETURNING 1")

    def load(run):
        run_sql = "NULL" if run is None else f"'{run}'"
        return db.json(f"""SELECT jsonb_object_agg(node_code, jsonb_build_object('w', working, 'kw', kw_ac, 'arms', arms))
                             FROM public.ottoq_power_canopy_board_load('{DEPOT}', {run_sql}, '{T}')""")

    r = load(RUN)
    assert r["BOARD-A"]["w"] == 2 and float(r["BOARD-A"]["kw"]) == 11.6        # 8 x 0.1 + 2 x (2.4 + 3)
    assert r["BOARD-B"]["w"] == 1 and float(r["BOARD-B"]["kw"]) == 6.3         # 9 x 0.1 + 5.4
    assert r["BOARD-C"]["w"] == 0 and float(r["BOARD-C"]["kw"]) == 1.0         # 10 idle arms at 0.1
    assert all(v["arms"] == 10 for v in r.values())
    assert load(OTHER)["BOARD-C"]["w"] == 1 and load(OTHER)["BOARD-A"]["w"] == 0
    assert load(None)["BOARD-C"]["w"] == 1 and load(None)["BOARD-A"]["w"] == 0


def test_the_capture_carries_each_board_and_tx_aux_their_sum(db):
    rc, err = _apply(db)
    assert rc == 0, err
    db.val(f"INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}', 'completed', 'busy_day', 1) RETURNING 1")
    a1, a2 = _stall(db, 1, "W", 1), _stall(db, 1, "E", 2)
    _visit(db, RUN, [_atom("interior_deep_clean", a1, "2026-11-14 14:50:00+00", "2026-11-14 15:00:20+00"),
                     _atom("interior_tidy", a2, "2026-11-14 14:58:00+00", "2026-11-14 15:00:20+00")])
    assert db.val(f"SELECT public.ottoq_power_capture('{DEPOT}', '{RUN}', '{T}', 100, -200, 50)") == "8"
    ticks = db.json(f"""SELECT jsonb_object_agg(node_code, kw_ac) FROM public.ottoq_power_node_ticks
                         WHERE sim_run_id = '{RUN}' AND sim_clock_at = '{T}'""")
    assert float(ticks["BOARD-A"]) == 11.6 and float(ticks["BOARD-B"]) == 1.0 and float(ticks["BOARD-C"]) == 1.0
    # TX-AUX: the building 100, the battery charging 200, the solar -50, and the three boards 13.6
    assert float(ticks["TX-AUX"]) == 263.6
    assert float(ticks["SERVICE"]) > 263.6     # and every transformer's no-load loss
    study = db.json(f"""SELECT jsonb_object_agg(node_code, jsonb_build_object('kind', kind, 'peak', peak_kw_ac, 'ticks', ticks))
                         FROM public.ottoq_power_node_study WHERE sim_run_id = '{RUN}' AND node_code LIKE 'BOARD-%'""")
    assert {v["kind"] for v in study.values()} == {"canopy_board"} and float(study["BOARD-A"]["peak"]) == 11.6
    # the same instant again is measured once
    assert db.val(f"SELECT public.ottoq_power_capture('{DEPOT}', '{RUN}', '{T}', 100, -200, 50)") == "0"
    # thirty seconds on, both routines have ended: the board is back to its standby
    assert db.val(f"SELECT public.ottoq_power_capture('{DEPOT}', '{RUN}', '{T}'::timestamptz + interval '30 seconds', 100, -200, 50)") == "8"
    assert db.val(f"""SELECT kw_ac FROM public.ottoq_power_node_ticks WHERE sim_run_id = '{RUN}' AND node_code = 'BOARD-A'
                       ORDER BY sim_clock_at DESC LIMIT 1""") == "1.00"
    assert db.val(f"SELECT ticks FROM public.ottoq_power_node_study WHERE sim_run_id = '{RUN}' AND node_code = 'BOARD-A'") == "2"


def test_the_rollback_in_the_header_gives_back_0810_and_0840_applies_again(db):
    tree_0810 = db.val(f"""SELECT md5(string_agg(node_code || coalesce(parent_code, '') || kind || coalesce(rated_kva::text, '')
                                   || coalesce(rated_kw::text, '') || title, ',' ORDER BY node_code))
                             FROM public.ottoq_power_nodes WHERE depot_id = '{DEPOT}'""")
    rc, err = _apply(db)
    assert rc == 0, err
    header = open(M0840).read().split("\nBEGIN;\n")[0]
    assert "ROLLBACK, in this order" in header
    rc, _, err = db.run(f"""
DO $rb$ DECLARE r record; BEGIN
  FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0840_pre' ORDER BY snapshot_id LOOP
    EXECUTE r.definition;
  END LOOP;
END $rb$;
DELETE FROM public.ottoq_power_nodes WHERE kind = 'canopy_board';
UPDATE public.ottoq_power_nodes t SET title = d.title, provenance = d.provenance
  FROM public.ottoq_power_one_line_design('{DEPOT}') d
 WHERE t.depot_id = '{DEPOT}' AND t.node_code = 'TX-AUX' AND d.node_code = 'TX-AUX';
ALTER TABLE public.ottoq_power_nodes DROP CONSTRAINT ottoq_power_nodes_kind_check,
  ADD CONSTRAINT ottoq_power_nodes_kind_check
    CHECK (kind IN ('utility_service', 'mv_switchgear', 'transformer', 'post', 'bess', 'solar', 'building'));
DROP FUNCTION public.ottoq_power_canopy_board_load(uuid, uuid, timestamptz);
DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0840_%';
""")
    assert rc == 0, err
    for fn, h in MD5_0810.items():
        assert _md5(db, fn) == h, fn
    assert db.val(f"""SELECT md5(string_agg(node_code || coalesce(parent_code, '') || kind || coalesce(rated_kva::text, '')
                             || coalesce(rated_kw::text, '') || title, ',' ORDER BY node_code))
                       FROM public.ottoq_power_nodes WHERE depot_id = '{DEPOT}'""") == tree_0810
    assert float(db.val(f"SELECT provenance->>'connected_kw' FROM public.ottoq_power_nodes WHERE node_code = 'TX-AUX'")) == 1750
    assert db.val("SELECT to_regprocedure('public.ottoq_power_canopy_board_load(uuid,uuid,timestamptz)') IS NULL") == "t"
    rc, err = _apply(db)
    assert rc == 0, err
    assert db.val("SELECT count(*) FROM public.ottoq_power_nodes WHERE kind = 'canopy_board'") == "3"
