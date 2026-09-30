"""db/migrations/0603, EXECUTED: two scheduler tasks orphaned in June stop stranding a car on every OTTO-Q test day.

WHY THIS EXISTS. HW.005 (critical, block, at task_start) counts a car's active rows in schedule_tasks with no run scope,
and four rows there have been `in_progress` since 2026-06-04, two on one Zoox. So the shield refused that car's task start
on every tick of every OTTO-Q test day, and it never charged, while the fifo and greedy seats charged it to 100%. 0603
cancels the four rows. Executed here against the live evaluator carried byte for byte (tests/fixtures/legacy_task_stub.sql):

  * before, HW.005 refuses the Zoox; after, it passes, and a genuine second active task is still refused;
  * the table's trigger records each change under no run and under the migration's name (0421's idiom);
  * 0603 refuses while anything is in flight, when the active rows are not the four measured, when the table has been
    written since June, when the evaluator is not the one measured, and a second time; its header's rollback restores it.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_sweep_sql.py.
"""
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "legacy_task_stub.sql")
M0603 = os.path.join(ROOT, "db", "migrations",
                     "0603_a_legacy_task_from_june_no_longer_strands_a_car_on_every_otto_q_test_day.sql")
ZOOX = "229f655b-803c-47c0-95fd-ca8adb9d8ef0"
HW005 = f"(public.ottoq_eval_hw_005_vehicle_one_task('vehicle', '{ZOOX}', '{{}}', '{{}}'))"


def _conn_args():
    if os.environ.get("PGHOST"):
        return ["-h", os.environ["PGHOST"], "-p", os.environ.get("PGPORT", "5432"),
                "-U", os.environ.get("PGUSER", "postgres")]
    return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"]


def _server_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-Atc", "select 1"], capture_output=True, text=True)
    return p.returncode == 0


pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


@pytest.fixture()
def db():
    name = f"ottoq_lt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def test_the_stub_carries_the_live_evaluator(db):
    assert db.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_eval_hw_005_vehicle_one_task'") \
        == "e744b5be3b873f4758a186f9b320f032"


def test_hw005_passes_the_zoox_after_0603_and_still_refuses_a_real_second_task(db):
    assert db.val(f"SELECT {HW005}.reason") == "vehicle has 2 simultaneously active tasks"
    rc, err = db.file(M0603)
    assert rc == 0, err
    assert db.val(f"SELECT {HW005}.passed") == "t"
    assert db.val("SELECT count(*) FROM public.schedule_tasks WHERE status = 'cancelled' AND notes LIKE '0603 (G313)%'") \
        == "4"
    assert db.val("SELECT count(*) FROM public.schedule_tasks WHERE status = 'completed'") == "1"   # untouched
    # the change is on the record under no run and the migration's name
    assert db.val("""SELECT string_agg(DISTINCT run_ctx || '/' || actor_type || '/' || actor_id || '/' || new_status, ',')
                       FROM public.stub_task_events""") == "none/migration/0603/cancelled"
    # a genuine pair of active tasks is still refused: the rule is untouched
    db.val(f"""INSERT INTO public.schedule_tasks (id, vehicle_id, status) VALUES
                 (gen_random_uuid(), '{ZOOX}', 'in_progress'), (gen_random_uuid(), '{ZOOX}', 'vehicle_en_route')""")
    assert db.val(f"SELECT {HW005}.passed") == "f"
    assert db.val("SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage") \
        == "true/true"


def test_0603_refuses_what_it_did_not_measure(db):
    db.val("UPDATE public.stub_in_flight SET n = 1")
    rc, err = db.file(M0603)
    assert rc != 0 and "0603 P0" in err
    db.val("UPDATE public.stub_in_flight SET n = 0")
    db.val(f"INSERT INTO public.schedule_tasks (id, vehicle_id, status, updated_at) VALUES "
           f"('00000000-0000-0000-0000-00000000f005', '{ZOOX}', 'in_progress', '2026-06-01 00:00+00')")
    rc, err = db.file(M0603)
    assert rc != 0 and "0603 P1: the active schedule tasks are not the four measured" in err
    db.val("DELETE FROM public.schedule_tasks WHERE id = '00000000-0000-0000-0000-00000000f005'")
    db.val("""INSERT INTO public.schedule_tasks (id, vehicle_id, status, created_at, updated_at) VALUES
                ('00000000-0000-0000-0000-00000000f006', gen_random_uuid(), 'completed', now(), now())""")
    rc, err = db.file(M0603)
    assert rc != 0 and "0603 P1: something has written schedule_tasks since June" in err
    db.val("DELETE FROM public.schedule_tasks WHERE id = '00000000-0000-0000-0000-00000000f006'")
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_005_vehicle_one_task(p_entity_type text, p_entity_id uuid,
                p_context jsonb, p_parameters jsonb) RETURNS ottoq_rule_result LANGUAGE sql STABLE AS
              $$ SELECT ROW(true, 'x', NULL, '{}'::jsonb, NULL)::ottoq_rule_result $$""")
    rc, err = db.file(M0603)
    assert rc != 0 and "0603 P1: HW.005's evaluator is not the one measured" in err


def test_0603_refuses_twice_and_its_rollback_restores_the_rows(db):
    rc, err = db.file(M0603)
    assert rc == 0, err
    rc, err = db.file(M0603)
    assert rc != 0 and "0603 P1: already applied" in err
    header = open(M0603).read().split("-- ROLLBACK: ", 1)[1].split("\n\nBEGIN;", 1)[0]
    lines = [(l[2:] if l.startswith("--") else l).strip() for l in header.splitlines()]
    db.val(" ".join(lines[:3]))
    db.val(lines[3].rstrip(".").replace("'.", "'") + ";")
    assert db.val("SELECT count(*) FROM public.schedule_tasks WHERE status = 'in_progress'") == "4"
    assert db.val(f"SELECT {HW005}.passed") == "f"
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
