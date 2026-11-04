#!/usr/bin/env python3
"""Drive the twin inside the lab: start an arm, tick it, digest it, fork it.

An ARM is started with exactly the statements one arm of public.ottoq_determinism_pair runs
(0421's GUC clear, the fleet reset from the seed, twin.ottoq_sim_start_run as 'cert_harness' with
fixed playback, 0152's run-scoped cuOpt quiesce, the 0.70 deployment prime), then ticked with
public.ottoq_sim_advance_tick -- so a lab arm is a certification arm, unpaced: a tick is 30 sim-
minutes whatever the CPU does, and a seed draws the same world every time.

It is digested with public.ottoq_ab_arm_atoms, the engine's own expression of the 14 atoms the
pair compares (plus the arrival stream), and per tick: events, decisions and commands bucketed
by the tick's sim-clock window, so two branches can be compared tick by tick.

A FORK is a SAVEPOINT in the arm's transaction. Branches run from it one after another; each is
digested, then rolled back to the savepoint. Two things do not roll back and the driver says
so instead of hiding them: sequences (ids minted in a later branch are higher; every atom is
id-blind, see 0216) and gen_random_uuid() (a minted uuid differs per branch; see the end-state
finding in the 2026-11-04 acceptance report). Each branch sets ottoq.sim_run_id itself (the GUC
hazard of 0329/0421).

Nothing here touches production. It runs against the lab database only.
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field

import psycopg

TWIN = "11111111-1111-1111-1111-111111111111"
SIM_START = "2026-09-01 02:00:00+00"  # ottoq_determinism_pair's default

PER_TICK_SQL = """
SELECT
 (SELECT md5(COALESCE(string_agg(
     event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                           THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||COALESCE(e.sim_clock_at::text,'-'),
     E'\\n' ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                     THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
    FROM ottoq_events e WHERE e.sim_run_id = %(run)s AND e.sim_clock_at > %(lo)s AND e.sim_clock_at <= %(hi)s) AS evt,
 (SELECT count(*) FROM ottoq_events e WHERE e.sim_run_id = %(run)s AND e.sim_clock_at > %(lo)s AND e.sim_clock_at <= %(hi)s) AS n_evt,
 (SELECT md5(COALESCE(string_agg(
     sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
     ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
     E'\\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                    COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
    FROM ottoq_decisions d WHERE d.sim_run_id = %(run)s AND d.sim_clock > %(lo)s AND d.sim_clock <= %(hi)s) AS dec,
 (SELECT count(*) FROM ottoq_decisions d WHERE d.sim_run_id = %(run)s AND d.sim_clock > %(lo)s AND d.sim_clock <= %(hi)s) AS n_dec,
 (SELECT md5(COALESCE(string_agg(
     issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
     E'\\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')), ''))
    FROM ottoq_vehicle_commands c WHERE c.sim_run_id = %(run)s AND c.issued_at > %(lo)s AND c.issued_at <= %(hi)s) AS cmd,
 (SELECT count(*) FROM ottoq_vehicle_commands c WHERE c.sim_run_id = %(run)s AND c.issued_at > %(lo)s AND c.issued_at <= %(hi)s) AS n_cmd
"""

# The end-state fingerprint's visit-needs hash with the minted robot_leg_id set aside -- the
# vn CTE of public.ottoq_boot_state_fingerprint, identical except that each atom loses that key.
# A DIAGNOSTIC only: it says whether two arms differ in anything BUT that minted id.
VIS_STRIPPED_SQL = """
WITH vn AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> %(run)s) AS fgn,
         md5(((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' - 'atoms')
              || jsonb_build_object('atoms',
                   CASE WHEN jsonb_typeof(t.atoms) = 'array'
                        THEN (SELECT COALESCE(jsonb_agg(x.e - 'robot_leg_id' ORDER BY x.o), '[]'::jsonb)
                                FROM jsonb_array_elements(t.atoms) WITH ORDINALITY x(e, o))
                        ELSE t.atoms END))::text) AS h
    FROM public.ottoq_visit_needs t
   WHERE t.depot_id = %(depot)s
     AND (t.sim_run_id IS NULL OR t.sim_run_id = %(run)s OR t.status::text IN ('open','in_progress','carried_over')))
SELECT md5(COALESCE(string_agg(h, '' ORDER BY h), '')) FROM vn WHERE NOT fgn
"""

ATOMS = ["fp", "h_cmd", "h_dec", "h_evt", "h_bkg", "h_nrg", "h_prop", "h_defr", "h_cal", "h_rule", "h_rcl", "h_sdr",
         "ticks", "endst"]
ATOM_NAMES = ["fingerprint", "commands", "decisions", "events", "bookings", "energy", "proposals", "deferrals",
              "calibration", "rules", "recalls", "sdrs", "tick_count", "end_state"]


@dataclass
class Arm:
    conn: psycopg.Connection
    seed: int
    scenario: str = "busy_day"
    depot: str = TWIN
    sim_start: str = SIM_START
    run: str | None = None
    boot: dict | None = None
    clocks: list = field(default_factory=list)  # sim clock after each tick, clocks[0] = start
    tick_seconds: list = field(default_factory=list)  # wall seconds per tick

    def q(self, sql: str, params=None):
        with self.conn.cursor() as c:
            c.execute(sql, params)
            return c.fetchall() if c.description else None

    def start(self) -> str:
        """One arm of ottoq_determinism_pair, statement for statement, up to its first tick."""
        self.q("SELECT set_config('ottoq.sim_run_id', 'none', true)")
        self.q("SELECT public.ottoq_tick_invariance_reset_fleet(%s, %s, %s)", (self.depot, self.seed, self.sim_start))
        self.run = str(self.q("SELECT twin.ottoq_sim_start_run(%s, %s::timestamptz, 60, %s, 'cert_harness')",
                              (self.scenario, self.sim_start, self.seed))[0][0])
        self.q("""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
                  VALUES ('run', %(r)s, 'cuopt_propose_enabled', 0, '0152_cert_quiesce'),
                         ('run', %(r)s, 'cuopt_first_refusal_max_defers', 0, '0152_cert_quiesce')
                  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = 0,
                    updated_by = '0152_cert_quiesce'""", {"r": self.run})
        self.q("SAVEPOINT lab_prime")
        try:
            self.q("SELECT twin.ottoq_sim_prime_deployment(%s, %s::timestamptz, 0.70)", (self.run, self.sim_start))
            self.q("RELEASE SAVEPOINT lab_prime")
        except psycopg.Error as e:  # the pair warns and goes on; so does the driver
            self.q("ROLLBACK TO SAVEPOINT lab_prime")
            print(f"WARNING prime failed: {e}")
        self.boot = self.q("SELECT public.ottoq_boot_state_fingerprint(%s, %s)", (self.depot, self.run))[0][0]
        self.clocks = [self.q("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (self.run,))[0][0]]
        return self.run

    def tick(self, n: int = 1) -> None:
        for _ in range(n):
            t0 = time.perf_counter()
            st = self.q("SELECT status, tick_count FROM ottoq_sim_runs WHERE sim_run_id = %s", (self.run,))[0]
            if st[0] != "running":
                raise RuntimeError(f"run {self.run} is {st[0]} at tick {st[1]}")
            self.q("SELECT * FROM public.ottoq_sim_advance_tick(%s)", (self.run,))
            self.tick_seconds.append(time.perf_counter() - t0)
            self.clocks.append(self.q("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s",
                                      (self.run,))[0][0])

    def set_run_dial(self, key: str, value, by: str = "lab_fork") -> None:
        """A run-scoped dial, written the way the pair writes its own (ottoq_policy_params, scope 'run')."""
        self.q("""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
                  VALUES ('run', %s, %s, %s, %s)
                  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value,
                    updated_by = EXCLUDED.updated_by""", (self.run, key, value, by))

    def digest(self) -> dict:
        atoms = self.q("SELECT public.ottoq_ab_arm_atoms(%s, %s)", (self.depot, self.run))[0][0]
        atoms["boot"] = self.boot
        # ottoq_ab_arm_atoms leaves out the calibration atom; the pair takes it from the boot image
        # (v_boot->'calibration'->>'h'), and so does this driver, or compare() would see None == None.
        atoms["h_cal"] = (self.boot or {}).get("calibration", {}).get("h")
        missing = [k for k in ATOMS if atoms.get(k) is None]
        if missing:
            raise RuntimeError(f"atoms missing from the digest: {missing}")
        atoms["vis_stripped"] = self.q(VIS_STRIPPED_SQL, {"run": self.run, "depot": self.depot})[0][0]
        per_tick = []
        for k in range(1, len(self.clocks)):
            row = self.q(PER_TICK_SQL, {"run": self.run, "lo": self.clocks[k - 1], "hi": self.clocks[k]})[0]
            per_tick.append({"tick": k, "clock": str(self.clocks[k]), "evt": row[0], "n_evt": row[1],
                             "dec": row[2], "n_dec": row[3], "cmd": row[4], "n_cmd": row[5]})
        atoms["per_tick"] = per_tick
        return json.loads(json.dumps(atoms, default=str))

    def finish(self) -> None:
        self.q("SELECT public.ottoq_sim_stop_and_reset(%s, 'determinism_arm_complete')", (self.run,))


# Settings whose value is a list of quoted names (PostgreSQL's GUC_LIST_QUOTE): set as one quoted string, the whole
# list becomes a single name. pg_db_role_setting stores them already in list syntax.
QUOTED_LIST_SETTINGS = {"search_path", "temp_tablespaces", "session_preload_libraries", "local_preload_libraries"}


def clone_database(admin: psycopg.Connection, template: str, name: str) -> float:
    """A replica: CREATE DATABASE ... TEMPLATE, plus the template's database-level settings, which CREATE DATABASE
    does not copy (lib/lab_server.sh also sets production's session settings server-wide). Returns seconds taken.

    The template must have no other session: no job scheduler runs on the lab server (sql/12_cron_standin.sql)."""
    t0 = time.perf_counter()
    admin.execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    admin.execute(f"CREATE DATABASE {name} TEMPLATE {template}")
    rows = admin.execute("""SELECT r.rolname, s.setconfig FROM pg_db_role_setting s
                              JOIN pg_database d ON d.oid = s.setdatabase LEFT JOIN pg_roles r ON r.oid = s.setrole
                             WHERE d.datname = %s""", (template,)).fetchall()
    for role, config in rows:
        for item in config:
            key, _, value = item.partition("=")
            target = f"ROLE {psycopg.sql.Identifier(role).as_string(admin)} IN DATABASE" if role else "DATABASE"
            # pg_db_role_setting stores a list-valued setting (search_path) in SQL list syntax, which must be written
            # back as a list; as one quoted literal it would become a single schema named after the whole list.
            rhs = value if key.lower() in QUOTED_LIST_SETTINGS else psycopg.sql.Literal(value).as_string(admin)
            admin.execute(f"ALTER {target} {name} SET {key} = {rhs}")
    return time.perf_counter() - t0


def compare(a: dict, b: dict) -> dict:
    """The pair's 14 atoms, a against b, plus the diagnostics this driver adds."""
    out = {"disagreeing_atoms": [], "end_state_sections": []}
    for key, name in zip(ATOMS, ATOM_NAMES):
        if a.get(key) != b.get(key):
            out["disagreeing_atoms"].append(name)
    if a.get("endst") != b.get("endst"):
        ea, eb = a.get("endst") or {}, b.get("endst") or {}
        for sec in sorted(set(ea) | set(eb)):
            if ea.get(sec) != eb.get(sec):
                out["end_state_sections"].append(sec)
    # end state with the minted robot_leg_id set aside: every section equal, and the stripped vis hash equal
    ea, eb = dict(a.get("endst") or {}), dict(b.get("endst") or {})
    for e, x in ((ea, a), (eb, b)):
        if "visit_needs" in e:
            vn = json.loads(json.dumps(e["visit_needs"]))
            vn["vis"]["h"] = x.get("vis_stripped")
            e["visit_needs"] = vn
    out["end_state_equal_without_robot_leg_id"] = ea == eb
    out["arrivals_equal"] = a.get("h_arr") == b.get("h_arr")
    ta, tb = a.get("per_tick", []), b.get("per_tick", [])
    out["first_tick_that_differs"] = next(
        (x["tick"] for x, y in zip(ta, tb) if (x["evt"], x["dec"], x["cmd"]) != (y["evt"], y["dec"], y["cmd"])), None)
    out["ticks_compared"] = min(len(ta), len(tb))
    return out
