"""scripts/editor_paste.py, EXECUTED: the text a person pastes into the Supabase SQL editor runs the file, or nothing.

WHY THIS EXISTS. On 2026-10-23 the SQL editor delivered 0765 with Windows line endings and its first anchor matched
nothing (the transaction rolled back), and the editor's own line after the file's COMMIT failed on a temporary table and
showed a red error after the work was saved (scripts/APPLYING.md §4 c). The editor sends the whole paste as one simple
query, which is what `psql -c` sends, so every apply here goes that way. On a probe migration that patches a function by
an anchor that spans a line end, as 0755 and 0765 do:
  - the file as it is, with CRLF, fails at its anchor (0765's failure, reproduced);
  - the paste, with bare newlines or with CRLF, leaves the database byte for byte as the file applied with psql does;
  - a paste changed in one character is refused whole, before anything runs;
  - a premise that fails inside the file rolls back everything it did;
  - a line the editor appends after the COMMIT fails without undoing the work;
  - statements given with --then run only once the file has committed;
  - and the wrapper refuses a file it cannot carry whole.
The database tests SKIP where no scratch PostgreSQL is reachable.
"""
import hashlib
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

sys.path.insert(0, os.path.join(base.ROOT, "scripts"))
import editor_paste as ep  # noqa: E402

PROBE = """-- migration-version: PENDING
-- migration-name:    editor_paste_probe
--
-- 9999  A probe: a temporary patch table, a function patched by an anchor that spans a line end, a new function whose
--       body holds a line end inside a string, a premise, and an UPDATE. Box drawing and a section sign: ══ § ══

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $p1$
BEGIN
  IF EXISTS (SELECT 1 FROM public.probe_lineage WHERE name = '9999') THEN
    RAISE EXCEPTION '9999 P1: already applied';
  END IF;
END $p1$;

CREATE TEMP TABLE _9999_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _9999_patch VALUES
  (1, $o1$  RETURN 1;
END
$o1$,
   $n1$  RETURN 2;   -- 9999
END
$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.probe_fn()'::regprocedure);
  FOR p IN SELECT * FROM _9999_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '9999: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
END $patch$;

CREATE FUNCTION public.probe_new() RETURNS text LANGUAGE plpgsql AS $fn$
BEGIN
  RETURN 'two
lines';
END $fn$;

UPDATE public.probe_dials SET v = 1 WHERE k = 'x';

SELECT count(*) FROM public.probe_dials;

INSERT INTO public.probe_lineage (name) VALUES ('9999');

COMMIT;
"""

FN = """CREATE OR REPLACE FUNCTION public.probe_fn() RETURNS int LANGUAGE plpgsql AS $f$
BEGIN
  RETURN 1;
END
$f$;
"""
WORLD = """CREATE TABLE public.probe_lineage (name text PRIMARY KEY);
CREATE TABLE public.probe_dials (k text PRIMARY KEY, v int);
INSERT INTO public.probe_dials VALUES ('x', 0);
""" + FN
RESET = ("DROP FUNCTION IF EXISTS public.probe_new(); DELETE FROM public.probe_lineage; "
         "UPDATE public.probe_dials SET v = 0;\n" + FN)

# probe_fn's body, probe_new's body, the dial, the lineage
STATE = """SELECT concat_ws('|',
  coalesce((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.probe_fn()')), ''),
  coalesce((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.probe_new()')), ''),
  coalesce((SELECT v::text FROM public.probe_dials WHERE k = 'x'), ''),
  coalesce((SELECT string_agg(name, ',') FROM public.probe_lineage), ''))"""


@pytest.fixture()
def probe(tmp_path):
    p = tmp_path / "9999_editor_paste_probe.sql"
    p.write_text(PROBE, encoding="utf-8")
    return p


def _body(text):
    lines = text.split("\n")
    return "\n".join(ln for i, ln in enumerate(lines) if ln not in ("BEGIN;", "COMMIT;"))


# ── the wrapper, without a database ──

def test_the_paste_carries_the_file_less_its_transaction_lines(probe):
    text, body_md5, file_md5 = ep.paste_for(probe)
    body = _body(PROBE)
    assert body_md5 == hashlib.md5(body.encode()).hexdigest()
    assert file_md5 == hashlib.md5(PROBE.encode()).hexdigest()
    assert "\n" + body + ep.INNER in text
    assert text.count("\nBEGIN;\n") == 1 and text.count("\nCOMMIT;\n") == 1
    assert f"IS DISTINCT FROM '{body_md5}'" in text and "9999: the pasted text is not the file as written" in text


@pytest.mark.parametrize("bad, why", [
    (PROBE.replace("\nBEGIN;\n", "\n"), "found 0 and 1"),
    (PROBE.replace("\nCOMMIT;\n", "\nCOMMIT;\nBEGIN;\nCOMMIT;\n"), "found 2 and 2"),
    (PROBE.replace("\nCOMMIT;\n", "\n").replace("\nBEGIN;\n", "\nCOMMIT;\nBEGIN;\n"), "found 1 and 1"),
    (PROBE.replace("\nBEGIN;\n", "\nSET search_path = public;\nBEGIN;\n"), "outside its BEGIN"),
    (PROBE + "SELECT 1;\n", "outside its BEGIN"),
    (PROBE.replace("\n", "\r\n"), "carriage return"),
    (PROBE.replace("$fn$", "$ottoq_file_text$"), "wrapper's own tag"),
], ids=["no BEGIN", "two transactions", "COMMIT before BEGIN", "a statement before", "a statement after", "CRLF",
        "the wrapper's tag"])
def test_a_file_it_cannot_carry_whole_is_refused(tmp_path, bad, why):
    p = tmp_path / "9999_bad.sql"
    p.write_text(bad, encoding="utf-8", newline="")
    with pytest.raises(ep.NotWrappable, match=why):
        ep.paste_for(p)


def test_then_must_be_its_own_transaction(probe):
    with pytest.raises(ep.NotWrappable, match="--then"):
        ep.paste_for(probe, "SELECT 1;\n")
    text, _, _ = ep.paste_for(probe, "BEGIN;\nSELECT 1;\nCOMMIT;\n")
    assert text.endswith("\nBEGIN;\nSELECT 1;\nCOMMIT;\n")
    assert text.index(f"END {ep.OUTER};\nCOMMIT;\n") < text.index("BEGIN;\nSELECT 1;")


def test_every_pending_file_but_the_withdrawn_one_can_be_pasted():
    """The editor is the path when the connector holds a write, so a PENDING file should be one it can carry. 0288 is
    withdrawn (db/checks/0223) and has no transaction at all; 0791 belongs to the architecture session's numbering."""
    mig = os.path.join(base.ROOT, "db", "migrations")
    refused = []
    for name in sorted(os.listdir(mig)):
        if not name.endswith(".sql"):
            continue
        with open(os.path.join(mig, name), encoding="utf-8") as f:
            if "migration-version: PENDING" not in f.read(300):
                continue
        try:
            ep.paste_for(os.path.join(mig, name))
        except ep.NotWrappable:
            refused.append(name[:4])
    assert set(refused) <= {"0288", "0791"}, refused


# ── on a scratch database, as the editor sends it: the whole paste as one simple query ──

@pytest.fixture()
def db():
    if not base._server_up():
        pytest.skip("no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")
    name = f"ottoq_paste_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        d.val(WORLD)
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _send(d, text):
    """The whole text as one simple query, as the SQL editor sends it."""
    rc, _, err = d.run(text)
    return rc, err


def test_the_file_with_crlf_fails_at_its_anchor(db):
    rc, err = _send(db, PROBE.replace("\n", "\r\n"))
    assert rc != 0 and "9999: anchor 1 matches 0 times, not 1" in err
    assert db.val(STATE).split("|")[1:] == ["", "0", ""]


@pytest.mark.parametrize("crlf", [False, True])
def test_the_paste_leaves_the_database_as_the_file_does(db, probe, tmp_path, crlf):
    rc, err = db.file(str(probe))
    assert rc == 0, err
    by_file = db.val(STATE)
    assert by_file.split("|")[2:] == ["1", "9999"]
    db.val(RESET)
    assert db.val(STATE).split("|")[1:] == ["", "0", ""]
    text, _, _ = ep.paste_for(probe)
    rc, err = _send(db, text.replace("\n", "\r\n") if crlf else text)
    assert rc == 0, err
    assert db.val(STATE) == by_file
    assert db.val("SELECT probe_new() = E'two\\nlines'") == "t"
    assert db.val("SELECT count(*) FROM pg_proc WHERE proname LIKE 'probe%' AND strpos(prosrc, chr(13)) > 0") == "0"


def test_a_changed_paste_is_refused_before_anything_runs(db, probe):
    text, body_md5, _ = ep.paste_for(probe)
    changed = text.replace("SET v = 1 WHERE", "SET v = 7 WHERE")
    assert changed != text
    rc, err = _send(db, changed.replace("\n", "\r\n"))
    assert rc != 0 and "9999: the pasted text is not the file as written" in err and body_md5 in err
    assert db.val(STATE).split("|")[1:] == ["", "0", ""]


def test_a_failed_premise_inside_the_file_rolls_back_everything(db, probe):
    db.val("INSERT INTO public.probe_lineage VALUES ('9999')")
    before = db.val(STATE)
    rc, err = _send(db, ep.paste_for(probe)[0])
    assert rc != 0 and "9999 P1: already applied" in err
    assert db.val(STATE) == before


def test_the_editors_line_after_the_commit_changes_nothing(db, probe):
    text, _, _ = ep.paste_for(probe)
    editor = ("\n-- Added by Supabase: enable Row Level Security on newly created tables\n"
              "ALTER TABLE _9999_patch ENABLE ROW LEVEL SECURITY;\n")
    rc, err = _send(db, (text + editor).replace("\n", "\r\n"))
    assert rc != 0 and 'relation "_9999_patch" does not exist' in err
    assert db.val(STATE).split("|")[2:] == ["1", "9999"]


def test_then_runs_only_once_the_file_has_committed(db, probe):
    then = "BEGIN;\nUPDATE public.probe_dials SET v = v + 10 WHERE k = 'x';\nCOMMIT;\n"
    text, _, _ = ep.paste_for(probe, then)
    rc, err = _send(db, text.replace("\n", "\r\n"))
    assert rc == 0, err
    assert db.val("SELECT v FROM public.probe_dials WHERE k = 'x'") == "11"
    rc, err = _send(db, text)
    assert rc != 0 and "9999 P1: already applied" in err
    assert db.val("SELECT v FROM public.probe_dials WHERE k = 'x'") == "11"


def test_several_files_make_one_paste_and_the_first_failure_stops_the_rest(db, probe, tmp_path):
    """The five ready files of 2026-10-23 went as one paste: each is its own transaction, so a file that fails leaves
    those before it committed and runs nothing after it, its --then statements included."""
    again = tmp_path / "9998_the_same_probe_again.sql"
    again.write_text(PROBE, encoding="utf-8")
    then = tmp_path / "then.sql"
    then.write_text("BEGIN;\nUPDATE public.probe_dials SET v = v + 10 WHERE k = 'x';\nCOMMIT;\n", encoding="utf-8")
    out = tmp_path / "paste.sql"
    assert ep.main([str(probe), str(again), "--then", f"9998={then}", "-o", str(out)]) == 0
    text = out.read_bytes().decode("utf-8")
    assert text.count(f"DO {ep.OUTER}") == 2 and text.index("9999_editor_paste_probe") < text.index("9998_the_same")
    rc, err = _send(db, text.replace("\n", "\r\n"))
    assert rc != 0 and "9999 P1: already applied" in err
    assert db.val(STATE).split("|")[2:] == ["1", "9999"]
    assert ep.main([str(probe), str(again), "--then", str(then)]) == 1
