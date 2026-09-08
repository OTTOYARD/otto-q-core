"""The declared catalog of things the load harness may point at.

WHY A CATALOG RATHER THAN A --sql FLAG. A load number is only interesting if
you can say what was loaded, and a free-text flag makes every result a
one-off that nobody can reproduce or compare. Each target here is a named,
committed thing with a stated safety class, so a result file names a target
and the target names the SQL.

SAFETY CLASSES, and they are enforced by the harness, not by convention:

  read_only   The statement cannot write. The harness runs these freely.
  writes      The statement can write. The harness REFUSES to run these
              without --i-know-this-writes AND a --depot that is not the
              flagship. There are none today; the class exists so that the
              first one to be added arrives with the guard already around it.

WHAT IS DELIBERATELY NOT HERE. Nothing that starts a sim run, tears a depot
down, or advances a tick. The harness measures the SERVED path — what a
vehicle or an interface asks for and waits on — and a tick is a batch job,
which is the other clock entirely (db/checks/0133).
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Target:
    """One declared thing to load.

    `sql` is a pgbench script body. `params` names every :variable it uses;
    the harness refuses to run a target whose params were not all supplied,
    because pgbench silently substitutes an empty string for an unset
    variable and the statement then measures a syntax error very quickly.
    """
    name: str
    layer: str            # "db" — a statement on a connection
    safety: str           # "read_only" | "writes"
    what_it_represents: str
    sql: str
    params: tuple = ()
    note: str = ""


#: The floor. Measured with the same client, the same connection settings and
#: the same concurrency as every real target, so the difference between a
#: target and the floor is the part that belongs to the engine rather than to
#: the network, the pooler, TLS, or the harness's own overhead.
#:
#: This is the single most load-bearing idea in this file. db/checks/0133 got
#: into trouble by quoting a latency with no floor beside it: 24-47 ms sounds
#: like the engine until you notice nobody measured what an EMPTY round trip
#: costs on the same path. If the floor is 22 ms, the engine's share is 2-25
#: ms and the sentence changes completely.
FLOOR = Target(
    name="floor",
    layer="db",
    safety="read_only",
    what_it_represents="an empty round trip: connection, protocol, network, pooler",
    sql="SELECT 1;\n",
    note="never edit this to do work; its whole value is that it does none",
)

TARGETS: dict[str, Target] = {t.name: t for t in (
    FLOOR,

    Target(
        name="running_run",
        layer="db",
        safety="read_only",
        what_it_represents=(
            "the cheapest real question in the engine: which sim run owns this "
            "depot right now. Every run-scoped read starts here"),
        sql="SELECT public.ottoq_depot_running_run(:depot::uuid);\n",
        params=("depot",),
        note=(
            "also the function 0223 hoisted out of a per-row filter. Its "
            "single-call cost was never the problem — 8,756 calls where one "
            "would do was — so a fast number here is expected and is NOT "
            "evidence about 0223"),
    ),

    Target(
        name="charger_load_kw",
        layer="db",
        safety="read_only",
        what_it_represents=(
            "the site load meter: how many kW is this depot drawing at this "
            "instant. The reading the power cap is compared against"),
        sql=("SELECT twin.ottoq_sim_compute_charger_load_kw"
             "(:depot::uuid, :clock::timestamptz);\n"),
        params=("depot", "clock"),
        note=(
            "0223's subject. G21's FIX 2 is still open: the surviving cost is a "
            "sequential scan of ocpp_sessions, so this target is the before "
            "measurement for a fix that has not been written yet"),
    ),

    Target(
        name="kpi_five",
        layer="db",
        safety="read_only",
        what_it_represents=(
            "the five canonical KPIs for one archived run — what a dashboard "
            "asks for, and the heaviest read the product serves"),
        sql="SELECT public.ottoq_kpi_five(:run::uuid);\n",
        params=("run",),
        note=(
            "0181-0190 took this from 54.6 s to 50.9 ms on a single call. "
            "Whether it holds up at concurrency is exactly what has never "
            "been measured"),
    ),

    Target(
        name="cert_matrix",
        layer="db",
        safety="read_only",
        what_it_represents=(
            "the certification matrix — the read behind every determinism "
            "claim we make, and the one an outside reviewer would run"),
        sql="SELECT * FROM public.ottoq_cert_matrix(:since::timestamptz);\n",
        params=("since",),
    ),
)}


def get(name: str) -> Target:
    if name not in TARGETS:
        raise KeyError(
            f"no declared target {name!r}. Declared: {sorted(TARGETS)}. "
            f"Add it to load/targets.py with a safety class and a sentence "
            f"about what it represents — a load number whose target is a "
            f"command-line string is a number nobody can reproduce.")
    return TARGETS[name]
